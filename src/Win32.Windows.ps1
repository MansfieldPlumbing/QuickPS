[CmdletBinding()]
param([hashtable]$Theme=@{})
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or [IntPtr]::Size -ne 8) { throw 'This backend requires 64-bit Windows.' }

# Native ABI block. Layouts and signatures: Windows SDK 10.0.26100.0, WinUser.h.
if ($MyInvocation.InvocationName -eq '.') { throw 'Win32.Windows.ps1 must be invoked with &.' }
$native = & {
$Native = & {
    $assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        [Reflection.AssemblyName]::new('QuickPS.Native.' + [Guid]::NewGuid().ToString('N')),
        [Reflection.Emit.AssemblyBuilderAccess]::Run)
    $module = $assembly.DefineDynamicModule('Native')
    $types = [Collections.Generic.Dictionary[string, Type]]::new()
    $calls = [Collections.Generic.Dictionary[string, Delegate]]::new()
    $libraries = [Collections.Generic.Dictionary[string, IntPtr]]::new(
        [StringComparer]::OrdinalIgnoreCase)

    $instance = [PSCustomObject]@{
        PSTypeName = 'QuickPS.Native'
        Module = $module
        DelegateTypes = $types
        Calls = $calls
        Libraries = $libraries
    }

    $instance | Add-Member ScriptMethod LoadLibrary ({
        param([string] $Name)
        if (-not $this.Libraries.ContainsKey($Name)) {
            $this.Libraries[$Name] = [Runtime.InteropServices.NativeLibrary]::Load($Name)
        }
        $this.Libraries[$Name]
    }.GetNewClosure())

    $instance | Add-Member ScriptMethod GetExport ({
        param([IntPtr] $Library, [string] $Name)
        [Runtime.InteropServices.NativeLibrary]::GetExport($Library, $Name)
    }.GetNewClosure())

    $instance | Add-Member ScriptMethod GetCall ({
        param([IntPtr] $Address, [Type] $ReturnType, [Type[]] $ParameterTypes)
        if ($Address -eq [IntPtr]::Zero) { throw 'Cannot bind a null native address.' }
        $signature = $ReturnType.FullName + ':' + (($ParameterTypes | ForEach-Object FullName) -join ',')
        if (-not $this.DelegateTypes.ContainsKey($signature)) {
            $builder = $this.Module.DefineType(
                'Call_' + [Guid]::NewGuid().ToString('N'),
                'Class,Public,Sealed',
                [MulticastDelegate])
            $constructor = $builder.DefineConstructor(
                'Public,HideBySig,RTSpecialName',
                [Reflection.CallingConventions]::Standard,
                @([object], [IntPtr]))
            $constructor.SetImplementationFlags('Runtime,Managed')
            $invoke = $builder.DefineMethod(
                'Invoke', 'Public,HideBySig,NewSlot,Virtual',
                $ReturnType, $ParameterTypes)
            $invoke.SetImplementationFlags('Runtime,Managed')
            $attribute = [Reflection.Emit.CustomAttributeBuilder]::new(
                [Runtime.InteropServices.UnmanagedFunctionPointerAttribute].GetConstructor(
                    @([Runtime.InteropServices.CallingConvention])),
                @([Runtime.InteropServices.CallingConvention]::StdCall))
            $builder.SetCustomAttribute($attribute)
            $this.DelegateTypes[$signature] = $builder.CreateType()
        }
        $key = $Address.ToInt64().ToString() + ':' + $signature
        if (-not $this.Calls.ContainsKey($key)) {
            $this.Calls[$key] = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer(
                $Address, $this.DelegateTypes[$signature])
        }
        $this.Calls[$key]
    }.GetNewClosure())

    $instance | Add-Member ScriptMethod GetExportCall ({
        param([string] $Library, [string] $Name, [Type] $ReturnType, [Type[]] $ParameterTypes)
        $handle = $this.LoadLibrary($Library)
        $address = $this.GetExport($handle, $Name)
        $this.GetCall($address, $ReturnType, $ParameterTypes)
    }.GetNewClosure())

    $instance | Add-Member ScriptMethod GetComCall ({
        param([IntPtr] $Object, [int] $Slot, [Type] $ReturnType, [Type[]] $ParameterTypes)
        if ($Object -eq [IntPtr]::Zero) { throw 'Cannot bind a null COM interface.' }
        $vtable = [Runtime.InteropServices.Marshal]::ReadIntPtr($Object)
        $address = [Runtime.InteropServices.Marshal]::ReadIntPtr(
            $vtable, $Slot * [IntPtr]::Size)
        $this.GetCall($address, $ReturnType, (@([IntPtr]) + $ParameterTypes))
    }.GetNewClosure())

    $instance | Add-Member ScriptMethod InvokeCom ({
        param(
            [IntPtr] $Object,
            [int] $Slot,
            [Type] $ReturnType,
            [Type[]] $ParameterTypes,
            [object[]] $Arguments
        )
        $call = $this.GetComCall($Object, $Slot, $ReturnType, $ParameterTypes)
        $invokeArguments = [object[]]::new(1 + $Arguments.Count)
        $invokeArguments[0] = [IntPtr]$Object
        for ($index = 0; $index -lt $Arguments.Count; $index++) {
            $argument = $Arguments[$index]
            if ($argument -is [Management.Automation.PSObject]) {
                $argument = $argument.BaseObject
            }
            $invokeArguments[$index + 1] = $argument
        }
        $call.DynamicInvoke($invokeArguments)
    }.GetNewClosure())

    $instance | Add-Member ScriptMethod Allocate ({
        param([int] $Bytes)
        if ($Bytes -lt 1) { throw 'Allocation size must be positive.' }
        $pointer = [Runtime.InteropServices.Marshal]::AllocHGlobal($Bytes)
        for ($index = 0; $index -lt $Bytes; $index++) {
            [Runtime.InteropServices.Marshal]::WriteByte($pointer, $index, 0)
        }
        $pointer
    }.GetNewClosure())

    $instance | Add-Member ScriptMethod Free ({
        param([IntPtr] $Pointer)
        if ($Pointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($Pointer)
        }
    }.GetNewClosure())

    $instance | Add-Member ScriptMethod ReleaseCom ({
        param([IntPtr] $Object)
        if ($Object -eq [IntPtr]::Zero) { return [uint32]0 }
        [uint32]$this.InvokeCom($Object, 2, ([uint32]), @(), @())
    }.GetNewClosure())

    $instance | Add-Member ScriptMethod Dispose ({
        foreach ($library in $this.Libraries.Values) {
            if ($library -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.NativeLibrary]::Free($library)
            }
        }
        $this.Libraries.Clear()
        $this.Calls.Clear()
        $this.DelegateTypes.Clear()
    }.GetNewClosure())

    $instance
}

