[CmdletBinding()]
param(
    [string[]]$AppScript=@((Join-Path $PSScriptRoot 'apps\Files.ps1')),
    [string]$ThemePath=(Join-Path $PSScriptRoot 'Window.theme.ps1'),
    [ValidateSet('Panel','Maximized')][string]$StartMode='Panel',
    [switch]$Verify
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Linear startup graph: Validate -> Bind -> Instantiate -> Hydrate -> Dispatch -> Dispose.
$apps=[ordered]@{}
foreach($path in $AppScript){
    $file=(Resolve-Path -LiteralPath $path -ErrorAction Stop).ProviderPath
    if([IO.Path]::GetExtension($file)-ne'.ps1'){throw 'App files must use the .ps1 extension.'}
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "App AST validation failed: $file"}
    $app=& $file
    if($app-isnot[hashtable]){throw 'App must return one descriptor hashtable.'}
    foreach($key in @('ApiVersion','Id','Title','Create')){if(-not$app.ContainsKey($key)){throw "Missing app field: $key"}}
    if($app.ApiVersion-ne2 -or $app.Id-notmatch'^[a-z][a-z0-9-]{0,63}$' -or $app.Create-isnot[scriptblock]){throw 'Invalid native app descriptor.'}
    if($apps.Contains($app.Id)){throw "Duplicate app: $($app.Id)"}
    $apps.Add($app.Id,$app)
}
$theme=& (Join-Path $PSScriptRoot 'Read-Data.ps1') -Path $ThemePath
$facade=& (Join-Path $PSScriptRoot '..\src\Win32.Windows.ps1') -Theme $theme
try {
    $rootWindow=$facade.CreateWindow('Native Windows and Controls',1100,740)
    $facade.Root=$rootWindow
    $session=@{Start=[IntPtr]::Zero; Apps=$apps; Instances=@{}; Mode=$StartMode}
    $null=$facade.AddControl($rootWindow,'STATIC','Native Windows and Controls',28,24,720,32,[uint32]0,$null)
    $null=$facade.AddControl($rootWindow,'STATIC','Native windows. Event-driven PowerShell apps.',28,62,720,24,[uint32]0,$null)
    $openStart={
        param($ui,$notification)
        if($notification-ne0){return}
        if($session.Start-ne[IntPtr]::Zero -and $ui.Api.IsWindow.Invoke($session.Start)){$ui.Activate($session.Start);return}
        $start=$ui.CreateWindow('Applications',640,560,'Acrylic')
        $session.Start=$start
        $null=$ui.AddControl($start,'STATIC','Apps',24,20,540,30,[uint32]0,$null)
        $index=0
        foreach($definition in $session.Apps.Values){
            $entry=$definition
            $activate={
                param($hostFacade,$code)
                if($code-ne0){return}
                $id=$entry.Id
                if($session.Instances.ContainsKey($id) -and $hostFacade.Api.IsWindow.Invoke($session.Instances[$id])){
                    $hostFacade.Activate($session.Instances[$id]);return
                }
                $window=& $entry.Create $hostFacade
                if($window-isnot[IntPtr] -or -not$hostFacade.Api.IsWindow.Invoke($window)){throw "App $id did not return a live window."}
                $session.Instances[$id]=$window
                $hostFacade.Show($window)
            }.GetNewClosure()
            $null=$ui.AddControl($start,'BUTTON',$entry.Title,(24+($index%3)*190),(66+[int][Math]::Floor($index/3)*88),178,76,[uint32]0,$activate)
            $index++
        }
        if($index-eq0){$null=$ui.AddControl($start,'STATIC','Load an app with -AppScript to add it here.',24,66,560,44,[uint32]0,$null)}
        $ui.Show($start,$(if($session.Mode-eq'Maximized'){3}else{5}))
    }.GetNewClosure()
    $startButton=$facade.AddControl($rootWindow,'BUTTON','Applications',28,112,140,42,[uint32]0,$openStart)
    if($Verify){
        $facade.Show($rootWindow,6)
        if(-not$facade.Api.IsIconic.Invoke($rootWindow)){throw 'Minimize verification failed.'}
        $facade.Show($rootWindow,3)
        if(-not$facade.Api.IsZoomed.Invoke($rootWindow)){throw 'Maximize verification failed.'}
        $facade.Show($rootWindow,9)
        if($facade.Api.IsIconic.Invoke($rootWindow) -or $facade.Api.IsZoomed.Invoke($rootWindow)){throw 'Restore verification failed.'}
        foreach($app in $apps.Values){
            $appWindow=& $app.Create $facade
            if($appWindow-isnot[IntPtr] -or -not$facade.IsAlive($appWindow)){throw "App creation failed: $($app.Id)"}
        }
        $observed=@{Count=0}
        $action={param($ui,$code) $observed.Count++}.GetNewClosure()
        $button=$facade.AddControl($rootWindow,'BUTTON','Verify',180,112,140,42,[uint32]0,$action)
        $id=$facade.NextId-1
        # WM_COMMAND enters the IL window procedure and is queued for event dispatch.
        [void]$facade.Api.SendMessageW.Invoke($rootWindow,[uint32]0x111,[IntPtr]$id,$button)
        [void]$facade.Api.SendMessageW.Invoke($rootWindow,[uint32]0x10,[IntPtr]::Zero,[IntPtr]::Zero)
        $facade.Run()
        if($observed.Count-ne1){throw 'Native command dispatch verification failed.'}
        'PASS: native creation, app loading, minimize/maximize/restore, IL command forwarding, event dispatch, and close.'
    } else {
        $facade.Show($rootWindow)
        if($StartMode-eq'Maximized'){& $openStart $facade 0}
        $facade.Run()
    }
} finally {$facade.Dispose()}
