#requires -Version 5.1
<#
ForestMap service manager for Windows (PowerShell)
Intended location:
  <repo>\scripts\forestmapctl.ps1

Works with the CURRENT local repository (no git clone / no git pull).

Commands:
  install/start/stop/restart/status/logs/update/env-init/deps
  backup-db restore-db safe-remove remove purge

Notes:
- No systemd on Windows.
- "install" = deps check/install + .env init + docker compose up -d --build + waits + health checks
- "update"  = rebuild/restart from current local sources
- "safe-remove" keeps Docker volumes/data
- "remove" deletes Docker volumes/data
- "purge" deletes volumes/data and project directory (dangerous)
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = "",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = "Stop"

# -----------------------------
# Globals / paths
# -----------------------------
$AppName = "forestmap"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRootDefault = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$InstallDir = if ($env:FORESTMAP_DIR) { $env:FORESTMAP_DIR } else { $ProjectRootDefault }

$InfraDir = Join-Path $InstallDir "infra"
$ComposeFile = Join-Path $InfraDir "docker-compose.yml"
$EnvFile = Join-Path $InfraDir ".env"
$EnvExample = Join-Path $InfraDir ".env.example"
$BackupDirDefault = Join-Path $InstallDir "backups"

# -----------------------------
# Helpers
# -----------------------------
function Write-Info([string]$Message)  { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)    { Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Warn2([string]$Message) { Write-Host "WARN: $Message" -ForegroundColor Yellow }
function Write-Err2([string]$Message)  { Write-Host "ERROR: $Message" -ForegroundColor Red }

function Test-Cmd([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Require-ProjectLayout {
    if (-not (Test-Path $InstallDir))  { throw "Project dir not found: $InstallDir" }
    if (-not (Test-Path $InfraDir))    { throw "Infra dir not found: $InfraDir" }
    if (-not (Test-Path $ComposeFile)) { throw "docker-compose.yml not found: $ComposeFile" }
}

function Normalize-ToLF {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path $Path)) { return }

    # Read as text and normalize CRLF -> LF, save UTF-8 (no BOM)
    $content = [System.IO.File]::ReadAllText($Path)
    $content = $content -replace "`r`n", "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

function Get-EnvMap {
    $map = @{}
    if (-not (Test-Path $EnvFile)) { return $map }

    Normalize-ToLF -Path $EnvFile

    foreach ($line in Get-Content -Path $EnvFile) {
        if ($null -eq $line) { continue }
        $trim = $line.Trim()
        if ($trim -eq "" -or $trim.StartsWith("#")) { continue }

        $idx = $trim.IndexOf("=")
        if ($idx -lt 1) { continue }

        $key = $trim.Substring(0, $idx).Trim()
        $val = $trim.Substring($idx + 1)
        $map[$key] = $val
    }
    return $map
}

function Get-ComposeBaseArgs {
    Require-ProjectLayout
    $args = @("compose")
    if (Test-Path $EnvFile) {
        $args += @("--env-file", $EnvFile)
    }
    $args += @("-f", $ComposeFile)
    return ,$args
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $all = @(Get-ComposeBaseArgs) + $Args
    & docker @all
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed (exit $LASTEXITCODE): $($Args -join ' ')"
    }
}

function Random-Secret {
    param([int]$Bytes = 18)
    $buf = New-Object byte[] $Bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
    $s = [Convert]::ToBase64String($buf)
    # sanitize for env values / URLs
    return ($s.Replace("+", "A").Replace("/", "b").Replace("=", ""))
}

function Wait-HttpReady {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutSec = 90,
        [int]$SleepSec = 2
    )

    Write-Info "Waiting for $Name: $Url (timeout ${TimeoutSec}s)"
    $start = Get-Date

    while ($true) {
        try {
            # Try GET first (works everywhere)
            Invoke-WebRequest -Uri $Url -Method GET -UseBasicParsing -TimeoutSec 5 | Out-Null
            Write-Host "   OK: $Name" -ForegroundColor Green
            return $true
        } catch {
            # HEAD fallback (some endpoints redirect; still acceptable)
            try {
                Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 5 | Out-Null
                Write-Host "   OK: $Name" -ForegroundColor Green
                return $true
            } catch {
                # continue polling
            }
        }

        $elapsed = (Get-Date) - $start
        if ($elapsed.TotalSeconds -ge $TimeoutSec) {
            Write-Warn2 "$Name not ready after ${TimeoutSec}s"
            return $false
        }

        Start-Sleep -Seconds $SleepSec
    }
}

