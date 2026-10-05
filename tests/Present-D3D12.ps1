[CmdletBinding()]
param(
    [single[]] $Color = @([single]0.0, [single]0.45, [single]0.85, [single]1.0),
    [int] $Seconds = 4,
    [string] $ScreenshotPath
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src'))
$window = $null
$dxgi = $null
$gpu = $null

try {
    $window = & (Join-Path $root 'Window.Windows.ps1') -Width 720 -Height 420 `
        -Title 'QuickPS D3D12 PRESENT PASS' -BackgroundColor 0x330000
    $null = $window.Show()
    $dxgi = & (Join-Path $root 'DXGI.Windows.ps1')
    $adapter = $dxgi.GetAdapter(0)
    $gpu = & (Join-Path $root 'D3D12.Windows.ps1') -Adapter $adapter
    $queue = $gpu.CreateCommandQueue()
    $swapChain = $dxgi.CreateSwapChainForWindow($queue, $window.Hwnd, 720, 420, 2)
    $buffers = @($dxgi.GetBuffer($swapChain, 0), $dxgi.GetBuffer($swapChain, 1))
    $heap = $gpu.CreateRtvHeap(2)
    $increment = $gpu.GetRtvIncrementSize()
    $start = $gpu.GetCpuDescriptorHandleStart($heap)
    $handles = @(
        $start,
        [IntPtr]::new($start.ToInt64() + $increment)
    )
    $gpu.CreateRenderTargetView($buffers[0], $handles[0])
    $gpu.CreateRenderTargetView($buffers[1], $handles[1])
    $allocators = @($gpu.CreateCommandAllocator(), $gpu.CreateCommandAllocator())
    $commandList = $gpu.CreateCommandList($allocators[0])
    $fence = $gpu.CreateFence(0)

    for ($frame = 0; $frame -lt 2; $frame++) {
        $index = $dxgi.GetCurrentBackBufferIndex($swapChain)
        if ($frame -gt 0) {
            $null = $gpu.ResetCommandAllocator($allocators[$index])
            $null = $gpu.ResetCommandList($commandList, $allocators[$index])
        }
        $gpu.Transition($commandList, $buffers[$index], 0, 4)
        $gpu.ClearRenderTarget($commandList, $handles[$index], $Color)
        $gpu.Transition($commandList, $buffers[$index], 4, 0)
        $null = $gpu.CloseCommandList($commandList)
        $gpu.ExecuteCommandLists($queue, @($commandList))
        $null = $dxgi.Present($swapChain, 1, 0)
        $value = [uint64]($frame + 1)
        $null = $gpu.Signal($queue, $fence, $value)
        $null = $gpu.Wait($fence, $value, 5000)
    }

    [PSCustomObject]@{
        Hwnd = $window.Hwnd
        Width = 720
        Height = 420
        BufferCount = $buffers.Count
        RtvIncrement = $increment
        FenceValue = $gpu.GetCompletedValue($fence)
        Presented = $true
    } | Format-List

    if ($ScreenshotPath) {
        $native = & (Join-Path $root 'Native.ps1')
        try {
            $getRect = $native.GetExportCall(
                'user32.dll', 'GetWindowRect', ([bool]), [Type[]]@([IntPtr], [IntPtr]))
            $rect = $native.Allocate(16)
            try {
                if (-not $getRect.DynamicInvoke($window.Hwnd, $rect)) { throw 'GetWindowRect failed.' }
                $left = [Runtime.InteropServices.Marshal]::ReadInt32($rect, 0)
                $top = [Runtime.InteropServices.Marshal]::ReadInt32($rect, 4)
                $right = [Runtime.InteropServices.Marshal]::ReadInt32($rect, 8)
                $bottom = [Runtime.InteropServices.Marshal]::ReadInt32($rect, 12)
            }
            finally { $native.Free($rect) }
            [void][Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath((Join-Path $PSHOME 'System.Drawing.Common.dll'))
            $bitmap = [Drawing.Bitmap]::new($right - $left, $bottom - $top)
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $printWindow = $native.GetExportCall(
                    'user32.dll', 'PrintWindow', ([bool]), [Type[]]@([IntPtr], [IntPtr], [uint32]))
                $deviceContext = $graphics.GetHdc()
                try {
                    if (-not $printWindow.DynamicInvoke($window.Hwnd, $deviceContext, [uint32]2)) {
                        throw 'PrintWindow failed.'
                    }
                }
                finally { $graphics.ReleaseHdc($deviceContext) }
                $bitmap.Save([IO.Path]::GetFullPath($ScreenshotPath), [Drawing.Imaging.ImageFormat]::Png)
            }
            finally { $graphics.Dispose(); $bitmap.Dispose() }
        }
        finally { $native.Dispose() }
    }

    if ($Seconds -le 0) { $null = $window.Run() }
}
finally {
    if ($gpu) { $gpu.Dispose() }
    if ($dxgi) { $dxgi.Dispose() }
    if ($window) { $window.Dispose() }
}