$Native


}
$api = @{}
$spec = @(
    @('kernel32.dll','GetModuleHandleW',[IntPtr],@([IntPtr])),
    @('kernel32.dll','GetCurrentThreadId',[uint32],@()),
    @('user32.dll','DefWindowProcW',[IntPtr],@([IntPtr],[uint32],[IntPtr],[IntPtr])),
    @('user32.dll','PostThreadMessageW',[int],@([uint32],[uint32],[IntPtr],[IntPtr])),
    @('user32.dll','RegisterClassExW',[uint16],@([IntPtr])),
    @('user32.dll','UnregisterClassW',[int],@([IntPtr],[IntPtr])),
    @('user32.dll','CreateWindowExW',[IntPtr],@([uint32],[IntPtr],[IntPtr],[uint32],[int],[int],[int],[int],[IntPtr],[IntPtr],[IntPtr],[IntPtr])),
    @('user32.dll','DestroyWindow',[int],@([IntPtr])),
    @('user32.dll','IsWindow',[int],@([IntPtr])),
    @('user32.dll','IsIconic',[int],@([IntPtr])),
    @('user32.dll','IsZoomed',[int],@([IntPtr])),
    @('user32.dll','ShowWindow',[int],@([IntPtr],[int])),
    @('user32.dll','SetForegroundWindow',[int],@([IntPtr])),
    @('user32.dll','GetMessageW',[int],@([IntPtr],[IntPtr],[uint32],[uint32])),
    @('user32.dll','TranslateMessage',[int],@([IntPtr])),
    @('user32.dll','DispatchMessageW',[IntPtr],@([IntPtr])),
    @('user32.dll','SendMessageW',[IntPtr],@([IntPtr],[uint32],[IntPtr],[IntPtr])),
    @('user32.dll','SetWindowTextW',[int],@([IntPtr],[IntPtr])),
    @('user32.dll','LoadCursorW',[IntPtr],@([IntPtr],[IntPtr])),
    @('user32.dll','LoadIconW',[IntPtr],@([IntPtr],[IntPtr])),
    @('user32.dll','GetClientRect',[int],@([IntPtr],[IntPtr])),
    @('user32.dll','SetWindowPos',[int],@([IntPtr],[IntPtr],[int],[int],[int],[int],[uint32])),
    @('gdi32.dll','GetStockObject',[IntPtr],@([int])),
    @('gdi32.dll','CreateSolidBrush',[IntPtr],@([uint32])),
    @('gdi32.dll','DeleteObject',[int],@([IntPtr])),
    @('gdi32.dll','SetTextColor',[uint32],@([IntPtr],[uint32])),
    @('gdi32.dll','SetBkColor',[uint32],@([IntPtr],[uint32])),
    @('gdi32.dll','CreateFontW',[IntPtr],@([int],[int],[int],[int],[int],[uint32],[uint32],[uint32],[uint32],[uint32],[uint32],[uint32],[uint32],[IntPtr])),
    @('dwmapi.dll','DwmSetWindowAttribute',[int],@([IntPtr],[uint32],[IntPtr],[uint32]))
    @('dwmapi.dll','DwmGetWindowAttribute',[int],@([IntPtr],[uint32],[IntPtr],[uint32])),
    @('dwmapi.dll','DwmExtendFrameIntoClientArea',[int],@([IntPtr],[IntPtr]))
)
foreach ($entry in $spec) { $api[$entry[1]] = $native.GetExportCall($entry[0],$entry[1],$entry[2],[Type[]]$entry[3]) }
$moduleHandle = $api.GetModuleHandleW.Invoke([IntPtr]::Zero)
$threadId = $api.GetCurrentThreadId.Invoke()

