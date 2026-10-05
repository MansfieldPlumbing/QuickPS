[CmdletBinding()]
param(
    [string]$TitlePattern,
    [int]$Index = -1,
    [string]$OutputPath,
    [switch]$List,
    [switch]$Verify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$capturePrimitive = & (Join-Path $PSScriptRoot '..\src\WindowCapture.Windows.ps1')
try {
    if ($Verify) {
        $owned=& (Join-Path $PSScriptRoot '..\src\Window.Windows.ps1') -Width 320 -Height 240 -Title 'Synthetic capture verification'
        $tempPath=Join-Path ([IO.Path]::GetTempPath()) ('QuickPS-Capture-'+[Guid]::NewGuid().ToString('N')+'.bmp')
        try {
            $null=$owned.Show()
            $windows=@($capturePrimitive.GetWindows())
            if(-not ($windows | Where-Object Hwnd -EQ $owned.Hwnd)){throw 'Task-owned window missing from enumeration.'}
            $result=$capturePrimitive.CaptureWindow($owned.Hwnd,$tempPath)
            $bytes=[IO.File]::ReadAllBytes($tempPath)
            if($bytes.Length -ne $result.Bytes+54 -or $bytes[0] -ne 66 -or $bytes[1] -ne 77){throw 'Capture BMP size/signature differs.'}
            $null=$owned.Close();$null=$owned.Run()
        }finally{
            $owned.Dispose()
            if(Test-Path -LiteralPath $tempPath){Remove-Item -LiteralPath $tempPath -Force}
        }
        'PASS: enumeration and BMP capture of a task-owned synthetic window only.'
        return
    }

    $windows = @($capturePrimitive.GetWindows())
    if ($windows.Count -eq 0) {
        Write-Host "No visible application windows detected." -ForegroundColor Yellow
        return
    }

    if ($List) {
        Write-Host "`n=== Available Windows for Capture ===" -ForegroundColor Cyan
        for ($i = 0; $i -lt $windows.Count; $i++) {
            $w = $windows[$i]
            Write-Host ("[{0,2}] {1,-28} | {2,-40} | ({3}x{4})" -f $i, $w.ProcessName, $w.Title, $w.Width, $w.Height)
        }
        Write-Host ""
        return
    }

    $target = $null
    if ($Index -ge 0 -and $Index -lt $windows.Count) {
        $target = $windows[$Index]
    }
    elseif ($TitlePattern) {
        $target = $windows | Where-Object { $_.Title -like "*$TitlePattern*" } | Select-Object -First 1
    }
    else {
        Write-Host "`n=== Windows Available for Capture ===" -ForegroundColor Cyan
        for ($i = 0; $i -lt $windows.Count; $i++) {
            $w = $windows[$i]
            Write-Host ("[{0,2}] {1,-28} | {2,-40} | ({3}x{4})" -f $i, $w.ProcessName, $w.Title, $w.Width, $w.Height)
        }
        Write-Host ""
        $selection = Read-Host "Enter window number to capture (or Enter for [0])"
        if ([string]::IsNullOrWhiteSpace($selection)) {
            $target = $windows[0]
        }
        else {
            $idx = 0
            if ([int]::TryParse($selection, [ref]$idx) -and $idx -ge 0 -and $idx -lt $windows.Count) {
                $target = $windows[$idx]
            } else {
                throw "Invalid selection: $selection"
            }
        }
    }

    if (-not $target) {
        throw "Could not resolve a target window to capture."
    }

    $capturesDir = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::MyPictures)) 'Captures'
    if (-not (Test-Path -LiteralPath $capturesDir)) {
        [IO.Directory]::CreateDirectory($capturesDir) | Out-Null
    }

    if (-not $OutputPath) {
        $safeTitle = ($target.Title -replace '[\\/:*?"<>|]', '_').Trim()
        if ($safeTitle.Length -gt 40) { $safeTitle = $safeTitle.Substring(0, 40) }
        $fileName = 'Capture_{0}_{1}.bmp' -f $safeTitle, (Get-Date -Format 'yyyyMMdd_HHmmss')
        $OutputPath = Join-Path $capturesDir $fileName
    }

    Write-Host ("Capturing [{0}] `"{1}`"..." -f $target.Hwnd, $target.Title) -ForegroundColor Green
    $result = $capturePrimitive.CaptureWindow($target.Hwnd, $OutputPath)

    Write-Host ("Captured: {0}" -f $result.Path) -ForegroundColor Cyan
    Write-Host ("Dimensions: {0}x{1} ({2:N0} bytes)" -f $result.Width, $result.Height, $result.Bytes)

    return $result
}
finally {
    $capturePrimitive.Dispose()
}
