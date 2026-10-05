[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AssemblyPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [switch]$Loopback,
    [switch]$Normalize,
    [switch]$Synthetic,
    [IntPtr]$NotifyWindow=[IntPtr]::Zero,
    [IntPtr]$NotifyControl=[IntPtr]::Zero,
    [int]$NotifyId=0
)
if ($MyInvocation.InvocationName -eq '.') { throw 'Capture.Windows.ps1 must be invoked with &, not dot-sourced.' }
$ErrorActionPreference='Stop'
if(-not $IsWindows -or [IntPtr]::Size -ne 8){throw 'Capture requires Windows x64.'}
$assemblyFile=(Resolve-Path -LiteralPath $AssemblyPath).ProviderPath
$assembly=[Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath($assemblyFile)
$type=$assembly.GetType('QuickPSCapture',$true)
$worker=[Activator]::CreateInstance($type)
try {
    # audioclient.h / mmdeviceapi.h: each argument list includes the COM this
    # pointer. Dynamic types contain only unmanaged delegate signatures, no code.
    $shapes=@(
        @([IntPtr],[uint32],[uint32],[IntPtr]),
        @([IntPtr],[IntPtr],[uint32],[IntPtr],[IntPtr]),
        @([IntPtr],[IntPtr]),
        @([IntPtr],[uint32],[uint32],[int64],[int64],[IntPtr],[IntPtr]),
        @([IntPtr],[IntPtr],[IntPtr]),
        @([IntPtr]),
        @([IntPtr],[IntPtr],[IntPtr],[IntPtr],[IntPtr],[IntPtr]),
        @([IntPtr],[uint32])
    )
    $delegateAssembly=[Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        [Reflection.AssemblyName]::new('QuickPS.Capture.Signatures.'+[Guid]::NewGuid().ToString('N')),
        [Reflection.Emit.AssemblyBuilderAccess]::Run)
    $module=$delegateAssembly.DefineDynamicModule('Signatures')
    $signatures=[Collections.Generic.List[Type]]::new()
    foreach($shape in $shapes){
        $builder=$module.DefineType('Call'+$signatures.Count,'Public,Sealed,Class',[MulticastDelegate])
        $constructor=$builder.DefineConstructor('Public,HideBySig,RTSpecialName',[Reflection.CallingConventions]::Standard,@([object],[IntPtr]))
        $constructor.SetImplementationFlags('Runtime,Managed')
        $method=$builder.DefineMethod('Invoke','Public,HideBySig,NewSlot,Virtual',[int32],[Type[]]$shape)
        $method.SetImplementationFlags('Runtime,Managed')
        $attribute=[Runtime.InteropServices.UnmanagedFunctionPointerAttribute].GetConstructor(@([Runtime.InteropServices.CallingConvention]))
        $builder.SetCustomAttribute([Reflection.Emit.CustomAttributeBuilder]::new($attribute,@([Runtime.InteropServices.CallingConvention]::StdCall)))
        $signatures.Add($builder.CreateType())
    }
    $worker.Signatures=$signatures.ToArray()
    $worker.OutputPath=[IO.Path]::GetFullPath($OutputPath)
    $worker.Loopback=[bool]$Loopback
    $worker.Normalize=[bool]$Normalize
    $worker.Synthetic=[bool]$Synthetic
    $worker.NotifyWindow=$NotifyWindow
    $worker.NotifyControl=$NotifyControl
    $worker.NotifyId=$NotifyId
    $entry=$type.GetMethod('Run').CreateDelegate([Threading.ThreadStart],$worker)
    $worker.Thread=[Threading.Thread]::new([Threading.ThreadStart]$entry)
    $worker.Thread.IsBackground=$true
    return $worker
} catch { $worker.Dispose(); throw }