$background=[uint32]0x001C1C1C; $foreground=[uint32]0x00FFFFFF
if($Theme.ContainsKey('Palette')){
    foreach($pair in @(@('Bg','background'),@('Text','foreground'))){
        if($Theme.Palette.ContainsKey($pair[0])){
            $rgb=[uint32]$Theme.Palette[$pair[0]]
            $color=[uint32]((($rgb-band255)-shl16)-bor($rgb-band65280)-bor(($rgb-shr16)-band255))
            if($pair[1]-eq'background'){$background=$color}else{$foreground=$color}
        }
    }
}
$backgroundBrush=$api.CreateSolidBrush.Invoke($background)
if($backgroundBrush-eq[IntPtr]::Zero){$native.Dispose();throw 'Theme brush creation failed.'}
$buttonBrush=$api.CreateSolidBrush.Invoke([uint32]0x00303030)
$buttonBorder=$api.CreateSolidBrush.Invoke([uint32]0x00808080)
if($buttonBrush-eq[IntPtr]::Zero -or $buttonBorder-eq[IntPtr]::Zero){
    foreach($brush in @($backgroundBrush,$buttonBrush,$buttonBorder)){if($brush-ne[IntPtr]::Zero){[void]$api.DeleteObject.Invoke($brush)}}
    $native.Dispose();throw 'Button theme brush creation failed.'
}
$fontName=[Runtime.InteropServices.Marshal]::StringToHGlobalUni('Segoe UI')
try{$font=$api.CreateFontW.Invoke(-16,0,0,0,400,[uint32]0,[uint32]0,[uint32]0,[uint32]1,[uint32]0,[uint32]0,[uint32]5,[uint32]0,$fontName)}
finally{[Runtime.InteropServices.Marshal]::FreeHGlobal($fontName)}
if($font-eq[IntPtr]::Zero){foreach($brush in @($backgroundBrush,$buttonBrush,$buttonBorder)){[void]$api.DeleteObject.Invoke($brush)};$native.Dispose();throw 'UI font creation failed.'}

