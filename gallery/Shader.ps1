[CmdletBinding()]
param([switch]$Verify)
& (Join-Path $PSScriptRoot 'Show.ps1') -Name 'Shader' -Verify:$Verify
