[CmdletBinding()]
param([switch]$Verify)
& (Join-Path $PSScriptRoot 'Show.ps1') -Name 'D3D12' -Verify:$Verify
