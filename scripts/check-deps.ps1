$ErrorActionPreference = 'Stop'
$null = docker version | Out-Null
$null = docker compose version | Out-Null
Write-Host 'Docker and Docker Compose are available.'
