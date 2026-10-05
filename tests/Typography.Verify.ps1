[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '..\src\D2D.Windows.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw $errors[0] }
$globals = @($ast.FindAll({param($node)
    $node -is [Management.Automation.Language.VariableExpressionAst] -and $node.VariablePath.IsGlobal
}, $true))
if ($globals.Count) { throw 'Typography binding must not use global state.' }
if (-not $IsWindows -or [IntPtr]::Size -ne 8) { throw 'This native check requires Windows x64.' }
$bindings = [Collections.Generic.List[object]]::new()
$resources = [Collections.Generic.List[object]]::new()
try {
    # Keep both instances alive to exercise closure isolation after reinvocation.
    $bindings.Add((& $source))
    $bindings.Add((& $source))
    foreach ($binding in $bindings) {
        $factory = $binding.CreateFactory.Invoke()
        $resources.Add($factory)
        if ($factory.Pointer -eq [IntPtr]::Zero) { throw 'Missing Direct2D factory.' }
        $textFactory = $binding.CreateDWriteFactory.Invoke()
        $resources.Add($textFactory)
        $format = $textFactory.CreateTextFormat.Invoke('Segoe UI', [single]16)
        $resources.Add($format)
        if ($format.Pointer -eq [IntPtr]::Zero) { throw 'Missing text format.' }
    }
    'PASS: syntax, no global variables, two independent bindings, native factories and text formats. No windows created.'
} finally {
    for ($i=$resources.Count-1; $i-ge0; $i--) { [void]$resources[$i].Release.Invoke() }
    foreach ($binding in $bindings) {
        [Runtime.InteropServices.NativeLibrary]::Free($binding.DWriteHandle)
        [Runtime.InteropServices.NativeLibrary]::Free($binding.D2D1Handle)
    }
}
