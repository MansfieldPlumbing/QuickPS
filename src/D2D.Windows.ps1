[CmdletBinding()]
param()

if ($MyInvocation.InvocationName -eq '.') {
    throw 'D2D.Windows.ps1 must be invoked with &, not dot-sourced.'
}

$D2D = & {
    $assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        [Reflection.AssemblyName]::new('QuickPS.D2D.' + [Guid]::NewGuid().ToString('N')),
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

    $bind = ({
        param([IntPtr] $Object, [int] $Slot, [Type] $ReturnType, [Type[]] $ParameterTypes)
        $vtable = [Runtime.InteropServices.Marshal]::ReadIntPtr($Object)
        $address = [Runtime.InteropServices.Marshal]::ReadIntPtr($vtable, $Slot * [IntPtr]::Size)
        & $nativeCall $address $ReturnType (@([IntPtr]) + $ParameterTypes)
    }).GetNewClosure()

    $d2d1 = [Runtime.InteropServices.NativeLibrary]::Load('d2d1.dll')
    $dwrite = [Runtime.InteropServices.NativeLibrary]::Load('dwrite.dll')

    $createD2DFactoryPtr = [Runtime.InteropServices.NativeLibrary]::GetExport($d2d1, 'D2D1CreateFactory')
    $createDWriteFactoryPtr = [Runtime.InteropServices.NativeLibrary]::GetExport($dwrite, 'DWriteCreateFactory')

    # D2D1CreateFactory signature: HRESULT D2D1CreateFactory(D2D1_FACTORY_TYPE, REFIID, const D2D1_FACTORY_OPTIONS*, void**)
    $createD2DFactory = & $nativeCall $createD2DFactoryPtr ([int32]) @([int32], [IntPtr], [IntPtr], [IntPtr])
    
    # DWriteCreateFactory signature: HRESULT DWriteCreateFactory(DWRITE_FACTORY_TYPE, REFIID, IUnknown**)
    $createDWriteFactory = & $nativeCall $createDWriteFactoryPtr ([int32]) @([int32], [IntPtr], [IntPtr])

    return [PSCustomObject]@{
        PSTypeName = 'QuickPS.D2D'
        D2D1Handle = $d2d1
        DWriteHandle = $dwrite

        CreateFactory = ({
            # Materialize the captured binder locally for descendant closures.
            $bind = $bind
            # 0 = D2D1_FACTORY_TYPE_SINGLE_THREADED
            $iidPtr = [Runtime.InteropServices.Marshal]::AllocHGlobal(16)
            $factoryOut = [Runtime.InteropServices.Marshal]::AllocHGlobal([IntPtr]::Size)
            try {
                # ID2D1Factory IID: 06152247-6f50-465a-9245-118bfd3b6007
                [Runtime.InteropServices.Marshal]::Copy([Guid]::new('06152247-6f50-465a-9245-118bfd3b6007').ToByteArray(), 0, $iidPtr, 16)
                [Runtime.InteropServices.Marshal]::WriteIntPtr($factoryOut, [IntPtr]::Zero)
                $hr = $createD2DFactory.DynamicInvoke(@([int32]0, $iidPtr, [IntPtr]::Zero, $factoryOut))
                if ($hr -lt 0) { throw "D2D1CreateFactory failed with HR $hr" }
                $factoryPtr = [Runtime.InteropServices.Marshal]::ReadIntPtr($factoryOut)
                
                return [PSCustomObject]@{
                    PSTypeName = 'QuickPS.D2D.Factory'
                    Pointer = $factoryPtr
                    Release = ({
                        $releaseCall = & $bind $factoryPtr 2 ([int32]) @()
                        $releaseCall.DynamicInvoke(@($factoryPtr))
                    }).GetNewClosure()

                    CreateHwndRenderTarget = ({
                        param([IntPtr]$Hwnd, [int32]$Width, [int32]$Height)
                        $bind = $bind
                        $rtProps = [Runtime.InteropServices.Marshal]::AllocHGlobal(28)
                        $hwndProps = [Runtime.InteropServices.Marshal]::AllocHGlobal(24)
                        $rtOut = [Runtime.InteropServices.Marshal]::AllocHGlobal([IntPtr]::Size)
                        try {
                            # Zero memory
                            for ($i = 0; $i -lt 28; $i++) { [Runtime.InteropServices.Marshal]::WriteByte($rtProps, $i, 0) }
                            for ($i = 0; $i -lt 24; $i++) { [Runtime.InteropServices.Marshal]::WriteByte($hwndProps, $i, 0) }
                            
                            # Setup hwnd props
                            [Runtime.InteropServices.Marshal]::WriteIntPtr($hwndProps, 0, $Hwnd)
                            [Runtime.InteropServices.Marshal]::WriteInt32($hwndProps, [IntPtr]::Size, $Width)
                            [Runtime.InteropServices.Marshal]::WriteInt32($hwndProps, [IntPtr]::Size + 4, $Height)
                            [Runtime.InteropServices.Marshal]::WriteIntPtr($rtOut, [IntPtr]::Zero)

                            # CreateHwndRenderTarget is slot 14 on ID2D1Factory
                            $createRtCall = & $bind $factoryPtr 14 ([int32]) @([IntPtr], [IntPtr], [IntPtr])
                            $hr = $createRtCall.DynamicInvoke(@($factoryPtr, $rtProps, $hwndProps, $rtOut))
                            if ($hr -lt 0) { throw "CreateHwndRenderTarget failed with HR $hr" }
                            
                            $rtPtr = [Runtime.InteropServices.Marshal]::ReadIntPtr($rtOut)

                            return [PSCustomObject]@{
                                PSTypeName = 'QuickPS.D2D.HwndRenderTarget'
                                Pointer = $rtPtr
                                
                                Release = ({
                                    $releaseCall = & $bind $rtPtr 2 ([int32]) @()
                                    $releaseCall.DynamicInvoke(@($rtPtr))
                                }).GetNewClosure()

                                BeginDraw = ({
                                    $beginDrawCall = & $bind $rtPtr 48 ([void]) @()
                                    $beginDrawCall.DynamicInvoke(@($rtPtr))
                                }).GetNewClosure()

                                EndDraw = ({
                                    $tag1 = [Runtime.InteropServices.Marshal]::AllocHGlobal(8)
                                    $tag2 = [Runtime.InteropServices.Marshal]::AllocHGlobal(8)
                                    try {
                                        $endDrawCall = & $bind $rtPtr 49 ([int32]) @([IntPtr], [IntPtr])
                                        return $endDrawCall.DynamicInvoke(@($rtPtr, $tag1, $tag2))
                                    } finally {
                                        [Runtime.InteropServices.Marshal]::FreeHGlobal($tag1)
                                        [Runtime.InteropServices.Marshal]::FreeHGlobal($tag2)
                                    }
                                }).GetNewClosure()

                                ClearColor = ({
                                    param([single]$R, [single]$G, [single]$B, [single]$A = 1.0)
                                    $colorPtr = [Runtime.InteropServices.Marshal]::AllocHGlobal(16)
                                    try {
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($R), 0, $colorPtr, 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($G), 0, [IntPtr]::new($colorPtr.ToInt64() + 4), 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($B), 0, [IntPtr]::new($colorPtr.ToInt64() + 8), 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($A), 0, [IntPtr]::new($colorPtr.ToInt64() + 12), 4)
                                        
                                        $clearCall = & $bind $rtPtr 47 ([void]) @([IntPtr])
                                        $clearCall.DynamicInvoke(@($rtPtr, $colorPtr))
                                    } finally {
                                        [Runtime.InteropServices.Marshal]::FreeHGlobal($colorPtr)
                                    }
                                }).GetNewClosure()
                                
                                Resize = ({
                                    param([int32]$Width, [int32]$Height)
                                    $sizePtr = [Runtime.InteropServices.Marshal]::AllocHGlobal(8)
                                    try {
                                        [Runtime.InteropServices.Marshal]::WriteInt32($sizePtr, 0, $Width)
                                        [Runtime.InteropServices.Marshal]::WriteInt32($sizePtr, 4, $Height)
                                        # Slot 58 is Resize on ID2D1HwndRenderTarget
                                        $resizeCall = & $bind $rtPtr 58 ([int32]) @([IntPtr])
                                        return $resizeCall.DynamicInvoke(@($rtPtr, $sizePtr))
                                    } finally {
                                        [Runtime.InteropServices.Marshal]::FreeHGlobal($sizePtr)
                                    }
                                }).GetNewClosure()

                                CreateSolidColorBrush = ({
                                    param([single]$R, [single]$G, [single]$B, [single]$A = 1.0)
                                    $bind = $bind
                                    $colorPtr = [Runtime.InteropServices.Marshal]::AllocHGlobal(16)
                                    $brushOut = [Runtime.InteropServices.Marshal]::AllocHGlobal([IntPtr]::Size)
                                    try {
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($R), 0, $colorPtr, 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($G), 0, [IntPtr]::new($colorPtr.ToInt64() + 4), 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($B), 0, [IntPtr]::new($colorPtr.ToInt64() + 8), 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($A), 0, [IntPtr]::new($colorPtr.ToInt64() + 12), 4)
                                        [Runtime.InteropServices.Marshal]::WriteIntPtr($brushOut, [IntPtr]::Zero)
                                        
                                        # Slot 8: CreateSolidColorBrush
                                        $createBrushCall = & $bind $rtPtr 8 ([int32]) @([IntPtr], [IntPtr], [IntPtr])
                                        $hr = $createBrushCall.DynamicInvoke(@($rtPtr, $colorPtr, [IntPtr]::Zero, $brushOut))
                                        if ($hr -lt 0) { throw "CreateSolidColorBrush failed with HR $hr" }
                                        
                                        $brushPtr = [Runtime.InteropServices.Marshal]::ReadIntPtr($brushOut)
                                        return [PSCustomObject]@{
                                            PSTypeName = 'QuickPS.D2D.SolidColorBrush'
                                            Pointer = $brushPtr
                                            Release = ({
                                                $releaseCall = & $bind $brushPtr 2 ([int32]) @()
                                                $releaseCall.DynamicInvoke(@($brushPtr))
                                            }).GetNewClosure()
                                        }
                                    } finally {
                                        [Runtime.InteropServices.Marshal]::FreeHGlobal($colorPtr)
                                        [Runtime.InteropServices.Marshal]::FreeHGlobal($brushOut)
                                    }
                                }).GetNewClosure()

                                FillRectangle = ({
                                    param([single]$Left, [single]$Top, [single]$Right, [single]$Bottom, [object]$Brush)
                                    $rectPtr = [Runtime.InteropServices.Marshal]::AllocHGlobal(16)
                                    try {
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($Left), 0, $rectPtr, 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($Top), 0, [IntPtr]::new($rectPtr.ToInt64() + 4), 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($Right), 0, [IntPtr]::new($rectPtr.ToInt64() + 8), 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($Bottom), 0, [IntPtr]::new($rectPtr.ToInt64() + 12), 4)
                                        
                                        $brushPtr = if ($Brush -is [IntPtr]) { $Brush } else { $Brush.Pointer }
                                        
                                        # Slot 17: FillRectangle
                                        $fillCall = & $bind $rtPtr 17 ([void]) @([IntPtr], [IntPtr])
                                        $fillCall.DynamicInvoke(@($rtPtr, $rectPtr, $brushPtr))
                                    } finally {
                                        [Runtime.InteropServices.Marshal]::FreeHGlobal($rectPtr)
                                    }
                                }).GetNewClosure()

                                DrawRectangle = ({
                                    param([single]$Left, [single]$Top, [single]$Right, [single]$Bottom, [object]$Brush, [single]$StrokeWidth = 1.0)
                                    $rectPtr = [Runtime.InteropServices.Marshal]::AllocHGlobal(16)
                                    try {
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($Left), 0, $rectPtr, 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($Top), 0, [IntPtr]::new($rectPtr.ToInt64() + 4), 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($Right), 0, [IntPtr]::new($rectPtr.ToInt64() + 8), 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($Bottom), 0, [IntPtr]::new($rectPtr.ToInt64() + 12), 4)
                                        
                                        $brushPtr = if ($Brush -is [IntPtr]) { $Brush } else { $Brush.Pointer }
                                        
                                        # Slot 16: DrawRectangle
                                        $drawCall = & $bind $rtPtr 16 ([void]) @([IntPtr], [IntPtr], [single], [IntPtr])
                                        $drawCall.DynamicInvoke(@($rtPtr, $rectPtr, $brushPtr, $StrokeWidth, [IntPtr]::Zero))
                                    } finally {
                                        [Runtime.InteropServices.Marshal]::FreeHGlobal($rectPtr)
                                    }
                                }).GetNewClosure()

                                DrawText = ({
                                    param([string]$Text, [single]$Left, [single]$Top, [single]$Right, [single]$Bottom, [object]$TextFormat, [object]$Brush)
                                    $rectPtr = [Runtime.InteropServices.Marshal]::AllocHGlobal(16)
                                    try {
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($Left), 0, $rectPtr, 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($Top), 0, [IntPtr]::new($rectPtr.ToInt64() + 4), 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($Right), 0, [IntPtr]::new($rectPtr.ToInt64() + 8), 4)
                                        [Runtime.InteropServices.Marshal]::Copy([BitConverter]::GetBytes($Bottom), 0, [IntPtr]::new($rectPtr.ToInt64() + 12), 4)
                                        
                                        $textPtr = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($Text)
                                        try {
                                            $textLen = $Text.Length
                                            $formatPtr = if ($TextFormat -is [IntPtr]) { $TextFormat } else { $TextFormat.Pointer }
                                            $brushPtr = if ($Brush -is [IntPtr]) { $Brush } else { $Brush.Pointer }

                                            # Slot 27: DrawText
                                            $drawTextCall = & $bind $rtPtr 27 ([void]) @([IntPtr], [uint32], [IntPtr], [IntPtr], [IntPtr], [uint32], [uint32])
                                            $drawTextCall.DynamicInvoke(@($rtPtr, $textPtr, [uint32]$textLen, $formatPtr, $rectPtr, $brushPtr, [uint32]0, [uint32]0))
                                        } finally {
                                            [Runtime.InteropServices.Marshal]::FreeHGlobal($textPtr)
                                        }
                                    } finally {
                                        [Runtime.InteropServices.Marshal]::FreeHGlobal($rectPtr)
                                    }
                                }).GetNewClosure()
                            }
                        } finally {
                            [Runtime.InteropServices.Marshal]::FreeHGlobal($rtProps)
                            [Runtime.InteropServices.Marshal]::FreeHGlobal($hwndProps)
                            [Runtime.InteropServices.Marshal]::FreeHGlobal($rtOut)
                        }
                    }).GetNewClosure()
                }
            } finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($iidPtr)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($factoryOut)
            }
        }).GetNewClosure()

        CreateDWriteFactory = ({
            $bind = $bind
            $iidPtr = [Runtime.InteropServices.Marshal]::AllocHGlobal(16)
            $factoryOut = [Runtime.InteropServices.Marshal]::AllocHGlobal([IntPtr]::Size)
            try {
                # IDWriteFactory IID: b859ee5a-d838-4b5b-a2e8-1adc7d93db48
                [Runtime.InteropServices.Marshal]::Copy([Guid]::new('b859ee5a-d838-4b5b-a2e8-1adc7d93db48').ToByteArray(), 0, $iidPtr, 16)
                [Runtime.InteropServices.Marshal]::WriteIntPtr($factoryOut, [IntPtr]::Zero)
                
                # 0 = DWRITE_FACTORY_TYPE_SHARED
                $hr = $createDWriteFactory.DynamicInvoke(@([int32]0, $iidPtr, $factoryOut))
                if ($hr -lt 0) { throw "DWriteCreateFactory failed with HR $hr" }
                
                $factoryPtr = [Runtime.InteropServices.Marshal]::ReadIntPtr($factoryOut)
                return [PSCustomObject]@{
                    PSTypeName = 'QuickPS.DWrite.Factory'
                    Pointer = $factoryPtr
                    Release = ({
                        $releaseCall = & $bind $factoryPtr 2 ([int32]) @()
                        $releaseCall.DynamicInvoke(@($factoryPtr))
                    }).GetNewClosure()

                    CreateTextFormat = ({
                        param(
                            [string] $FontFamilyName,
                            [single] $FontSize,
                            [uint32] $FontWeight = 400,
                            [uint32] $FontStyle = 0,
                            [uint32] $FontStretch = 5
                        )
                        $bind = $bind
                        $familyPtr = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($FontFamilyName)
                        $localePtr = [Runtime.InteropServices.Marshal]::StringToHGlobalUni('en-US')
                        
                        $formatOut = [Runtime.InteropServices.Marshal]::AllocHGlobal([IntPtr]::Size)
                        try {
                            [Runtime.InteropServices.Marshal]::WriteIntPtr($formatOut, [IntPtr]::Zero)

                            # Slot 15: CreateTextFormat
                            $call = & $bind $factoryPtr 15 ([int32]) @([IntPtr], [IntPtr], [uint32], [uint32], [uint32], [single], [IntPtr], [IntPtr])
                            $hr = $call.DynamicInvoke(@($factoryPtr, $familyPtr, [IntPtr]::Zero, $FontWeight, $FontStyle, $FontStretch, $FontSize, $localePtr, $formatOut))
                            
                            $formatPtr = [Runtime.InteropServices.Marshal]::ReadIntPtr($formatOut)
                            if ($hr -lt 0) { throw "CreateTextFormat failed with HR $hr" }

                            return [PSCustomObject]@{
                                PSTypeName = 'QuickPS.DWrite.TextFormat'
                                Pointer = $formatPtr
                                Release = ({
                                    $releaseCall = & $bind $formatPtr 2 ([int32]) @()
                                    $releaseCall.DynamicInvoke(@($formatPtr))
                                }).GetNewClosure()
                            }
                        } finally {
                            [Runtime.InteropServices.Marshal]::FreeHGlobal($familyPtr)
                            [Runtime.InteropServices.Marshal]::FreeHGlobal($localePtr)
                            [Runtime.InteropServices.Marshal]::FreeHGlobal($formatOut)
                        }
                    }).GetNewClosure()
                }
            } finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($iidPtr)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($factoryOut)
            }
        }).GetNewClosure()
    }
}.GetNewClosure()


return $D2D



