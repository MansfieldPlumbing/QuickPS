[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference='Stop'
$resolved=(Resolve-Path -LiteralPath $Path).ProviderPath
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseFile($resolved,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
# Explicit local trusted source. Parsing verifies syntax, not authorization.
$data=& $resolved
if($data -isnot [hashtable]){throw 'Data source must return exactly one hashtable.'}
$data
