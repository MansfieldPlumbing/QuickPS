[CmdletBinding()]
param(
    [string] $Application,
    [string[]] $Source = @(),
    [ValidateSet('SourceBundle','Assembly','WindowsExecutable')]
    [string] $OutputKind = 'Assembly',
    [string] $OutputPath,
    [string] $ClassName,
    [string] $EntryPoint,
    [string] $CompilerArchive = (Join-Path $PSScriptRoot '../build/upstream/pslowering/source.tar'),
    [switch] $Help
)
$ErrorActionPreference = 'Stop'
if ($Help -or -not $Application) {
    @'
Build-Appliance.ps1 -Application <typed PS1> -Source <explicit PS1 paths>
  -OutputKind Assembly -OutputPath <DLL> [-ClassName <type>] [-EntryPoint <method>]
  -OutputKind SourceBundle -OutputPath <standalone PS1> -ClassName <type> -EntryPoint <method>

Select declarations explicitly; several files compile into one assembly.
SourceBundle carries source and the verified compiler archive and lowers at launch.
Today's compiler adapter stages files and loads the derived assembly by path.
WindowsExecutable awaits the pinned minimal static RC1 runtime/startup asset.
Existing outputs are preserved: choose a new output path to rebuild.
'@
    return
}
if ($PSVersionTable.PSVersion.ToString() -ne '7.7.0-preview.5' -or
    [Runtime.InteropServices.RuntimeInformation]::FrameworkDescription -cne '.NET 11.0.0-rc.1.26425.128') {
    throw 'Build requires PowerShell 7.7.0-preview.5 on .NET 11.0.0-rc.1.26425.128.'
}
if ($OutputKind -eq 'WindowsExecutable') {
    throw 'WindowsExecutable is not implemented: the verified minimal static RC1 runtime asset and startup/payload contract are not yet available.'
}
if (-not $OutputPath) { throw 'Specify -OutputPath. No artifact is written by default.' }
if ($OutputKind -eq 'SourceBundle' -and (-not $EntryPoint -or -not $ClassName)) {
    throw 'SourceBundle requires an explicit -ClassName and static zero-argument -EntryPoint.'
}
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$prefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Write appliance artifacts inside this repository, normally under build/.'
}
if ((Test-Path -LiteralPath $output) -or (Test-Path -LiteralPath ($output+'.provenance.json'))) { throw 'Output or receipt already exists; it has been preserved.' }
$extension = if ($OutputKind -eq 'Assembly') { '.dll' } else { '.ps1' }
if ([IO.Path]::GetExtension($output) -cne $extension) { throw "Output must use $extension." }
$paths = @($Source) + @($Application)
$seenPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$seenTypes = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$units = [Collections.Generic.List[string]]::new()
$receipts = [Collections.Generic.List[object]]::new()
foreach ($selection in $paths) {
    $path = [IO.Path]::GetFullPath($selection)
    if (-not $path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Selected source must belong to this repository.'
    }
    if (-not $seenPaths.Add($path)) { throw 'Source selection contains the same file twice.' }
    if ([IO.Path]::GetExtension($path) -ine '.ps1') { throw 'Select PS1 source files.' }
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    # A peer class can be unresolved until the explicit source set is composed.
    $syntaxErrors = @($errors | Where-Object ErrorId -ne 'TypeNotFound')
    if ($syntaxErrors.Count) { throw "$([IO.Path]::GetFileName($path)):$($syntaxErrors[0].Extent.StartLineNumber): $($syntaxErrors[0].Message)" }
    if ($ast.ParamBlock -or $ast.BeginBlock -or $ast.ProcessBlock -or $ast.CleanBlock -or $ast.DynamicParamBlock -or $ast.UsingStatements.Count -or $ast.EndBlock.Traps.Count) {
        throw 'Current typed composition does not admit top-level parameters or execution blocks.'
    }
    $relative = [IO.Path]::GetRelativePath($root,$path).Replace('\','/')
    $classes = 0
    foreach ($statement in $ast.EndBlock.Statements) {
        if ($statement -is [Management.Automation.Language.TypeDefinitionAst] -and $statement.IsClass) {
            if (-not $seenTypes.Add($statement.Name)) { throw "Duplicate type: $($statement.Name)." }
            $units.Add("# Source: ${relative}:$($statement.Extent.StartLineNumber)`n" + $statement.Extent.Text)
            $classes++
        } elseif ($statement.Extent.Text -match '^if\s*\(\s*\$MyInvocation\.InvocationName\s+-eq\s*''\.''\s*\)\s*\{\s*throw\s+''[^'']*''\s*\}\s*$') {
            # The known source-invocation guard is staging policy, not runtime logic.
        } else {
            throw "${relative}:$($statement.Extent.StartLineNumber): rewrite/admit this top-level runtime construct before lowering; nothing was omitted."
        }
    }
    if (-not $classes) { throw "${relative}: no typed classes selected." }
    $receipts.Add([ordered]@{Source=$relative;Sha256=(Get-FileHash -LiteralPath $path).Hash})
}
if ($ClassName -and -not $seenTypes.Contains($ClassName)) { throw 'Selected entry class is absent.' }
$compilationUnit = ($units -join "`n`n") + "`n"
$tokens=$null; $errors=$null
[void][Management.Automation.Language.Parser]::ParseInput($compilationUnit,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw "Composed unit:$($errors[0].Extent.StartLineNumber): $($errors[0].Message)" }
$digest = '7005315D32BD1A786EE601B2A57A847581E85A764B7CE9815C19146906E952A5'
$archive = [IO.Path]::GetFullPath($CompilerArchive)
if (-not $archive.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Compiler inputs must belong to this repository cache.' }
if ((Get-FileHash -LiteralPath $archive).Hash -cne $digest) { throw 'Pinned compiler archive integrity failed.' }
$workspace = Join-Path $root ('build/appliance-staging/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($workspace)
$sourcePath = Join-Path $workspace 'Runtime.ps1'
[IO.File]::WriteAllText($sourcePath,$compilationUnit,[Text.UTF8Encoding]::new($false))
$compiler = Join-Path $workspace 'compiler'
[void][IO.Directory]::CreateDirectory($compiler)
& tar -xf $archive -C $compiler
if ($LASTEXITCODE) { throw 'Verified compiler archive extraction failed.' }
Import-Module (Join-Path $compiler 'src/Dev.MansfieldPlumbing.PowerShell.Lowering.psd1') -Force
$assemblyPath = Join-Path $workspace ([IO.Path]::GetFileNameWithoutExtension($output) + '.dll')
$arguments = @{SourcePath=$sourcePath;OutputPath=$assemblyPath;Deterministic=$true}
if ($ClassName) { $arguments.ClassName = $ClassName }
if ($EntryPoint) { $arguments.EntryPoint = $EntryPoint }
Export-LoweredAssembly @arguments | Out-Null
if ($OutputKind -eq 'SourceBundle') {
    $context = [Runtime.Loader.AssemblyLoadContext]::new('QuickPS-build-admission',$true)
    try {
        $compiled = $context.LoadFromAssemblyPath($assemblyPath)
        $method = $compiled.GetType($ClassName,$true).GetMethod($EntryPoint,[Reflection.BindingFlags]'Public,Static')
        if ($null -eq $method -or $method.GetParameters().Count -ne 0 -or $method.ReturnType -notin @([int],[void])) {
            throw 'Standalone launch requires a public static zero-argument Int32/Void entry.'
        }
    } finally { $context.Unload() }
    $template = @'
[CmdletBinding()]
param([switch]$Help)
$ErrorActionPreference = 'Stop'
if ($Help) { 'Self-contained appliance source with launch-time lowering. Requires PowerShell 7.7.0-preview.5 / .NET 11 RC1. Current adapter materializes verified compiler/source/output files in a temporary directory.'; return }
if ($PSVersionTable.PSVersion.ToString() -ne '7.7.0-preview.5' -or [Runtime.InteropServices.RuntimeInformation]::FrameworkDescription -cne '.NET 11.0.0-rc.1.26425.128') { throw 'Pinned PowerShell/runtime required.' }
$sourceText = '__SOURCE__'
$compilerArchive = '__ARCHIVE__'
$archiveDigest = '__DIGEST__'
$className = '__CLASS__'
$entryName = '__ENTRY__'
$directory = Join-Path ([IO.Path]::GetTempPath()) ('QuickPS-stage-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$archivePath = Join-Path $directory 'compiler.tar'
[IO.File]::WriteAllBytes($archivePath,[Convert]::FromBase64String($compilerArchive))
if ((Get-FileHash -LiteralPath $archivePath).Hash -cne $archiveDigest) { throw 'Compiler archive integrity failed.' }
$compilerPath = Join-Path $directory 'compiler'
[void][IO.Directory]::CreateDirectory($compilerPath)
& tar -xf $archivePath -C $compilerPath
if ($LASTEXITCODE) { throw 'Verified compiler extraction failed.' }
Import-Module (Join-Path $compilerPath 'src/Dev.MansfieldPlumbing.PowerShell.Lowering.psd1') -Force
$runtimeSource = Join-Path $directory 'Runtime.ps1'
[IO.File]::WriteAllText($runtimeSource,$sourceText,[Text.UTF8Encoding]::new($false))
$imagePath = Join-Path $directory 'Appliance.dll'
Export-LoweredAssembly -SourcePath $runtimeSource -ClassName $className -OutputPath $imagePath -EntryPoint $entryName -Deterministic | Out-Null
$context = [Runtime.Loader.AssemblyLoadContext]::new('QuickPS-appliance',$true)
try {
    $assembly = $context.LoadFromAssemblyPath($imagePath)
    $entry = $assembly.GetType($className,$true).GetMethod($entryName,[Reflection.BindingFlags]'Public,Static')
    if ($null -eq $entry -or $entry.GetParameters().Count -ne 0 -or $entry.ReturnType -notin @([int],[void])) { throw 'Invalid appliance entry.' }
    $result = $entry.Invoke($null,@())
    if ($entry.ReturnType -eq [int]) { exit ([int]$result) }
} finally { $context.Unload() }
'@
    $payload = @{SOURCE=$compilationUnit.Replace("'","''");ARCHIVE=[Convert]::ToBase64String([IO.File]::ReadAllBytes($archive));DIGEST=$digest;CLASS=$ClassName.Replace("'","''");ENTRY=$EntryPoint.Replace("'","''")}
    $artifact = [regex]::Replace($template,'__(SOURCE|ARCHIVE|DIGEST|CLASS|ENTRY)__',{param($match) $payload[$match.Groups[1].Value]})
    $license = [IO.File]::ReadAllText((Join-Path $root 'LICENSE')).Replace("`r`n","`n")
    $artifact = (($license.Split("`n") | ForEach-Object { '# ' + $_ }) -join "`n") + "`n`n" + $artifact
    $tokens=$null; $errors=$null
    [void][Management.Automation.Language.Parser]::ParseInput($artifact,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw 'Generated source failed syntax validation.' }
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output))
if ($OutputKind -eq 'Assembly') { [IO.File]::Copy($assemblyPath,$output,$false) }
else { [IO.File]::WriteAllText($output,$artifact,[Text.UTF8Encoding]::new($false)) }
$receipt = [ordered]@{OutputKind=$OutputKind;SourceSet=@($receipts);CompilerCommit='26fe7a864b19e70cfd6937ab062335a05fac3232';CompilerArchiveSha256=$digest;PowerShell=$PSVersionTable.PSVersion.ToString();Runtime=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription;ArtifactSha256=(Get-FileHash -LiteralPath $output).Hash}
[IO.File]::WriteAllText(($output+'.provenance.json'),($receipt | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
[PSCustomObject]@{OutputKind=$OutputKind;SourceCount=$paths.Count;TypeCount=$seenTypes.Count;Bytes=(Get-Item -LiteralPath $output).Length}
