[CmdletBinding()]
param([string]$OutputPath=(Join-Path $PSScriptRoot '..\build\standalone\Backdrop.ps1'),[switch]$Check)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$facade=[IO.File]::ReadAllText((Join-Path $root 'src\Win32.Windows.ps1'))
$theme=[IO.File]::ReadAllText((Join-Path $root 'gallery\Window.theme.ps1'))
$applet=[IO.File]::ReadAllText((Join-Path $root 'gallery\Backdrop.ps1'))
$applet=$applet.Replace("`$theme=& (Join-Path `$PSScriptRoot 'Read-Data.ps1') -Path (Join-Path `$PSScriptRoot 'Window.theme.ps1')","`$theme=& {`n$theme`n}")
$binding="`$ui=& (Join-Path `$PSScriptRoot '..\src\Win32.Windows.ps1') -Theme `$theme"
if(-not $applet.Contains($binding)){throw 'Canonical applet binding changed; update generation deliberately.'}
$generated=$applet.Replace($binding,"`$ui=& {`n$facade`n} -Theme `$theme").Replace("`r`n","`n")
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseInput($generated,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
if($Check){
    if(-not (Test-Path -LiteralPath $OutputPath) -or [IO.File]::ReadAllText($OutputPath) -cne $generated){throw 'Standalone distribution drift detected.'}
}else{
    $null=[IO.Directory]::CreateDirectory((Split-Path ([IO.Path]::GetFullPath($OutputPath))))
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),$generated,[Text.UTF8Encoding]::new($false))
}
'PASS: standalone backdrop matches canonical PowerShell sources.'
