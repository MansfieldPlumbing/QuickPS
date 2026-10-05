[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '..\src\MediaFoundation.Windows.ps1'
$tokens = $null; $errors = $null
$null = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw $errors[0] }
$media = & $path
try {
    $devices = @($media.ListVideoDevices())
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($device in $devices) {
        if ([string]::IsNullOrWhiteSpace($device.Name) -or [string]::IsNullOrWhiteSpace($device.DeviceId)) { throw 'Incomplete device descriptor.' }
        if (-not $ids.Add($device.DeviceId)) { throw 'Duplicate device ID.' }
    }
    if ($devices.Count -eq 0) { 'PASS: empty enumeration handled. Hardware descriptor validation NOT RUN: no video devices.' }
    else { "PASS: $($devices.Count) video descriptors validated without activation or capture." }
} finally { $media.Dispose() }
