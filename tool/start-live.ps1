param([switch]$ApiOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$envFile = Join-Path $projectRoot '.env'
if (!(Test-Path -LiteralPath $envFile)) {
    throw 'Create the local .env using .env.example and configure WORKER_URL first.'
}
foreach ($line in Get-Content -LiteralPath $envFile) {
    if ($line -match '^([^#=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2], 'Process')
    }
}
if (!$env:WORKER_URL) { throw 'WORKER_URL must point to the deployed Hedrion Modal gateway.' }
$logDirectory = Join-Path $projectRoot '.local/live'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
Push-Location $projectRoot
try {
    docker compose -p hedrion-live -f infrastructure/docker-compose.yml up -d postgres
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL failed to start.' }
    $databaseReady = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        docker compose -p hedrion-live -f infrastructure/docker-compose.yml exec -T postgres pg_isready -U hedrion -d hedrion *> $null
        if ($LASTEXITCODE -eq 0) { $databaseReady = $true; break }
        Start-Sleep -Seconds 1
    }
    if (!$databaseReady) { throw 'PostgreSQL did not become ready.' }
    Push-Location (Join-Path $projectRoot 'services/api')
    try {
        dart run bin/migrate.dart
        if ($LASTEXITCODE -ne 0) { throw 'Database migration failed.' }
    } finally { Pop-Location }
    function Start-HedrionProcess($name, $directory, $command) {
        $process = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d', '/c', $command) `
            -WorkingDirectory $directory -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput (Join-Path $logDirectory "$name.out.log") `
            -RedirectStandardError (Join-Path $logDirectory "$name.err.log")
        return @{ name = $name; pid = $process.Id }
    }
    $running = @()
    $apiOrigin = "http://127.0.0.1:$($env:API_PORT)"
    try { $health = Invoke-RestMethod "$apiOrigin/health" -TimeoutSec 2 } catch { $health = $null }
    if ($health.service -eq 'hedrion-api') {
        Write-Output "API already running: $apiOrigin"
    } else {
        $running += Start-HedrionProcess 'api' (Join-Path $projectRoot 'services/api') 'dart run bin/server.dart'
        $apiReady = $false
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            try {
                $health = Invoke-RestMethod "$apiOrigin/health" -TimeoutSec 2
                if ($health.service -eq 'hedrion-api') { $apiReady = $true; break }
            } catch { }
            Start-Sleep -Milliseconds 500
        }
        if (!$apiReady) { throw "API did not become ready; inspect $logDirectory/api.err.log" }
        Write-Output "API ready: $apiOrigin"
    }
    if (!$ApiOnly) {
        $studioPort = if ($env:STUDIO_PORT) { $env:STUDIO_PORT } else { '19082' }
        $backofficePort = if ($env:BACKOFFICE_PORT) { $env:BACKOFFICE_PORT } else { '19083' }
        $running += Start-HedrionProcess 'studio' (Join-Path $projectRoot 'apps/mobile') "flutter run -d web-server --web-hostname 127.0.0.1 --web-port $studioPort --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=$apiOrigin"
        $running += Start-HedrionProcess 'backoffice' (Join-Path $projectRoot 'apps/backoffice') "flutter run -d web-server --web-hostname 127.0.0.1 --web-port $backofficePort --dart-define=HEDRION_MODE=api --dart-define=HEDRION_API_URL=$apiOrigin"
        Write-Output "Studio: http://127.0.0.1:$studioPort | Backoffice: http://127.0.0.1:$backofficePort"
    }
    $running | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logDirectory 'processes.json')
    Write-Output "Process logs: $logDirectory"
} finally { Pop-Location }
