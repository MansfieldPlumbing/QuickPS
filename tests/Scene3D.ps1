[CmdletBinding()]
param([int] $Seconds = 4, [string] $ScreenshotPath, [ValidateSet('Box','Plane','Sphere','Cylinder','Cone','Torus','Capsule')] [string] $Shape = 'Box')

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src'))
$window = $dxgi = $gpu = $shader = $native = $null

$hlsl = @'
struct VertexOutput { float4 Position : SV_POSITION; float3 Color : COLOR0; };
cbuffer Camera : register(b0) { row_major float4x4 ViewProjection; };

VertexOutput VSMain(float3 position : POSITION, float3 color : COLOR) {
    float3 p = position;
    float sy = sin(0.65), cy = cos(0.65), sx = sin(-0.45), cx = cos(-0.45);
    p = float3(cy*p.x + sy*p.z, p.y, -sy*p.x + cy*p.z);
    p = float3(p.x, cx*p.y - sx*p.z, sx*p.y + cx*p.z);
    VertexOutput output;
    output.Position = mul(float4(p, 1), ViewProjection);
    output.Color = color;
    return output;
}

float4 PSMain(VertexOutput input) : SV_TARGET { return float4(input.Color, 1); }
'@

try {
    $window = & (Join-Path $root 'Window.Windows.ps1') -Width 720 -Height 420 `
        -Title "QuickPS Scene3D - D3D12 $Shape" -BackgroundColor 0x330000
    $null = $window.Show()
    $dxgi = & (Join-Path $root 'DXGI.Windows.ps1')
    $adapter = $dxgi.GetAdapter(0)
    $gpu = & (Join-Path $root 'D3D12.Windows.ps1') -Adapter $adapter
    $shader = & (Join-Path $root 'Shader.Windows.ps1')
    $geometry = & (Join-Path $root 'Geometry3D.ps1') $Shape
    $camera = & (Join-Path $root 'Camera3D.ps1') -AspectRatio (720.0/420.0)
    $layout = @(
        [PSCustomObject]@{ Semantic='POSITION'; SemanticIndex=0; Format=6; Slot=0; Offset=0 },
        [PSCustomObject]@{ Semantic='COLOR'; SemanticIndex=0; Format=6; Slot=0; Offset=12 }
    )
    $pipeline = $gpu.CreateGraphicsPipeline(
        $shader.Compile($hlsl, 'VSMain', 'vs_5_0'),
        $shader.Compile($hlsl, 'PSMain', 'ps_5_0'), 87, $true, $layout, 16)
    $vertexBuffer = $gpu.CreateUploadBuffer($geometry.VertexBytes)
    $indexBuffer = $gpu.CreateUploadBuffer($geometry.IndexBytes)
    $queue = $gpu.CreateCommandQueue()
    $swapChain = $dxgi.CreateSwapChainForWindow($queue, $window.Hwnd, 720, 420, 2)
    $buffers = @($dxgi.GetBuffer($swapChain, 0), $dxgi.GetBuffer($swapChain, 1))
    $heap = $gpu.CreateRtvHeap(2)
    $increment = $gpu.GetRtvIncrementSize()
    $start = $gpu.GetCpuDescriptorHandleStart($heap)
    $handles = @($start, [IntPtr]::new($start.ToInt64() + $increment))
    $gpu.CreateRenderTargetView($buffers[0], $handles[0])
    $gpu.CreateRenderTargetView($buffers[1], $handles[1])
    $depth = $gpu.CreateDepthTarget(720, 420)
    $allocators = @($gpu.CreateCommandAllocator(), $gpu.CreateCommandAllocator())
    $list = $gpu.CreateCommandList($allocators[0])
    $fence = $gpu.CreateFence(0)
    for ($frame = 0; $frame -lt 2; $frame++) {
        $index = $dxgi.GetCurrentBackBufferIndex($swapChain)
        if ($frame) {
            $null = $gpu.ResetCommandAllocator($allocators[$index])
            $null = $gpu.ResetCommandList($list, $allocators[$index])
        }
        $gpu.Transition($list, $buffers[$index], 0, 4)
        $gpu.ClearRenderTarget($list, $handles[$index], [single[]]@(0.015,0.025,0.06,1))
        $gpu.ClearDepth($list, $depth.Handle, 1.0)
        $gpu.DrawIndexed($list, $pipeline, $handles[$index], 720, 420,
            $vertexBuffer, $geometry.VertexStride, $indexBuffer, $geometry.IndexCount,
            $depth.Handle, $geometry.IndexFormat, $camera.ViewProjection)
        $gpu.Transition($list, $buffers[$index], 4, 0)
        $null = $gpu.CloseCommandList($list)
        $gpu.ExecuteCommandLists($queue, @($list))
        $null = $dxgi.Present($swapChain, 1, 0)
        $value = [uint64]($frame + 1)
        $null = $gpu.Signal($queue, $fence, $value)
        $null = $gpu.Wait($fence, $value, 5000)
    }
    if ($ScreenshotPath) {
        $native = & (Join-Path $root 'Native.ps1')
        [void][Reflection.Assembly]::Load('System.Drawing.Common')
        $bitmap = [Drawing.Bitmap]::new(736, 459)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $print = $native.GetExportCall('user32.dll','PrintWindow',([bool]),[Type[]]@([IntPtr],[IntPtr],[uint32]))
            $dc = $graphics.GetHdc()
            try { if (-not $print.DynamicInvoke($window.Hwnd,$dc,[uint32]2)) { throw 'PrintWindow failed.' } }
            finally { $graphics.ReleaseHdc($dc) }
            $bitmap.Save([IO.Path]::GetFullPath($ScreenshotPath), [Drawing.Imaging.ImageFormat]::Png)
        }
        finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
    [PSCustomObject]@{ Scene="QuickPS $Shape"; Vertices=$geometry.VertexCount; Indices=$geometry.IndexCount; Indexed=$true; Presented=$true; Fence=$gpu.GetCompletedValue($fence) } | Format-List
    $until = if ($Seconds -gt 0) { [DateTime]::UtcNow.AddSeconds($Seconds) } else { [DateTime]::MaxValue }
    while ($window.Alive -and [DateTime]::UtcNow -lt $until) { $null=$window.Pump(); [Threading.Thread]::Sleep(8) }
}
finally {
    if ($native) { $native.Dispose() }
    if ($shader) { $shader.Dispose() }
    if ($gpu) { $gpu.Dispose() }
    if ($dxgi) { $dxgi.Dispose() }
    if ($window) { $window.Dispose() }
}
