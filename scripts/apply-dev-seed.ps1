$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$InfraDir = Join-Path $Root 'infra'
Push-Location $InfraDir
try {
    Get-Content .\dev_detections_seed.sql | docker compose exec -T db psql -v ON_ERROR_STOP=1 -U forest -d forestmap
    Write-Host 'Dev detections seed applied.'
} finally {
    Pop-Location
}
