[CmdletBinding()]
param([string]$AssemblyDirectory=(Join-Path $PSScriptRoot '..\build\managed'),[string]$OutputPath=(Join-Path $PSScriptRoot '..\build\QuickPS.zip'))
$ErrorActionPreference='Stop'
$buildManifest=Join-Path $AssemblyDirectory 'build-manifest.json'
if(-not (Test-Path -LiteralPath $buildManifest)){throw 'Build the managed assemblies first.'}
$built=Get-Content -LiteralPath $buildManifest -Raw | ConvertFrom-Json
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stage=Join-Path $root ('build\package-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory((Join-Path $stage 'lib'))
try {
    $entries=foreach($item in $built.Assemblies){
        $assembly=Join-Path $AssemblyDirectory $item.Assembly
        if((Get-FileHash -LiteralPath $assembly).Hash -ne $item.AssemblySha256){throw "$($item.Assembly) differs from its build manifest."}
        Copy-Item -LiteralPath $assembly -Destination (Join-Path $stage ('lib\'+$item.Assembly))
        [ordered]@{Assembly='lib/'+$item.Assembly;SHA256=$item.AssemblySha256;Source=$item.Source}
    }
    foreach($directory in @('src','gallery')){Copy-Item -LiteralPath (Join-Path $root $directory) -Destination $stage -Recurse}
    Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination $stage
    $manifest=[ordered]@{SchemaVersion=2;Platform='Windows x64';CompilerCommit=$built.CompilerCommit;Runtime=$built.Runtime;Assemblies=@($entries)}
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stage 'manifest.json')
    if(Test-Path -LiteralPath $OutputPath){throw 'Package destination exists; choose a new path to preserve the original.'}
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $OutputPath
    if(-not (Test-Path -LiteralPath $OutputPath)){throw 'Package output missing.'}
    "PASS: $(@($entries).Count) managed DLLs and PowerShell consumers packaged; generated output remains outside version control."
}finally{
    if(-not $stage.StartsWith((Join-Path $root 'build\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected package staging path.'}
    Remove-Item -LiteralPath $stage -Recurse -Force
}
