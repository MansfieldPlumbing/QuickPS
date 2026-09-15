[CmdletBinding()]
param()

if ($MyInvocation.InvocationName -eq '.') {
    throw 'Shader.Windows.ps1 must be invoked with &, not dot-sourced.'
}

$Shader = & {
    $assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        [Reflection.AssemblyName]::new('QuickPS.Shader.' + [Guid]::NewGuid().ToString('N')),
        [Reflection.Emit.AssemblyBuilderAccess]::Run)
    $module = $assembly.DefineDynamicModule('Native')
    $types = [Collections.Generic.Dictionary[string, Type]]::new()
    $calls = [Collections.Generic.Dictionary[string, Delegate]]::new()

    $nativeCall = ({
        param([IntPtr] $Address, [Type] $ReturnType, [Type[]] $ParameterTypes)
        $signature = $ReturnType.FullName + ':' + (($ParameterTypes | ForEach-Object FullName) -join ',')
        if (-not $types.ContainsKey($signature)) {
            $builder = $module.DefineType(
                'Call_' + [Guid]::NewGuid().ToString('N'),
                'Class,Public,Sealed', [MulticastDelegate])
            $constructor = $builder.DefineConstructor(
                'Public,HideBySig,RTSpecialName',
                [Reflection.CallingConventions]::Standard, @([object], [IntPtr]))
            $constructor.SetImplementationFlags('Runtime,Managed')
            $invoke = $builder.DefineMethod(
                'Invoke', 'Public,HideBySig,NewSlot,Virtual', $ReturnType, $ParameterTypes)
            $invoke.SetImplementationFlags('Runtime,Managed')
            $attribute = [Reflection.Emit.CustomAttributeBuilder]::new(
                [Runtime.InteropServices.UnmanagedFunctionPointerAttribute].GetConstructor(
                    @([Runtime.InteropServices.CallingConvention])),
                @([Runtime.InteropServices.CallingConvention]::StdCall))
            $builder.SetCustomAttribute($attribute)
            $types[$signature] = $builder.CreateType()
        }
        $key = $Address.ToInt64().ToString() + ':' + $signature
        if (-not $calls.ContainsKey($key)) {
            $calls[$key] = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer(
                $Address, $types[$signature])
        }
        $calls[$key]
    }).GetNewClosure()

    $comCall = ({
        param([IntPtr] $Object, [int] $Slot, [Type] $ReturnType)
        $vtable = [Runtime.InteropServices.Marshal]::ReadIntPtr($Object)
        $address = [Runtime.InteropServices.Marshal]::ReadIntPtr(
            $vtable, $Slot * [IntPtr]::Size)
        $call = & $nativeCall $address $ReturnType @([IntPtr])
        $call.DynamicInvoke($Object)
    }).GetNewClosure()

    $compilerLibrary = [Runtime.InteropServices.NativeLibrary]::Load('d3dcompiler_47.dll')
    $compile = & $nativeCall (
        [Runtime.InteropServices.NativeLibrary]::GetExport($compilerLibrary, 'D3DCompile')
    ) ([int32]) @(
        [IntPtr], [UIntPtr], [IntPtr], [IntPtr], [IntPtr], [IntPtr],
        [IntPtr], [uint32], [uint32], [IntPtr], [IntPtr])

    $instance = [PSCustomObject]@{
        PSTypeName = 'QuickPS.Shader.Windows'
        CompileCall = $compile
        ComCall = $comCall
    }

    $instance | Add-Member ScriptMethod Compile ({
        param(
            [Parameter(Mandatory)][string] $Source,
            [Parameter(Mandatory)][string] $EntryPoint,
            [Parameter(Mandatory)][string] $Target,
            [uint32] $Flags = 0
        )
        $sourceBytes = [Text.Encoding]::UTF8.GetBytes($Source)
        $sourceBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($sourceBytes.Length)
        $entryBuffer = [Runtime.InteropServices.Marshal]::StringToCoTaskMemUTF8($EntryPoint)
        $targetBuffer = [Runtime.InteropServices.Marshal]::StringToCoTaskMemUTF8($Target)
        $codeOut = [Runtime.InteropServices.Marshal]::AllocHGlobal([IntPtr]::Size)
        $errorsOut = [Runtime.InteropServices.Marshal]::AllocHGlobal([IntPtr]::Size)
        [Runtime.InteropServices.Marshal]::WriteIntPtr($codeOut, [IntPtr]::Zero)
        [Runtime.InteropServices.Marshal]::WriteIntPtr($errorsOut, [IntPtr]::Zero)
        $codeBlob = [IntPtr]::Zero
        $errorsBlob = [IntPtr]::Zero
        try {
            [Runtime.InteropServices.Marshal]::Copy(
                $sourceBytes, 0, $sourceBuffer, $sourceBytes.Length)
            $hr = [int32]$this.CompileCall.DynamicInvoke(
                $sourceBuffer, [UIntPtr]::new([uint64]$sourceBytes.Length),
                [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero,
                $entryBuffer, $targetBuffer, $Flags, [uint32]0, $codeOut, $errorsOut)
            $codeBlob = [Runtime.InteropServices.Marshal]::ReadIntPtr($codeOut)
            $errorsBlob = [Runtime.InteropServices.Marshal]::ReadIntPtr($errorsOut)
            if ($hr -lt 0 -or $codeBlob -eq [IntPtr]::Zero) {
                $message = 'No compiler diagnostic was returned.'
                if ($errorsBlob -ne [IntPtr]::Zero) {
                    $errorPointer = & $this.ComCall $errorsBlob 3 ([IntPtr])
                    $errorLength = [uint64](& $this.ComCall $errorsBlob 4 ([UIntPtr])).ToUInt64()
                    if ($errorPointer -ne [IntPtr]::Zero -and $errorLength) {
                        $message = [Runtime.InteropServices.Marshal]::PtrToStringAnsi(
                            $errorPointer, [int]$errorLength).TrimEnd([char]0)
                    }
                }
                throw ('D3DCompile failed: 0x{0:X8}: {1}' -f [uint32]$hr, $message)
            }
            $bytecodePointer = & $this.ComCall $codeBlob 3 ([IntPtr])
            $bytecodeLength = [uint64](& $this.ComCall $codeBlob 4 ([UIntPtr])).ToUInt64()
            if ($bytecodePointer -eq [IntPtr]::Zero -or $bytecodeLength -eq 0) {
                throw 'D3DCompile returned an empty shader blob.'
            }
            $bytecode = [byte[]]::new([int]$bytecodeLength)
            [Runtime.InteropServices.Marshal]::Copy(
                $bytecodePointer, $bytecode, 0, $bytecode.Length)
            $bytecode
        }
        finally {
            if ($errorsBlob -ne [IntPtr]::Zero) {
                [void](& $this.ComCall $errorsBlob 2 ([uint32]))
            }
            if ($codeBlob -ne [IntPtr]::Zero) {
                [void](& $this.ComCall $codeBlob 2 ([uint32]))
            }
            [Runtime.InteropServices.Marshal]::FreeHGlobal($codeOut)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($errorsOut)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($sourceBuffer)
            [Runtime.InteropServices.Marshal]::FreeCoTaskMem($entryBuffer)
            [Runtime.InteropServices.Marshal]::FreeCoTaskMem($targetBuffer)
        }
    }.GetNewClosure())

    $instance | Add-Member ScriptMethod Dispose ({
        $this.CompileCall = $null
        $this.ComCall = $null
    }.GetNewClosure())

    $instance
}

$Shader
