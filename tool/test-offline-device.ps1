param(
    [string]$DeviceId = 'emulator-5554',
    [string]$ApiUrl = 'http://10.0.2.2:8080',
    [string]$HostApiUrl = 'http://127.0.0.1:8080',
    [string]$ExpectedAvd = 'Hedrion_Test',
    [string]$Adb = 'adb',
    [switch]$WithConflict
)

$ErrorActionPreference = 'Stop'
if ($DeviceId -notmatch '^emulator-\d+$') {
    throw 'This script changes networking only on an explicitly named test emulator.'
}
$avdResponse = @(& $Adb -s $DeviceId emu avd name)
$avdExitCode = $LASTEXITCODE
$avdName = ($avdResponse | Select-Object -First 1).Trim()
if ($avdExitCode -ne 0 -or $avdName -ne $ExpectedAvd) {
    throw "Expected test AVD $ExpectedAvd; found $avdName."
}
$repoRoot = Split-Path -Parent $PSScriptRoot
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$testEmail = "offline-$stamp@example.test"
$testPassword = 'Device-test-' + [Guid]::NewGuid().ToString('N')
$networkDisabled = $false

function Invoke-Phase([string]$Phase) {
    # Flutter otherwise uninstalls the app after each test, deleting the durable state.
    & flutter test integration_test/offline_device_test.dart --no-pub --no-uninstall --no-enable-impeller -d $DeviceId --timeout 120s `
        "--dart-define=DEVICE_TEST_PHASE=$Phase" `
        "--dart-define=DEVICE_TEST_EMAIL=$testEmail" `
        "--dart-define=DEVICE_TEST_PASSWORD=$testPassword" `
        "--dart-define=HEDRION_API_URL=$ApiUrl" `
        "--dart-define=DEVICE_TEST_EXPECT_CONFLICT=$($WithConflict.IsPresent.ToString().ToLowerInvariant())"
    if ($LASTEXITCODE -ne 0) { throw "Device test failed in phase $Phase." }
}

Push-Location (Join-Path $repoRoot 'apps/mobile')
try {
    Invoke-Phase 'prepare'
    $networkDisabled = $true
    & $Adb -s $DeviceId shell cmd connectivity airplane-mode enable
    & $Adb -s $DeviceId shell svc wifi disable
    & $Adb -s $DeviceId shell svc data disable
    Invoke-Phase 'offline'
    if ($WithConflict) {
        # A second authenticated client edits the same record while Android is offline.
        $loginBody = @{ email=$testEmail; password=$testPassword } | ConvertTo-Json
        $session = Invoke-RestMethod -Method Post -Uri "$HostApiUrl/api/v1/auth/login" -ContentType 'application/json' -Body $loginBody
        $headers = @{ Authorization="Bearer $($session.token)" }
        $library = Invoke-RestMethod -Uri "$HostApiUrl/api/v1/assets" -Headers $headers
        if ($library.assets.Count -ne 1) { throw 'Expected the isolated test account to own one model.' }
        $asset = $library.assets[0]
        $patch = @{ title='Izmena sa drugog klijenta'; baseRevision=$asset.revision } | ConvertTo-Json
        Invoke-RestMethod -Method Patch -Uri "$HostApiUrl/api/v1/assets/$($asset.id)" -Headers $headers -ContentType 'application/json' -Body $patch | Out-Null
        Write-Output 'Concurrent edit recorded; Android must expose and explicitly resolve its revision conflict.'
    }
    & $Adb -s $DeviceId shell cmd connectivity airplane-mode disable
    & $Adb -s $DeviceId shell svc wifi enable
    & $Adb -s $DeviceId shell svc data enable
    $networkDisabled = $false
    Invoke-Phase 'sync'
} finally {
    if ($networkDisabled) {
        & $Adb -s $DeviceId shell cmd connectivity airplane-mode disable
        & $Adb -s $DeviceId shell svc wifi enable
        & $Adb -s $DeviceId shell svc data enable
    }
    Pop-Location
}
