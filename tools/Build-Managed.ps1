[CmdletBinding()]
param([string]$CompilerRoot=(Join-Path $PSScriptRoot '..\build\upstream\pslowering'),[string]$OutputDirectory=(Join-Path $PSScriptRoot '..\build\managed'))
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$source=Join-Path $root 'src\managed\Windows.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
# The pinned tool's verified subset for this build uses static conversions and
# byte-layout GUID constants. Do not admit unsupported value-receiver helpers.
$unsupported=@($ast.FindAll({param($node)
    $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
    -not $node.Static -and $node.Member.Extent.Text -in @('ToString','ToByteArray')
},$true))
if($unsupported.Count){throw 'Value-receiver conversion requires a separately verified compiler revision.'}
Import-Module (Join-Path $CompilerRoot 'src\Dev.MansfieldPlumbing.PowerShell.Lowering.psd1') -Force
$null=[IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory))
$output=Join-Path $OutputDirectory 'QuickPS.Windows.dll'
Export-LoweredAssembly -SourcePath $source -ClassName QuickPSCapture -OutputPath $output -Deterministic | Out-Null
if(-not (Test-Path -LiteralPath $output)){throw 'Managed output missing.'}
$manifest=@{CompilerCommit='26fe7a864b19e70cfd6937ab062335a05fac3232';SourceSha256=(Get-FileHash $source).Hash;AssemblySha256=(Get-FileHash $output).Hash;PowerShell=$PSVersionTable.PSVersion.ToString();Runtime=[Environment]::Version.ToString()}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'build-manifest.json')
'PASS: PowerShell-authored Windows capability assembly built.'
