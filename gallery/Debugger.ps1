[CmdletBinding()]
param(
    [switch] $All,
    [string[]] $Name,
    [string] $BinderPath = (Join-Path $PSScriptRoot '..\src')
)

if ($MyInvocation.InvocationName -eq '.') {
    throw 'Debugger.ps1 must be invoked with &, not dot-sourced.'
}

$excluded = [Collections.Generic.HashSet[string]]::new(
    [string[]]@('Debugger.ps1', 'QuickPS.ps1', 'Verify.ps1'),
    [StringComparer]::OrdinalIgnoreCase)

$available = @(Get-ChildItem -LiteralPath $BinderPath -File -Filter '*.ps1' |
    Where-Object { -not $excluded.Contains($_.Name) } |
    Sort-Object BaseName)

$expected = @(
    'Activity.Android', 'Audio.Android', 'Camera.Android', 'Camera.Windows',
    'Canvas.Android', 'Canvas.Windows', 'Composition.Windows', 'D3D11On12.Windows',
    'D3D12.Windows', 'Direct2D.Windows', 'DirectWrite.Windows', 'DXGI.Windows',
    'Images.Android', 'Input.Android', 'Input.Windows', 'Media.Android',
    'MediaFoundation.Windows', 'Pixels.Android', 'Pixels.Windows',
    'Shader.Android', 'Shader.Windows', 'Sharing.Android', 'Sharing.Windows',
    'Text.Android', 'Wasapi.Windows', 'Wic.Windows', 'Window.Android',
    'Window.Windows'
)

$requested = if ($All) {
    $expected
}
elseif (-not $Name) {
    @($available.BaseName)
}
else {
    @($Name)
}

$results = [Collections.Generic.List[object]]::new()
$instances = [Collections.Generic.List[object]]::new()

foreach ($requestedName in $requested) {
    $file = @($available | Where-Object BaseName -EQ $requestedName)
    if ($file.Count -ne 1) {
        $results.Add([PSCustomObject]@{
            Name = $requestedName
            State = 'Missing'
            Instance = $null
            Error = "No unique binder named '$requestedName' exists in '$BinderPath'."
        })
        continue
    }

    try {
        $output = @(& $file[0].FullName)
        $instance = if ($output.Count -eq 1) { $output[0] } else { $output }
        $instances.Add($instance)
        $results.Add([PSCustomObject]@{
            Name = $requestedName
            State = 'Live'
            Instance = $instance
            Error = $null
        })
    }
    catch {
        $results.Add([PSCustomObject]@{
            Name = $requestedName
            State = 'Failed'
            Instance = $null
            Error = $_.Exception.Message
        })
    }
}

$harness = [PSCustomObject]@{
    PSTypeName = 'QuickPS.Debugger'
    BinderPath = [IO.Path]::GetFullPath($BinderPath)
    Results = $results.ToArray()
    Instances = $instances.ToArray()
    Expected = $expected
}

$harness | Add-Member ScriptMethod Dispose ({
    foreach ($instance in $this.Instances) {
        if ($null -eq $instance) { continue }
        $dispose = $instance.PSObject.Methods['Dispose']
        if ($null -ne $dispose) {
            try { $instance.Dispose() } catch { }
        }
    }
}.GetNewClosure())

$harness
