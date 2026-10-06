[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AssemblyPath,
    [Parameter(Mandatory)][IntPtr]$Generator,
    [Parameter(Mandatory)][IntPtr]$NotifyWindow,
    [ValidateRange(0x8000, 0xBFFD)][uint32]$Message = 0x8000
)
if ($MyInvocation.InvocationName -eq '.') { throw 'MediaSessionEvents.Windows.ps1 must be invoked with &, not dot-sourced.' }
$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or [IntPtr]::Size -ne 8) { throw 'Media session events require Windows x64.' }
if ($Generator -eq [IntPtr]::Zero -or $NotifyWindow -eq [IntPtr]::Zero) { throw 'A media event generator and a notification window are required.' }

# Returns an unstarted QuickPSMediaSessionEvents worker; the caller starts
# Thread and joins it after closing or shutting down the generator. The
# generator must outlive the thread. Messages are documented in
# src/managed/MediaSessionEvents.ps1 (WM_APP range, Message to Message + 2).
$assemblyFile = (Resolve-Path -LiteralPath $AssemblyPath).ProviderPath
$assembly = [Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath($assemblyFile)
$type = $assembly.GetType('QuickPSMediaSessionEvents', $true)
$worker = [Activator]::CreateInstance($type)
# mfobjects.h: each argument list includes the COM this pointer.
# 0 GetEvent(this, DWORD, IMFMediaEvent**); 1 GetType/GetStatus(this, out);
# 2 GetUINT32(this, REFGUID, UINT32*). Dynamic types hold signatures, no code.
$shapes = @(
    @([IntPtr], [uint32], [IntPtr]),
    @([IntPtr], [IntPtr]),
    @([IntPtr], [IntPtr], [IntPtr])
)
$delegateAssembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
    [Reflection.AssemblyName]::new('QuickPS.MediaSessionEvents.Signatures.' + [Guid]::NewGuid().ToString('N')),
    [Reflection.Emit.AssemblyBuilderAccess]::Run)
$module = $delegateAssembly.DefineDynamicModule('Signatures')
$signatures = [Collections.Generic.List[Type]]::new()
foreach ($shape in $shapes) {
    $builder = $module.DefineType('Call' + $signatures.Count, 'Public,Sealed,Class', [MulticastDelegate])
    $constructor = $builder.DefineConstructor('Public,HideBySig,RTSpecialName', [Reflection.CallingConventions]::Standard, @([object], [IntPtr]))
    $constructor.SetImplementationFlags('Runtime,Managed')
    $method = $builder.DefineMethod('Invoke', 'Public,HideBySig,NewSlot,Virtual', [int32], [Type[]]$shape)
    $method.SetImplementationFlags('Runtime,Managed')
    $attribute = [Runtime.InteropServices.UnmanagedFunctionPointerAttribute].GetConstructor(@([Runtime.InteropServices.CallingConvention]))
    $builder.SetCustomAttribute([Reflection.Emit.CustomAttributeBuilder]::new($attribute, @([Runtime.InteropServices.CallingConvention]::StdCall)))
    $signatures.Add($builder.CreateType())
}
$worker.Signatures = $signatures.ToArray()
$worker.Generator = $Generator
$worker.NotifyWindow = $NotifyWindow
$worker.Message = $Message
$entry = $type.GetMethod('Run').CreateDelegate([Threading.ThreadStart], $worker)
$worker.Thread = [Threading.Thread]::new([Threading.ThreadStart]$entry)
$worker.Thread.IsBackground = $true
$worker
