[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gallery = Join-Path $root 'gallery'
$catalog = & (Join-Path $gallery 'Read-Data.ps1') -Path (Join-Path $gallery 'Catalog.ps1')
if ($catalog.SchemaVersion -ne 1) { throw 'Unsupported gallery schema.' }
$ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $catalog.Entries) {
    if ($entry.Id -notmatch '^[a-z][a-z0-9-]*$' -or -not $ids.Add($entry.Id)) { throw 'Invalid or duplicate gallery ID.' }
    foreach ($field in @('Title','Description','Platform','Status')) {
        if ([string]::IsNullOrWhiteSpace($entry[$field])) { throw "Missing field: $field" }
    }
    foreach ($field in @('Script','Launcher','Source','Verification','Standalone')) {
        if (-not $entry.ContainsKey($field)) {
            if ($field -eq 'Standalone') { continue }
            throw "Missing path: $field"
        }
        $path = [IO.Path]::GetFullPath((Join-Path $gallery $entry[$field]))
        if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Catalog path escapes repository.' }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing catalog target: $field" }
        if ([IO.Path]::GetExtension($path) -eq '.ps1') {
            $tokens = $null; $errors = $null
            $null = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
            if ($errors.Count) { throw $errors[0] }
        }
    }
    if ($entry.VerificationArguments.Count -ne 1 -or $entry.VerificationArguments[0] -ne '-Verify') { throw 'Unexpected verification arguments.' }
}
'PASS: gallery catalog IDs, metadata, repository-contained paths, and script syntax. No applets executed.'