# Native window procedure: enqueue discrete commands, then call DefWindowProcW.
# No PowerShell callback is entered by paint, resize, or compositor animation.
$procSignature = [Type[]]@([IntPtr],[uint32],[IntPtr],[IntPtr])
$method = [Reflection.Emit.DynamicMethod]::new('DesktopWindowProcedure',[IntPtr],$procSignature)
$il = $method.GetILGenerator()
# DRAWITEMSTRUCT x64: hwndItem=24, hDC=32, rcItem=40 (WinUser.h).
$dcLocal=$il.DeclareLocal([IntPtr]);$rectLocal=$il.DeclareLocal([IntPtr])
$textLocal=$il.DeclareLocal([IntPtr]);$oldFont=$il.DeclareLocal([IntPtr])
$afterDraw=$il.DefineLabel();$noFocus=$il.DefineLabel()
$il.Emit([Reflection.Emit.OpCodes]::Ldarg_1)
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,0x002B)
$il.Emit([Reflection.Emit.OpCodes]::Bne_Un,$afterDraw)
foreach($field in @(@(32,$dcLocal),@(40,$rectLocal))){
    $il.Emit([Reflection.Emit.OpCodes]::Ldarg_3)
    $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,[int]$field[0]);$il.Emit([Reflection.Emit.OpCodes]::Conv_I)
    $il.Emit([Reflection.Emit.OpCodes]::Add)
    if($field[0]-eq32){$il.Emit([Reflection.Emit.OpCodes]::Ldind_I)}
    $il.Emit([Reflection.Emit.OpCodes]::Stloc,$field[1])
}
function Emit-DesktopCall([string]$library,[string]$name,[Type]$result,[Type[]]$parameters){
    $address=$native.GetExport($native.LoadLibrary($library),$name)
    $il.Emit([Reflection.Emit.OpCodes]::Ldc_I8,$address.ToInt64());$il.Emit([Reflection.Emit.OpCodes]::Conv_I)
    $il.EmitCalli([Reflection.Emit.OpCodes]::Calli,[Runtime.InteropServices.CallingConvention]::StdCall,$result,$parameters)
}
foreach($paint in @(@('FillRect',$buttonBrush),@('FrameRect',$buttonBorder))){
    $il.Emit([Reflection.Emit.OpCodes]::Ldloc,$dcLocal);$il.Emit([Reflection.Emit.OpCodes]::Ldloc,$rectLocal)
    $il.Emit([Reflection.Emit.OpCodes]::Ldc_I8,$paint[1].ToInt64());$il.Emit([Reflection.Emit.OpCodes]::Conv_I)
    Emit-DesktopCall user32.dll $paint[0] ([int]) @([IntPtr],[IntPtr],[IntPtr])
    $il.Emit([Reflection.Emit.OpCodes]::Pop)
}
$il.Emit([Reflection.Emit.OpCodes]::Ldloc,$dcLocal)
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,[int]$foreground)
Emit-DesktopCall gdi32.dll SetTextColor ([uint32]) @([IntPtr],[uint32])
$il.Emit([Reflection.Emit.OpCodes]::Pop)
$il.Emit([Reflection.Emit.OpCodes]::Ldloc,$dcLocal);$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_1)
Emit-DesktopCall gdi32.dll SetBkMode ([int]) @([IntPtr],[int])
$il.Emit([Reflection.Emit.OpCodes]::Pop)
$il.Emit([Reflection.Emit.OpCodes]::Ldloc,$dcLocal)
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I8,$font.ToInt64());$il.Emit([Reflection.Emit.OpCodes]::Conv_I)
Emit-DesktopCall gdi32.dll SelectObject ([IntPtr]) @([IntPtr],[IntPtr])
$il.Emit([Reflection.Emit.OpCodes]::Stloc,$oldFont)
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,512);$il.Emit([Reflection.Emit.OpCodes]::Localloc)
$il.Emit([Reflection.Emit.OpCodes]::Stloc,$textLocal)
$il.Emit([Reflection.Emit.OpCodes]::Ldloc,$textLocal);$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_0);$il.Emit([Reflection.Emit.OpCodes]::Stind_I2)
$il.Emit([Reflection.Emit.OpCodes]::Ldarg_3);$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,24);$il.Emit([Reflection.Emit.OpCodes]::Conv_I);$il.Emit([Reflection.Emit.OpCodes]::Add);$il.Emit([Reflection.Emit.OpCodes]::Ldind_I)
$il.Emit([Reflection.Emit.OpCodes]::Ldloc,$textLocal);$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,256)
Emit-DesktopCall user32.dll GetWindowTextW ([int]) @([IntPtr],[IntPtr],[int])
$il.Emit([Reflection.Emit.OpCodes]::Pop)
$il.Emit([Reflection.Emit.OpCodes]::Ldloc,$dcLocal);$il.Emit([Reflection.Emit.OpCodes]::Ldloc,$textLocal)
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_M1);$il.Emit([Reflection.Emit.OpCodes]::Ldloc,$rectLocal);$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,0x8025)
Emit-DesktopCall user32.dll DrawTextW ([int]) @([IntPtr],[IntPtr],[int],[IntPtr],[uint32])
$il.Emit([Reflection.Emit.OpCodes]::Pop)
$il.Emit([Reflection.Emit.OpCodes]::Ldarg_3);$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,16);$il.Emit([Reflection.Emit.OpCodes]::Conv_I);$il.Emit([Reflection.Emit.OpCodes]::Add);$il.Emit([Reflection.Emit.OpCodes]::Ldind_I4)
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,16);$il.Emit([Reflection.Emit.OpCodes]::And);$il.Emit([Reflection.Emit.OpCodes]::Brfalse,$noFocus)
$il.Emit([Reflection.Emit.OpCodes]::Ldloc,$dcLocal);$il.Emit([Reflection.Emit.OpCodes]::Ldloc,$rectLocal)
Emit-DesktopCall user32.dll DrawFocusRect ([int]) @([IntPtr],[IntPtr])
$il.Emit([Reflection.Emit.OpCodes]::Pop)
$il.MarkLabel($noFocus)
$il.Emit([Reflection.Emit.OpCodes]::Ldloc,$dcLocal);$il.Emit([Reflection.Emit.OpCodes]::Ldloc,$oldFont)
Emit-DesktopCall gdi32.dll SelectObject ([IntPtr]) @([IntPtr],[IntPtr])
$il.Emit([Reflection.Emit.OpCodes]::Pop)
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4_1);$il.Emit([Reflection.Emit.OpCodes]::Conv_I);$il.Emit([Reflection.Emit.OpCodes]::Ret)
$il.MarkLabel($afterDraw)
$normal = $il.DefineLabel(); $closing = $il.DefineLabel()
$colors=$il.DefineLabel();$commands=$il.DefineLabel()
# WM_CTLCOLOREDIT, WM_CTLCOLORLISTBOX, WM_CTLCOLORSTATIC: GDI colors and brush.
foreach($message in @(0x133,0x134,0x138)){
    $il.Emit([Reflection.Emit.OpCodes]::Ldarg_1)
    $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,$message)
    $il.Emit([Reflection.Emit.OpCodes]::Beq,$colors)
}
$il.Emit([Reflection.Emit.OpCodes]::Br,$commands)
$il.MarkLabel($colors)
foreach($entry in @(@('SetTextColor',$foreground),@('SetBkColor',$background))){
    $il.Emit([Reflection.Emit.OpCodes]::Ldarg_2)
    $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,[int]$entry[1])
    $address=$native.GetExport($native.LoadLibrary('gdi32.dll'),$entry[0])
    $il.Emit([Reflection.Emit.OpCodes]::Ldc_I8,$address.ToInt64())
    $il.Emit([Reflection.Emit.OpCodes]::Conv_I)
    $il.EmitCalli([Reflection.Emit.OpCodes]::Calli,[Runtime.InteropServices.CallingConvention]::StdCall,[uint32],[Type[]]@([IntPtr],[uint32]))
    $il.Emit([Reflection.Emit.OpCodes]::Pop)
}
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I8,$backgroundBrush.ToInt64())
$il.Emit([Reflection.Emit.OpCodes]::Conv_I)
$il.Emit([Reflection.Emit.OpCodes]::Ret)
$il.MarkLabel($commands)
$il.Emit([Reflection.Emit.OpCodes]::Ldarg_1)
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,0x0111)
$il.Emit([Reflection.Emit.OpCodes]::Bne_Un,$closing)
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,[int]$threadId)
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,0x8001)
$il.Emit([Reflection.Emit.OpCodes]::Ldarg_2)
$il.Emit([Reflection.Emit.OpCodes]::Ldarg_3)
$postAddress = $native.GetExport($native.LoadLibrary('user32.dll'),'PostThreadMessageW')
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I8,$postAddress.ToInt64())
$il.Emit([Reflection.Emit.OpCodes]::Conv_I)
$il.EmitCalli([Reflection.Emit.OpCodes]::Calli,[Runtime.InteropServices.CallingConvention]::StdCall,[int],[Type[]]@([uint32],[uint32],[IntPtr],[IntPtr]))
$il.Emit([Reflection.Emit.OpCodes]::Pop)
$il.Emit([Reflection.Emit.OpCodes]::Br,$normal)
$il.MarkLabel($closing)
$il.Emit([Reflection.Emit.OpCodes]::Ldarg_1)
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,0x0010)
$il.Emit([Reflection.Emit.OpCodes]::Bne_Un,$normal)
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,[int]$threadId)
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I4,0x8002)
$il.Emit([Reflection.Emit.OpCodes]::Ldarg_0)
$il.Emit([Reflection.Emit.OpCodes]::Ldarg_3)
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I8,$postAddress.ToInt64())
$il.Emit([Reflection.Emit.OpCodes]::Conv_I)
$il.EmitCalli([Reflection.Emit.OpCodes]::Calli,[Runtime.InteropServices.CallingConvention]::StdCall,[int],[Type[]]@([uint32],[uint32],[IntPtr],[IntPtr]))
$il.Emit([Reflection.Emit.OpCodes]::Pop)
$il.MarkLabel($normal)
foreach ($op in @([Reflection.Emit.OpCodes]::Ldarg_0,[Reflection.Emit.OpCodes]::Ldarg_1,[Reflection.Emit.OpCodes]::Ldarg_2,[Reflection.Emit.OpCodes]::Ldarg_3)) { $il.Emit($op) }
$defAddress = $native.GetExport($native.LoadLibrary('user32.dll'),'DefWindowProcW')
$il.Emit([Reflection.Emit.OpCodes]::Ldc_I8,$defAddress.ToInt64())
$il.Emit([Reflection.Emit.OpCodes]::Conv_I)
$il.EmitCalli([Reflection.Emit.OpCodes]::Calli,[Runtime.InteropServices.CallingConvention]::StdCall,[IntPtr],$procSignature)
$il.Emit([Reflection.Emit.OpCodes]::Ret)
$windowProcedure = $method.CreateDelegate($api.DefWindowProcW.GetType())
$className = [Runtime.InteropServices.Marshal]::StringToHGlobalUni('PwshDesktop_'+[guid]::NewGuid().ToString('N'))
$class = $native.Allocate(80)
try {
    [Runtime.InteropServices.Marshal]::WriteInt32($class,80)
    [Runtime.InteropServices.Marshal]::WriteIntPtr($class,8,[Runtime.InteropServices.Marshal]::GetFunctionPointerForDelegate($windowProcedure))
    [Runtime.InteropServices.Marshal]::WriteIntPtr($class,24,$moduleHandle)
    [Runtime.InteropServices.Marshal]::WriteIntPtr($class,40,$api.LoadCursorW.Invoke([IntPtr]::Zero,[IntPtr]32512))
    $classBrush=if([Environment]::OSVersion.Version.Build-ge22621){$api.GetStockObject.Invoke(4)}else{$backgroundBrush}
    [Runtime.InteropServices.Marshal]::WriteIntPtr($class,48,$classBrush)
    [Runtime.InteropServices.Marshal]::WriteIntPtr($class,64,$className)
    if (-not $api.RegisterClassExW.Invoke($class)) { throw 'Window class registration failed.' }
} catch {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($className)
    [void]$api.DeleteObject.Invoke($font)
    [void]$api.DeleteObject.Invoke($backgroundBrush)
    [void]$api.DeleteObject.Invoke($buttonBrush)
    [void]$api.DeleteObject.Invoke($buttonBorder)
    $native.Dispose()
    throw
} finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($class) }

