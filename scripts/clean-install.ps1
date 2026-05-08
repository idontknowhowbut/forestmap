$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$InfraDir = Join-Path $Root 'infra'
$EnvPath = Join-Path $InfraDir '.env'
if (-not (Test-Path $EnvPath)) {
    & (Join-Path $PSScriptRoot 'generate-env.ps1')
}
& (Join-Path $PSScriptRoot 'check-deps.ps1')
Push-Location $InfraDir
try {
    docker compose down -v --remove-orphans
    docker compose up -d --build
    Start-Sleep -Seconds 8
    docker compose restart api
    Write-Host 'Clean install completed.'
} finally {
    Pop-Location
}