function Wait-Services {
    $envMap = Get-EnvMap
    $apiPort = if ($envMap.ContainsKey("API_PORT")) { $envMap["API_PORT"] } else { "8081" }
    $nginxPort = if ($envMap.ContainsKey("NGINX_PORT")) { $envMap["NGINX_PORT"] } else { "8443" }

    $ok = $true
    if (-not (Wait-HttpReady -Name "API" -Url "http://localhost:$apiPort/healthz" -TimeoutSec 90 -SleepSec 2)) { $ok = $false }
    if (-not (Wait-HttpReady -Name "Gateway API" -Url "http://localhost:$nginxPort/api/healthz" -TimeoutSec 90 -SleepSec 2)) { $ok = $false }
    if (-not (Wait-HttpReady -Name "Keycloak via nginx" -Url "http://localhost:$nginxPort/auth/" -TimeoutSec 180 -SleepSec 3)) { $ok = $false }

    return $ok
}

function Health-Check {
    Write-Info "Health checks (best effort)"
    $envMap = Get-EnvMap
    $apiPort = if ($envMap.ContainsKey("API_PORT")) { $envMap["API_PORT"] } else { "8081" }
    $nginxPort = if ($envMap.ContainsKey("NGINX_PORT")) { $envMap["NGINX_PORT"] } else { "8443" }

    Write-Host "  - API:     http://localhost:$apiPort/healthz"
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:$apiPort/healthz" -UseBasicParsing -TimeoutSec 5
        Write-Host "    $($r.StatusCode) $($r.Content)" -ForegroundColor Green
    } catch {
        Write-Host "    (failed) $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "  - Gateway: http://localhost:$nginxPort/api/healthz"
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:$nginxPort/api/healthz" -UseBasicParsing -TimeoutSec 5
        Write-Host "    $($r.StatusCode) $($r.Content)" -ForegroundColor Green
    } catch {
        Write-Host "    (failed) $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "  - Keycloak via nginx: http://localhost:$nginxPort/auth/"
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:$nginxPort/auth/" -Method Head -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 5
        Write-Host "    $($r.StatusCode)" -ForegroundColor Green
    } catch {
        # Redirects often throw in PowerShell when MaxRedirection=0
        if ($_.Exception.Response) {
            try {
                $code = [int]$_.Exception.Response.StatusCode
                Write-Host "    $code (redirect is OK)" -ForegroundColor Green
            } catch {
                Write-Host "    (failed) $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "    (failed) $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# -----------------------------
# Dependencies
# -----------------------------
function Install-Dependencies {
    Write-Info "Checking dependencies"

    $hasDocker = Test-Cmd "docker"
    $hasGit = Test-Cmd "git"
    $hasWinget = Test-Cmd "winget"

    if ($hasDocker) {
        try {
            & docker version | Out-Null
            Write-Host "  - docker: OK" -ForegroundColor Green
        } catch {
            Write-Warn2 "docker CLI found, but Docker Desktop/daemon may not be running."
        }

        try {
            & docker compose version | Out-Null
            Write-Host "  - docker compose: OK" -ForegroundColor Green
        } catch {
            Write-Warn2 "docker compose plugin is not available."
            $hasDocker = $false
        }
    } else {
        Write-Warn2 "docker not found"
    }

    if ($hasGit) {
        Write-Host "  - git: OK" -ForegroundColor Green
    } else {
        Write-Warn2 "git not found"
    }

    if ((-not $hasDocker) -or (-not $hasGit)) {
        if (-not $hasWinget) {
            Write-Warn2 "winget not found. Install dependencies manually:"
            Write-Host "    - Docker Desktop (with WSL2)"
            Write-Host "    - Git"
            return
        }

        Write-Info "Attempting to install missing dependencies via winget (may require admin / UAC)"
        if (-not $hasGit) {
            try {
                & winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements
            } catch {
                Write-Warn2 "Failed to install Git via winget. Install manually."
            }
        }

        if (-not $hasDocker) {
            try {
                & winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements
            } catch {
                Write-Warn2 "Failed to install Docker Desktop via winget. Install manually."
            }
            Write-Warn2 "After Docker Desktop installation, start Docker Desktop once and wait until engine is running."
        }
    }

    Write-Info "Dependency check complete"
}

# -----------------------------
# .env initialization
# -----------------------------
function Init-Env {
    Require-ProjectLayout

    if (Test-Path $EnvFile) {
        Write-Info ".env already exists: $EnvFile"
        Normalize-ToLF -Path $EnvFile
        return
    }

    if (-not (Test-Path $EnvExample)) {
        throw ".env.example not found: $EnvExample"
    }

    Normalize-ToLF -Path $EnvExample

    Write-Info "Creating .env from .env.example"
    Copy-Item -Path $EnvExample -Destination $EnvFile -Force
    Normalize-ToLF -Path $EnvFile

    $forestDb = Random-Secret
    $kcDb = Random-Secret
    $kcAdmin = Random-Secret

    $content = [System.IO.File]::ReadAllText($EnvFile)
    $content = $content -replace '(^POSTGRES_PASSWORD=).*$','$1' + $forestDb
    $content = $content -replace '(^KEYCLOAK_DB_PASSWORD=).*$','$1' + $kcDb
    $content = $content -replace '(^KEYCLOAK_ADMIN_PASSWORD=).*$','$1' + $kcAdmin

    $content = $content.Replace("CHANGE_ME_FOREST_DB_PASSWORD", $forestDb)
    $content = $content.Replace("CHANGE_ME_KEYCLOAK_DB_PASSWORD", $kcDb)
    $content = $content.Replace("CHANGE_ME_KEYCLOAK_ADMIN_PASSWORD", $kcAdmin)

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($EnvFile, $content, $utf8NoBom)

    Write-Ok "Created .env with generated secrets: $EnvFile"
}

# -----------------------------
# Docker stack operations
# -----------------------------
function Install-Cmd {
    Install-Dependencies
    Require-ProjectLayout
    Init-Env

    Write-Info "Starting stack (build + up)"
    Invoke-Compose up -d --build

    if (-not (Wait-Services)) {
        Write-Warn2 "Some services did not become ready in time. Showing logs snapshot..."
        try { Invoke-Compose ps } catch {}
        try { Invoke-Compose logs --tail=80 api nginx db keycloak keycloak-db } catch {}
    }

    Health-Check
    Write-Ok "Installed & running from local repository."
    Write-Host "   - Project dir: $InstallDir"
    Write-Host "   - Env file:    $EnvFile"
}

function Start-Cmd {
    Require-ProjectLayout
    Write-Info "Starting stack"
    Invoke-Compose up -d

    if (-not (Wait-Services)) {
        Write-Warn2 "Some services did not become ready in time."
    }

    Health-Check
}

function Stop-Cmd {
    Require-ProjectLayout
    Write-Info "Stopping stack"
    Invoke-Compose down
}

function Restart-Cmd {
    Write-Info "Restarting stack"
    Stop-Cmd
    Start-Cmd
}

function Status-Cmd {
    Require-ProjectLayout
    Write-Info "docker compose ps"
    Invoke-Compose ps
}

function Logs-Cmd {
    param([string]$Service = "")
    Require-ProjectLayout
    if ([string]::IsNullOrWhiteSpace($Service)) {
        Invoke-Compose logs --tail=200 -f
    } else {
        Invoke-Compose logs --tail=200 -f $Service
    }
}

function Update-Cmd {
    Require-ProjectLayout
    Write-Info "Rebuild/restart from current local sources"
    Invoke-Compose up -d --build

    if (-not (Wait-Services)) {
        Write-Warn2 "Some services did not become ready in time."
    }
    Health-Check
}

# -----------------------------
# DB backup / restore
# -----------------------------
function Get-DbEnvOrThrow {
    $envMap = Get-EnvMap
    foreach ($k in @("POSTGRES_USER","POSTGRES_PASSWORD","POSTGRES_DB")) {
        if (-not $envMap.ContainsKey($k) -or [string]::IsNullOrWhiteSpace($envMap[$k])) {
            throw "Missing $k in $EnvFile"
        }
    }
    return $envMap
}

function Backup-Db-Cmd {
    Require-ProjectLayout
    $envMap = Get-DbEnvOrThrow

    $dbService = if ($env:FORESTMAP_DB_SERVICE) { $env:FORESTMAP_DB_SERVICE } else { "db" }
    $backupDir = if ($env:FORESTMAP_BACKUP_DIR) { $env:FORESTMAP_BACKUP_DIR } else { $BackupDirDefault }

    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $outFile = Join-Path $backupDir "${AppName}_db_${ts}.sql"

    Write-Info "Ensuring DB container is running"
    Invoke-Compose up -d $dbService

    Write-Info "Creating DB backup"
    Write-Host "   service : $dbService"
    Write-Host "   file    : $outFile"

    # NOTE: In Windows PowerShell, native redirection may re-encode output.
    # For pg_dump SQL text this is usually fine. If you need exact byte preservation,
    # use PowerShell 7+ or add a dedicated native process capture helper.
    $base = @(Get-ComposeBaseArgs)
    & docker @($base + @(
        "exec","-T",
        "-e","PGPASSWORD=$($envMap["POSTGRES_PASSWORD"])",
        $dbService,
        "pg_dump",
        "-U",$envMap["POSTGRES_USER"],
        "-d",$envMap["POSTGRES_DB"]
    )) | Out-File -FilePath $outFile -Encoding utf8

    if ($LASTEXITCODE -ne 0) {
        throw "Backup failed (exit $LASTEXITCODE)"
    }

    Write-Ok "Backup created: $outFile"
    Write-Host ""
    Write-Host "Restore examples:"
    Write-Host "  .\scripts\forestmapctl.ps1 restore-db `"$outFile`""
    Write-Host "  .\scripts\forestmapctl.ps1 restore-db    # latest backup from default dir"
}

function Read-TextFileMaybeGzip {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path.ToLower().EndsWith(".gz")) {
        $fs = [System.IO.File]::OpenRead($Path)
        try {
            $gz = New-Object System.IO.Compression.GzipStream($fs, [System.IO.Compression.CompressionMode]::Decompress)
            try {
                $sr = New-Object System.IO.StreamReader($gz)
                try {
                    return $sr.ReadToEnd()
                } finally { $sr.Dispose() }
            } finally { $gz.Dispose() }
        } finally { $fs.Dispose() }
    } else {
        return [System.IO.File]::ReadAllText($Path)
    }
}

function Restore-Db-Cmd {
    param([string]$InputFile = "")

    Require-ProjectLayout
    $envMap = Get-DbEnvOrThrow
    $dbService = if ($env:FORESTMAP_DB_SERVICE) { $env:FORESTMAP_DB_SERVICE } else { "db" }
    $backupDir = if ($env:FORESTMAP_BACKUP_DIR) { $env:FORESTMAP_BACKUP_DIR } else { $BackupDirDefault }

    if ([string]::IsNullOrWhiteSpace($InputFile)) {
        if (Test-Path $backupDir) {
            $candidates = Get-ChildItem -Path $backupDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '\.sql(\.gz)?$' } |
                Sort-Object LastWriteTime -Descending
            if ($candidates.Count -gt 0) {
                $InputFile = $candidates[0].FullName
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($InputFile)) {
        throw "Backup file not specified and no backups found in: $backupDir"
    }
    if (-not (Test-Path $InputFile)) {
        throw "Backup file not found: $InputFile"
    }

    Write-Host "⚠️  RESTORE will overwrite app DB contents in service '$dbService'." -ForegroundColor Yellow
    Write-Host "   Backup file: $InputFile"
    $ans = Read-Host "Подтвердить восстановление БД? (yes/NO)"
    if ($ans -ne "yes") {
        Write-Info "Cancelled."
        return
    }

    Write-Info "Ensuring DB container is running"
    Invoke-Compose up -d $dbService

    $base = @(Get-ComposeBaseArgs)
    $pgPassArg = "PGPASSWORD=$($envMap["POSTGRES_PASSWORD"])"

    Write-Info "Recreating public schema + PostGIS extension"
    & docker @($base + @("exec","-T","-e",$pgPassArg,$dbService,"psql","-v","ON_ERROR_STOP=1","-U",$envMap["POSTGRES_USER"],"-d",$envMap["POSTGRES_DB"],"-c","DROP SCHEMA IF EXISTS public CASCADE;"))
    if ($LASTEXITCODE -ne 0) { throw "Failed to drop schema" }

    & docker @($base + @("exec","-T","-e",$pgPassArg,$dbService,"psql","-v","ON_ERROR_STOP=1","-U",$envMap["POSTGRES_USER"],"-d",$envMap["POSTGRES_DB"],"-c","CREATE SCHEMA public;"))
    if ($LASTEXITCODE -ne 0) { throw "Failed to create schema" }

    & docker @($base + @("exec","-T","-e",$pgPassArg,$dbService,"psql","-v","ON_ERROR_STOP=1","-U",$envMap["POSTGRES_USER"],"-d",$envMap["POSTGRES_DB"],"-c","GRANT ALL ON SCHEMA public TO PUBLIC;"))
    if ($LASTEXITCODE -ne 0) { throw "Failed to grant PUBLIC on schema" }

    & docker @($base + @("exec","-T","-e",$pgPassArg,$dbService,"psql","-v","ON_ERROR_STOP=1","-U",$envMap["POSTGRES_USER"],"-d",$envMap["POSTGRES_DB"],"-c","GRANT ALL ON SCHEMA public TO ""$($envMap["POSTGRES_USER"])"";"))
    if ($LASTEXITCODE -ne 0) { throw "Failed to grant owner on schema" }

    & docker @($base + @("exec","-T","-e",$pgPassArg,$dbService,"psql","-v","ON_ERROR_STOP=1","-U",$envMap["POSTGRES_USER"],"-d",$envMap["POSTGRES_DB"],"-c","CREATE EXTENSION IF NOT EXISTS postgis;"))
    if ($LASTEXITCODE -ne 0) { throw "Failed to create postgis extension" }

    Write-Info "Restoring from backup"
    $sqlText = Read-TextFileMaybeGzip -Path $InputFile

    $sqlText | & docker @($base + @(
        "exec","-T",
        "-e",$pgPassArg,
        $dbService,
        "psql","-v","ON_ERROR_STOP=1",
        "-U",$envMap["POSTGRES_USER"],
        "-d",$envMap["POSTGRES_DB"]
    ))
    if ($LASTEXITCODE -ne 0) {
        throw "Restore failed (exit $LASTEXITCODE)"
    }

    Write-Ok "Restore completed."
}

# -----------------------------
# Remove / purge
# -----------------------------
function Safe-Remove-Cmd {
    Require-ProjectLayout

    Write-Host "⚠️  SAFE REMOVE will delete:" -ForegroundColor Yellow
    Write-Host "   - Docker containers/networks for this compose project (compose down)"
    Write-Host "   - orphan containers for this compose file"
    Write-Host "It will KEEP:"
    Write-Host "   - Docker volumes (DB data, uploads, etc.)"
    Write-Host "   - project directory: $InstallDir"
    $ans = Read-Host "Подтвердить safe remove? (yes/NO)"
    if ($ans -ne "yes") {
        Write-Info "Cancelled."
        return
    }

    try { Invoke-Compose down --remove-orphans } catch {}
    Write-Ok "Safe remove completed (volumes/data preserved)."
}

function Remove-Cmd {
    Require-ProjectLayout

    Write-Host "⚠️  REMOVE will delete:" -ForegroundColor Yellow
    Write-Host "   - Docker containers/networks/volumes for this compose project (compose down -v)"
    Write-Host "   - orphan containers for this compose file"
    Write-Host "It will NOT delete the project directory: $InstallDir"
    Write-Host "NOTE: volumes include DB data and uploaded files."
    $ans = Read-Host "Подтвердить удаление стека С ДАННЫМИ? (yes/NO)"
    if ($ans -ne "yes") {
        Write-Info "Cancelled."
        return
    }

    try { Invoke-Compose down -v --remove-orphans } catch {}
    Write-Ok "Stack removed (project files kept, data volumes deleted)."
}

function Purge-Cmd {
    Require-ProjectLayout

    Write-Host "⚠️  PURGE will delete EVERYTHING:" -ForegroundColor Yellow
    Write-Host "   - Docker containers/networks/volumes (compose down -v)"
    Write-Host "   - project directory $InstallDir"
    Write-Host "   - this script too, if it is inside the project directory"
    $ans = Read-Host "Подтвердить ПОЛНОЕ удаление? (yes/NO)"
    if ($ans -ne "yes") {
        Write-Info "Cancelled."
        return
    }

    try { Invoke-Compose down -v --remove-orphans } catch {}

    # Best effort delete (script may be running from inside this dir)
    Start-Sleep -Seconds 1
    try {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
        Write-Ok "Purged."
    } catch {
        Write-Warn2 "Could not fully delete project dir while script is running."
        Write-Warn2 "Close PowerShell handles and delete manually: $InstallDir"
    }
}

# -----------------------------
# Menu
# -----------------------------
function Show-Paths {
    Write-Host ""
    Write-Host "APP_NAME      = $AppName"
    Write-Host "SCRIPT_DIR    = $ScriptDir"
    Write-Host "INSTALL_DIR   = $InstallDir"
    Write-Host "INFRA_DIR     = $InfraDir"
    Write-Host "COMPOSE_FILE  = $ComposeFile"
    Write-Host "ENV_FILE      = $EnvFile"
    Write-Host "ENV_EXAMPLE   = $EnvExample"
    Write-Host "BACKUP_DIR    = $(if ($env:FORESTMAP_BACKUP_DIR) { $env:FORESTMAP_BACKUP_DIR } else { $BackupDirDefault })"
}

function Pause-Menu {
    Write-Host ""
    [void](Read-Host "Нажмите Enter для возврата в меню")
}

function Menu-Logs {
    $svc = Read-Host "Имя сервиса для логов (api/nginx/db/keycloak/keycloak-db/frontend) или пусто для всех"
    Write-Host "Ctrl+C чтобы выйти из tail."
    if ([string]::IsNullOrWhiteSpace($svc)) { Logs-Cmd } else { Logs-Cmd -Service $svc }
}

function Menu-BackupRestore {
    Write-Host ""
    Write-Host "1) Создать бэкап (backup-db)"
    Write-Host "2) Восстановить последний бэкап"
    Write-Host "3) Восстановить из указанного файла"
    Write-Host "0) Назад"
    $c = Read-Host "Выберите пункт [0-3]"
    switch ($c) {
        "1" { Backup-Db-Cmd }
        "2" { Restore-Db-Cmd }
        "3" { $f = Read-Host "Путь к .sql или .sql.gz"; Restore-Db-Cmd -InputFile $f }
        "0" { }
        default { Write-Warn2 "Неверный пункт." }
    }
}

function Interactive-Menu {
    while ($true) {
        Clear-Host
        Write-Host "========================================"
        Write-Host "       ForestMap Service Manager"
        Write-Host "             (Windows)"
        Write-Host "========================================"
        Write-Host "PROJECT_ROOT: $InstallDir"
        Write-Host ""
        Write-Host " 1) Установка (deps + .env + up)"
        Write-Host " 2) Запуск сервиса"
        Write-Host " 3) Остановка сервиса"
        Write-Host " 4) Перезапуск сервиса"
        Write-Host " 5) Статус"
        Write-Host " 6) Логи"
        Write-Host " 7) Обновление (rebuild текущего кода)"
        Write-Host " 8) Создать .env из .env.example (env-init)"
        Write-Host " 9) Установить/проверить зависимости"
        Write-Host "10) Бэкап БД"
        Write-Host "11) Восстановление БД из бэкапа"
        Write-Host "12) Safe Remove (удалить стек, но СОХРАНИТЬ volumes/данные)"
        Write-Host "13) Remove (удалить стек + volumes/данные)"
        Write-Host "14) Purge (удалить всё, включая папку проекта)"
        Write-Host "15) Показать пути/переменные"
        Write-Host " 0) Выход"
        Write-Host ""

        $choice = Read-Host "Выберите пункт [0-15]"
        try {
            switch ($choice) {
                "1"  { Install-Cmd; Pause-Menu }
                "2"  { Start-Cmd; Pause-Menu }
                "3"  { Stop-Cmd; Pause-Menu }
                "4"  { Restart-Cmd; Pause-Menu }
                "5"  { Status-Cmd; Pause-Menu }
                "6"  { Menu-Logs; Pause-Menu }
                "7"  { Update-Cmd; Pause-Menu }
                "8"  { Init-Env; Pause-Menu }
                "9"  { Install-Dependencies; Pause-Menu }
                "10" { Backup-Db-Cmd; Pause-Menu }
                "11" { Menu-BackupRestore; Pause-Menu }
                "12" { Safe-Remove-Cmd; Pause-Menu }
                "13" { Remove-Cmd; Pause-Menu }
                "14" { Purge-Cmd; Pause-Menu }
                "15" { Show-Paths; Pause-Menu }
                "0"  { Write-Host "Bye."; break }
                default { Write-Warn2 "Неверный пункт."; Start-Sleep -Seconds 1 }
            }
        } catch {
            Write-Err2 $_.Exception.Message
            Pause-Menu
        }
    }
}

function Show-Usage {
@"
Usage:
  .\scripts\forestmapctl.ps1                  # interactive menu
  .\scripts\forestmapctl.ps1 install
  .\scripts\forestmapctl.ps1 start
  .\scripts\forestmapctl.ps1 stop
  .\scripts\forestmapctl.ps1 restart
  .\scripts\forestmapctl.ps1 status
  .\scripts\forestmapctl.ps1 logs [svc]
  .\scripts\forestmapctl.ps1 update
  .\scripts\forestmapctl.ps1 env-init
  .\scripts\forestmapctl.ps1 deps
  .\scripts\forestmapctl.ps1 backup-db
  .\scripts\forestmapctl.ps1 restore-db [file]
  .\scripts\forestmapctl.ps1 safe-remove
  .\scripts\forestmapctl.ps1 remove
  .\scripts\forestmapctl.ps1 purge

Important:
  Script should be placed at:
    <repo>\scripts\forestmapctl.ps1
  Paths are resolved automatically from script location.

Environment variables:
  FORESTMAP_DIR          Optional override for repository root
  FORESTMAP_BACKUP_DIR   Optional backup output dir (default: <repo>\backups)
  FORESTMAP_DB_SERVICE   Optional compose DB service name (default: db)
"@ | Write-Host
}

# -----------------------------
# Entry point
# -----------------------------
switch ($Command.ToLowerInvariant()) {
    ""           { Interactive-Menu }
    "install"    { Install-Cmd }
    "start"      { Start-Cmd }
    "stop"       { Stop-Cmd }
    "restart"    { Restart-Cmd }
    "status"     { Status-Cmd }
    "logs"       { if ($Rest.Count -gt 0) { Logs-Cmd -Service $Rest[0] } else { Logs-Cmd } }
    "update"     { Update-Cmd }
    "env-init"   { Init-Env }
    "deps"       { Install-Dependencies }
    "backup-db"  { Backup-Db-Cmd }
    "restore-db" { if ($Rest.Count -gt 0) { Restore-Db-Cmd -InputFile $Rest[0] } else { Restore-Db-Cmd } }
    "safe-remove"{ Safe-Remove-Cmd }
    "remove"     { Remove-Cmd }
    "purge"      { Purge-Cmd }
    "help"       { Show-Usage }
    "-h"         { Show-Usage }
    "--help"     { Show-Usage }
    default      {
        Write-Err2 "Unknown command: $Command"
        Show-Usage
        exit 1
    }
}