# Facade block: native pointers stay in this backend.
$facade = [pscustomobject]@{
    Native=$native; Api=$api; Module=$moduleHandle; ClassName=$className
    WindowProcedure=$windowProcedure; Windows=[Collections.Generic.List[IntPtr]]::new()
    Actions=@{}; NextId=100; Root=[IntPtr]::Zero; Disposed=$false; Theme=$Theme
    BackgroundBrush=$backgroundBrush; Font=$font
    ButtonBrush=$buttonBrush; ButtonBorder=$buttonBorder
}
$facade | Add-Member ScriptMethod CreateWindow {
    param([string]$title,[int]$width,[int]$height,[string]$backdrop='Mica')
    $text=[Runtime.InteropServices.Marshal]::StringToHGlobalUni($title)
    try {
        $hwnd=$this.Api.CreateWindowExW.Invoke([uint32]0,$this.ClassName,$text,[uint32]0x00CF0000,100,100,$width,$height,[IntPtr]::Zero,[IntPtr]::Zero,$this.Module,[IntPtr]::Zero)
        if ($hwnd -eq [IntPtr]::Zero) { throw 'Window creation failed.' }
        $this.Windows.Add($hwnd)
        $this.ApplyTheme($hwnd)
        $this.SetBackdrop($hwnd,$backdrop)
        return $hwnd
    } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($text) }
}
$facade | Add-Member ScriptMethod ApplyTheme {
    param([IntPtr]$handle)
    if(-not$this.Theme.ContainsKey('Palette')){return}
    $palette=$this.Theme.Palette
    $attributes=@{Text=36}
    $buffer=$this.Native.Allocate(4)
    try{
        # DWMWA_COLOR_NONE removes the thin outline; it does not remove resize hit-testing.
        [Runtime.InteropServices.Marshal]::WriteInt32($buffer,-2)
        $hr=$this.Api.DwmSetWindowAttribute.Invoke($handle,[uint32]34,$buffer,[uint32]4)
        if($hr-lt0 -and $hr-ne-2147024809){throw "DWM border attribute failed: $hr"}
        [Runtime.InteropServices.Marshal]::WriteInt32($buffer,1)
        $hr=$this.Api.DwmSetWindowAttribute.Invoke($handle,[uint32]20,$buffer,[uint32]4)
        if($hr-lt0 -and $hr-ne-2147024809){throw "DWM dark-mode attribute failed: $hr"}
        foreach($key in $attributes.Keys){
            if(-not$palette.ContainsKey($key)){continue}
            $rgb=[uint32]$palette[$key]
            $color=[int]((($rgb-band255)-shl16)-bor($rgb-band65280)-bor(($rgb-shr16)-band255))
            [Runtime.InteropServices.Marshal]::WriteInt32($buffer,$color)
            $hr=$this.Api.DwmSetWindowAttribute.Invoke($handle,[uint32]$attributes[$key],$buffer,[uint32]4)
            if($hr-lt0 -and $hr-ne-2147024809){throw "DWM theme attribute failed: $hr"}
        }
    }finally{$this.Native.Free($buffer)}
}
$facade | Add-Member ScriptMethod SetBackdrop {
    param([IntPtr]$handle,[string]$material)
    $materials=@{None=1;Mica=2;Acrylic=3;MicaAlt=4}
    if(-not$materials.ContainsKey($material)){throw "Unknown backdrop: $material"}
    if([Environment]::OSVersion.Version.Build-lt22621){return}
    $value=$this.Native.Allocate(4);$margins=$this.Native.Allocate(16)
    try{
        [Runtime.InteropServices.Marshal]::WriteInt32($value,$materials[$material])
        $hr=$this.Api.DwmSetWindowAttribute.Invoke($handle,[uint32]38,$value,[uint32]4)
        if($hr-lt0){throw "DWM backdrop failed: $hr"}
        for($offset=0;$offset-lt16;$offset+=4){[Runtime.InteropServices.Marshal]::WriteInt32($margins,$offset,$(if($material-eq'None'){0}else{-1}))}
        $hr=$this.Api.DwmExtendFrameIntoClientArea.Invoke($handle,$margins)
        if($hr-lt0){throw "DWM frame extension failed: $hr"}
    }finally{$this.Native.Free($margins);$this.Native.Free($value)}
}
$facade | Add-Member ScriptMethod SetIcon {
    param([IntPtr]$handle,[ValidateSet('Application','Information','Warning','Error')][string]$name)
    $ids=@{Application=32512;Information=32516;Warning=32515;Error=32513}
    if(-not $this.Windows.Contains($handle)){throw 'Window is not owned by this facade.'}
    # Predefined LoadIcon resources are shared system handles; never destroy them.
    $icon=$this.Api.LoadIconW.Invoke([IntPtr]::Zero,[IntPtr]$ids[$name])
    if($icon-eq[IntPtr]::Zero){throw 'Unable to load system icon.'}
    foreach($size in @(0,1)){
        [void]$this.Api.SendMessageW.Invoke($handle,[uint32]0x80,[IntPtr]$size,$icon)
        if($this.Api.SendMessageW.Invoke($handle,[uint32]0x7F,[IntPtr]$size,[IntPtr]::Zero)-ne$icon){throw 'Window icon verification failed.'}
    }
}
$facade | Add-Member ScriptMethod AddControl {
    param([IntPtr]$parent,[string]$kind,[string]$caption,[int]$x,[int]$y,[int]$width,[int]$height,[uint32]$style,[scriptblock]$action)
    $id=$this.NextId++; if ($id -gt 65535) { throw 'Control identifier limit reached.' }
    if($kind-eq'BUTTON'){$style=[uint32](($style-band0xFFFFFFF0L)-bor0x0001000B)}
    $classText=[Runtime.InteropServices.Marshal]::StringToHGlobalUni($kind)
    $text=[Runtime.InteropServices.Marshal]::StringToHGlobalUni($caption)
    try {
        $hwnd=$this.Api.CreateWindowExW.Invoke([uint32]0,$classText,$text,[uint32](0x50000000 -bor $style),$x,$y,$width,$height,$parent,[IntPtr]$id,$this.Module,[IntPtr]::Zero)
        if ($hwnd -eq [IntPtr]::Zero) { throw "Control creation failed: $kind" }
        [void]$this.Api.SendMessageW.Invoke($hwnd,[uint32]0x30,$this.Font,[IntPtr]1)
        if ($action) { $this.Actions[$id]=@{Handle=$hwnd;Invoke=$action} }
        return $hwnd
    } finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($text)
        [Runtime.InteropServices.Marshal]::FreeHGlobal($classText)
    }
}
$facade | Add-Member ScriptMethod SetText {
    param([IntPtr]$handle,[string]$value)
    $text=[Runtime.InteropServices.Marshal]::StringToHGlobalUni($value)
    try { if (-not $this.Api.SetWindowTextW.Invoke($handle,$text)) { throw 'SetWindowText failed.' } }
    finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($text) }
}
$facade | Add-Member ScriptMethod Show {
    param([IntPtr]$handle,[int]$command=5)
    [void]$this.Api.ShowWindow.Invoke($handle,$command)
    # The first ShowWindow may honor the launcher's STARTUPINFO instead of command.
    [void]$this.Api.ShowWindow.Invoke($handle,$command)
}
$facade | Add-Member ScriptMethod SetItems {
    param([IntPtr]$handle,[string[]]$items)
    [void]$this.Api.SendMessageW.Invoke($handle,[uint32]0x184,[IntPtr]::Zero,[IntPtr]::Zero)
    foreach($item in $items){
        $text=[Runtime.InteropServices.Marshal]::StringToHGlobalUni($item)
        try{
            $result=$this.Api.SendMessageW.Invoke($handle,[uint32]0x180,[IntPtr]::Zero,$text).ToInt64()
            if($result-lt0){throw 'List item insertion failed.'}
        } finally{[Runtime.InteropServices.Marshal]::FreeHGlobal($text)}
    }
}
$facade | Add-Member ScriptMethod SelectedIndex {
    param([IntPtr]$handle)
    $this.Api.SendMessageW.Invoke($handle,[uint32]0x188,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()
}
$facade | Add-Member ScriptMethod IsAlive {
    param([IntPtr]$handle)
    [bool]$this.Api.IsWindow.Invoke($handle)
}
$facade | Add-Member ScriptMethod Activate {
    param([IntPtr]$handle)
    [void]$this.Api.ShowWindow.Invoke($handle,9)
    [void]$this.Api.SetForegroundWindow.Invoke($handle)
}
$facade | Add-Member ScriptMethod Run {
    $message=$this.Native.Allocate(48)
    try {
        while ($true) {
            $result=$this.Api.GetMessageW.Invoke($message,[IntPtr]::Zero,[uint32]0,[uint32]0)
            if ($result -eq -1) { throw 'GetMessageW failed.' }
            if ($result -eq 0) { break }
            $kind=[Runtime.InteropServices.Marshal]::ReadInt32($message,8)
            $wparam=[Runtime.InteropServices.Marshal]::ReadIntPtr($message,16)
            $lparam=[Runtime.InteropServices.Marshal]::ReadIntPtr($message,24)
            if ($kind -eq 0x8002 -and $wparam -eq $this.Root) { break }
            if ($kind -eq 0x8001) {
                $id=[int]($wparam.ToInt64() -band 65535)
                $notification=[int](($wparam.ToInt64() -shr 16) -band 65535)
                if ($this.Actions.ContainsKey($id) -and $this.Actions[$id].Handle -eq $lparam) {
                    & $this.Actions[$id].Invoke $this $notification
                }
                continue
            }
            [void]$this.Api.TranslateMessage.Invoke($message)
            [void]$this.Api.DispatchMessageW.Invoke($message)
        }
    } finally { $this.Native.Free($message) }
}
$facade | Add-Member ScriptMethod Dispose {
    if ($this.Disposed) { return }
    for ($i=$this.Windows.Count-1;$i-ge0;$i--) {
        if ($this.Api.IsWindow.Invoke($this.Windows[$i])) { [void]$this.Api.DestroyWindow.Invoke($this.Windows[$i]) }
    }
    if (-not $this.Api.UnregisterClassW.Invoke($this.ClassName,$this.Module)) { throw 'Window class cleanup failed.' }
    [Runtime.InteropServices.Marshal]::FreeHGlobal($this.ClassName)
    $this.Windows.Clear(); $this.Actions.Clear()
    $this.WindowProcedure=$null
    [void]$this.Api.DeleteObject.Invoke($this.Font)
    [void]$this.Api.DeleteObject.Invoke($this.BackgroundBrush)
    [void]$this.Api.DeleteObject.Invoke($this.ButtonBrush)
    [void]$this.Api.DeleteObject.Invoke($this.ButtonBorder)
    $this.Native.Dispose(); $this.Disposed=$true
}
$facade
