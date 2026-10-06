[CmdletBinding()]
param([string]$CompilerRoot=(Join-Path $PSScriptRoot '..\build\upstream\pslowering'),[string]$OutputDirectory=(Join-Path $PSScriptRoot '..\build\managed'))
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
# Each src/managed/<Name>.ps1 compiles to its own QuickPS.<Name>.dll: PSLowering
# compiles one source file per assembly and the parts do not reference each other.
$sources=@(Get-ChildItem -LiteralPath (Join-Path $root 'src\managed') -File -Filter '*.ps1' | Sort-Object Name)
if(-not $sources.Count){throw 'No managed sources found.'}
foreach($source in $sources){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($source.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "$($source.Name): $($errors[0].Message)"}
    # The pinned tool's verified subset for this build uses static conversions and
    # byte-layout GUID constants. Do not admit unsupported value-receiver helpers.
    $unsupported=@($ast.FindAll({param($node)
        $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
        -not $node.Static -and $node.Member.Extent.Text -in @('ToString','ToByteArray')
    },$true))
    if($unsupported.Count){throw "$($source.Name): value-receiver conversion requires a separately verified compiler revision."}
}
Import-Module (Join-Path $CompilerRoot 'src\Dev.MansfieldPlumbing.PowerShell.Lowering.psd1') -Force
$null=[IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory))
$assemblies=foreach($source in $sources){
    $output=Join-Path $OutputDirectory ('QuickPS.'+$source.BaseName+'.dll')
    $classes=@([Management.Automation.Language.Parser]::ParseFile($source.FullName,[ref]$null,[ref]$null).FindAll({param($node) $node -is [Management.Automation.Language.TypeDefinitionAst]},$false))
    Export-LoweredAssembly -SourcePath $source.FullName -ClassName $classes[0].Name -OutputPath $output -Deterministic | Out-Null
    if(-not (Test-Path -LiteralPath $output)){throw "Managed output missing: $output"}
    [ordered]@{Assembly=[IO.Path]::GetFileName($output);Source='src/managed/'+$source.Name;SourceSha256=(Get-FileHash -LiteralPath $source.FullName).Hash;AssemblySha256=(Get-FileHash -LiteralPath $output).Hash}
}
$manifest=[ordered]@{CompilerCommit='26fe7a864b19e70cfd6937ab062335a05fac3232';PowerShell=$PSVersionTable.PSVersion.ToString();Runtime=[Environment]::Version.ToString();Assemblies=@($assemblies)}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'build-manifest.json')
"PASS: $(@($assemblies).Count) PowerShell-authored assemblies built."
