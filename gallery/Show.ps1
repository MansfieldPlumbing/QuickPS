[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Native', 'Window', 'Wic', 'Wasapi', 'MediaFoundation', 'Composition', 'DXGI', 'D3D12', 'Shader')]
    [string] $Name,
    [switch] $Verify
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src'))
$owned = [Collections.Generic.List[object]]::new()

function Use-Binder([string] $File, [hashtable] $Arguments = @{}) {
    $value = & (Join-Path $root $File) @Arguments
    if ($value -and $value.PSObject.Methods['Dispose']) { $owned.Add($value) }
    $value
}

function Show-ResultWindow([string] $Text, [uint32] $Color = 0x0033CC) {
    $window = Use-Binder 'Window.Windows.ps1' @{
        Width = 760
        Height = 440
        Title = $Text
        BackgroundColor = $Color
    }
    $null = $window.Show()
    if($Verify){$null=$window.Close()}
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host 'Close the blue window to finish.' -ForegroundColor Gray
    $null = $window.Run()
}

function Wait-ResultWindow($Window, [string] $Text) {
    if($Verify){$null=$Window.Close()}
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host 'Close the window to finish.' -ForegroundColor Gray
    $null = $Window.Run()
}

try {
    switch ($Name) {
        Native {
            $native = Use-Binder 'Native.ps1'
            $call = $native.GetExportCall('kernel32.dll', 'GetCurrentProcessId', ([uint32]), [Type[]]@())
            $nativePid = [uint32]$call.DynamicInvoke()
            if ($nativePid -ne [Environment]::ProcessId) { throw 'Native process ID mismatch.' }
            Show-ResultWindow "QuickPS Native PASS - PID $nativePid"
        }
        Window {
            Show-ResultWindow 'QuickPS Window PASS - responsive HWND'
        }
        Wic {
            $wic = Use-Binder 'Wic.Windows.ps1'
            $bitmap = $wic.CreateBitmap(320, 180)
            $size = $wic.GetSize($bitmap)
            Show-ResultWindow "QuickPS WIC PASS - bitmap $($size.Width)x$($size.Height)"
        }
        Wasapi {
            & (Join-Path $PSScriptRoot 'Wasapi.ps1')
        }
        MediaFoundation {
            $media = Use-Binder 'MediaFoundation.Windows.ps1'
            $devices = @($media.EnumerateVideoDevices())
            try {
                Show-ResultWindow "QuickPS Media Foundation PASS - $($devices.Count) video device(s)"
            }
            finally {
                foreach ($device in $devices) {
                    if ($device -ne [IntPtr]::Zero) {
                        [void](& $media.ComCall $device 2 ([uint32]) @() @())
                    }
                }
            }
        }
        DXGI {
            $dxgi = Use-Binder 'DXGI.Windows.ps1'
            $adapter = $dxgi.GetAdapter(0)
            $description = $dxgi.GetAdapterDescription($adapter)
            Show-ResultWindow "QuickPS DXGI PASS - $($description.Description)"
        }
        D3D12 {
            $window = Use-Binder 'Window.Windows.ps1' @{
                Width = 760
                Height = 440
                Title = 'QuickPS D3D12 PRESENT PASS - two buffers'
                BackgroundColor = 0x330000
            }
            $null = $window.Show()
            $dxgi = Use-Binder 'DXGI.Windows.ps1'
            $adapter = $dxgi.GetAdapter(0)
            $gpu = Use-Binder 'D3D12.Windows.ps1' @{ Adapter = $adapter }
            $queue = $gpu.CreateCommandQueue()
            $swapChain = $dxgi.CreateSwapChainForWindow($queue, $window.Hwnd, 760, 440, 2)
            $buffers = @($dxgi.GetBuffer($swapChain, 0), $dxgi.GetBuffer($swapChain, 1))
            $heap = $gpu.CreateRtvHeap(2)
            $increment = $gpu.GetRtvIncrementSize()
            $start = $gpu.GetCpuDescriptorHandleStart($heap)
            $handles = @($start, [IntPtr]::new($start.ToInt64() + $increment))
            $gpu.CreateRenderTargetView($buffers[0], $handles[0])
            $gpu.CreateRenderTargetView($buffers[1], $handles[1])
            $allocators = @($gpu.CreateCommandAllocator(), $gpu.CreateCommandAllocator())
            $commandList = $gpu.CreateCommandList($allocators[0])
            $fence = $gpu.CreateFence(0)
            $color = [single[]]@(0.0, 0.45, 0.85, 1.0)
            for ($frame = 0; $frame -lt 2; $frame++) {
                $index = $dxgi.GetCurrentBackBufferIndex($swapChain)
                if ($frame -gt 0) {
                    $null = $gpu.ResetCommandAllocator($allocators[$index])
                    $null = $gpu.ResetCommandList($commandList, $allocators[$index])
                }
                $gpu.Transition($commandList, $buffers[$index], 0, 4)
                $gpu.ClearRenderTarget($commandList, $handles[$index], $color)
                $gpu.Transition($commandList, $buffers[$index], 4, 0)
                $null = $gpu.CloseCommandList($commandList)
                $gpu.ExecuteCommandLists($queue, @($commandList))
                $null = $dxgi.Present($swapChain, 1, 0)
                $value = [uint64]($frame + 1)
                $null = $gpu.Signal($queue, $fence, $value)
                $null = $gpu.Wait($fence, $value, 5000)
            }
            Wait-ResultWindow $window "QuickPS D3D12 PRESENT PASS - fence $($gpu.GetCompletedValue($fence))"
        }
        Shader {
            $shader = Use-Binder 'Shader.Windows.ps1'
            $source = 'float4 main() : SV_Target { return float4(0.0,0.2,0.8,1.0); }'
            $bytes = $shader.Compile($source, 'main', 'ps_5_0')
            Show-ResultWindow "QuickPS Shader PASS - $($bytes.Length) byte pixel shader"
        }
        Composition {
            $native = Use-Binder 'Native.ps1'
            $create = $native.GetExportCall(
                'd3d11.dll', 'D3D11CreateDevice', ([int32]),
                [Type[]]@([IntPtr],[uint32],[IntPtr],[uint32],[IntPtr],[uint32],[uint32],[IntPtr],[IntPtr],[IntPtr]))
            $deviceOut = $native.Allocate([IntPtr]::Size)
            $contextOut = $native.Allocate([IntPtr]::Size)
            $device = [IntPtr]::Zero
            $context = [IntPtr]::Zero
            $dxgiDevice = [IntPtr]::Zero
            try {
                $hr = [int32]$create.DynamicInvoke(
                    [IntPtr]::Zero, [uint32]1, [IntPtr]::Zero, [uint32]0,
                    [IntPtr]::Zero, [uint32]0, [uint32]7,
                    $deviceOut, [IntPtr]::Zero, $contextOut)
                if ($hr -lt 0) { throw ('D3D11CreateDevice failed: 0x{0:X8}' -f [uint32]$hr) }
                $device = [Runtime.InteropServices.Marshal]::ReadIntPtr($deviceOut)
                $context = [Runtime.InteropServices.Marshal]::ReadIntPtr($contextOut)
                $iid = $native.Allocate(16)
                $dxgiOut = $native.Allocate([IntPtr]::Size)
                try {
                    [Runtime.InteropServices.Marshal]::Copy(
                        ([Guid]'54ec77fa-1377-44e6-8c32-88fd5f44c84c').ToByteArray(), 0, $iid, 16)
                    $query = $native.GetComCall($device, 0, ([int32]), [Type[]]@([IntPtr], [IntPtr]))
                    $hr = [int32]$query.DynamicInvoke($device, $iid, $dxgiOut)
                    if ($hr -lt 0) { throw ('IDXGIDevice query failed: 0x{0:X8}' -f [uint32]$hr) }
                    $dxgiDevice = [Runtime.InteropServices.Marshal]::ReadIntPtr($dxgiOut)
                }
                finally { $native.Free($iid); $native.Free($dxgiOut) }
                $composition = Use-Binder 'Composition.Windows.ps1' @{ DxgiDevice = $dxgiDevice }
                $visual = $composition.CreateVisual()
                $null = $composition.Commit()
                $null = $composition.WaitForCommitCompletion()
                Show-ResultWindow "QuickPS Composition PASS - visual 0x$($visual.ToInt64().ToString('X'))"
            }
            finally {
                $native.Free($deviceOut)
                $native.Free($contextOut)
                if ($dxgiDevice -ne [IntPtr]::Zero) { [void]$native.ReleaseCom($dxgiDevice) }
                if ($context -ne [IntPtr]::Zero) { [void]$native.ReleaseCom($context) }
                if ($device -ne [IntPtr]::Zero) { [void]$native.ReleaseCom($device) }
            }
        }
    }
}
catch {
    Write-Host ''
    Write-Host "QuickPS $Name FAILED" -ForegroundColor White -BackgroundColor Black
    Write-Host ($_ | Out-String) -ForegroundColor White -BackgroundColor Black
    if(-not $Verify){Read-Host 'Press Enter to exit'}
    exit 1
}
finally {
    for ($index = $owned.Count - 1; $index -ge 0; $index--) {
        try { $owned[$index].Dispose() } catch { }
    }
}
