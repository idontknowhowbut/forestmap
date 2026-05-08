$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$InfraDir = Join-Path $Root 'infra'
$ExamplePath = Join-Path $InfraDir '.env.example'
$EnvPath = Join-Path $InfraDir '.env'

function New-RandomSecret([int]$Length = 32) {
    $bytes = New-Object byte[] $Length
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ([Convert]::ToBase64String($bytes)).Replace('+', 'A').Replace('/', 'B').TrimEnd('=')
}

if (-not (Test-Path $ExamplePath)) {
    throw "Cannot find $ExamplePath"
}

$content = Get-Content $ExamplePath -Raw
$content = $content -replace 'CHANGE_ME_FOREST_DB_PASSWORD', (New-RandomSecret)
$content = $content -replace 'CHANGE_ME_KEYCLOAK_DB_PASSWORD', (New-RandomSecret)
$content = $content -replace 'CHANGE_ME_KEYCLOAK_ADMIN_PASSWORD', (New-RandomSecret)

Set-Content -Path $EnvPath -Value $content -Encoding UTF8
Write-Host "Generated $EnvPath"
