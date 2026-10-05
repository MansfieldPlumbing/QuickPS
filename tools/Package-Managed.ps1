[CmdletBinding()]
param([string]$AssemblyDirectory=(Join-Path $PSScriptRoot '..\build\managed'),[string]$OutputPath=(Join-Path $PSScriptRoot '..\build\QuickPS.Windows.zip'))
$ErrorActionPreference='Stop'
$assembly=Join-Path $AssemblyDirectory 'QuickPS.Windows.dll'
if(-not (Test-Path -LiteralPath $assembly)){throw 'Build the managed capability assembly first.'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stage=Join-Path $root ('build\package-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory((Join-Path $stage 'lib'))
try {
    Copy-Item -LiteralPath $assembly -Destination (Join-Path $stage 'lib\QuickPS.Windows.dll')
    foreach($directory in @('src','gallery')){Copy-Item -LiteralPath (Join-Path $root $directory) -Destination $stage -Recurse}
    Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination $stage
    $manifest=@{SchemaVersion=1;Platform='Windows x64';Assembly='lib/QuickPS.Windows.dll';SHA256=(Get-FileHash $assembly).Hash;CompilerCommit='26fe7a864b19e70cfd6937ab062335a05fac3232'}
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'manifest.json')
    if(Test-Path -LiteralPath $OutputPath){throw 'Package destination exists; choose a new path to preserve the original.'}
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $OutputPath
    if(-not (Test-Path -LiteralPath $OutputPath)){throw 'Package output missing.'}
    'PASS: managed DLL and PowerShell consumers packaged; generated output remains outside version control.'
}finally{
    if(-not $stage.StartsWith((Join-Path $root 'build\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected package staging path.'}
    Remove-Item -LiteralPath $stage -Recurse -Force
}
