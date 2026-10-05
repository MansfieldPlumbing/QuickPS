[CmdletBinding()]
param([ValidateSet('Mica','Acrylic','MicaAlt')][string]$Material='Mica',[switch]$Verify)
$ErrorActionPreference='Stop'
$theme=& (Join-Path $PSScriptRoot 'Read-Data.ps1') -Path (Join-Path $PSScriptRoot 'Window.theme.ps1')
$ui=& (Join-Path $PSScriptRoot '..\src\Win32.Windows.ps1') -Theme $theme
try {
    $window=$ui.CreateWindow("QuickPS - $Material",840,480,$Material)
    $ui.Root=$window
    $x=24
    foreach($name in @('Mica','Acrylic','MicaAlt')){
        $selected=$name
        $change={param($facade,$notification) if($notification-eq0){$facade.SetBackdrop($window,$selected)}}.GetNewClosure()
        $null=$ui.AddControl($window,'BUTTON',$name,$x,24,180,44,[uint32]0,$change)
        $x+=192
    }
    $icons=@('Application','Information','Warning','Error')
    $iconState=@{Index=0;Button=[IntPtr]::Zero}
    $ui.SetIcon($window,$icons[0])
    $cycleIcon={
        param($facade,$notification)
        if($notification-ne0){return}
        $iconState.Index=($iconState.Index+1)%$icons.Count
        $facade.SetIcon($window,$icons[$iconState.Index])
        $facade.SetText($iconState.Button,"Icon: $($icons[$iconState.Index])")
    }.GetNewClosure()
    $iconState.Button=$ui.AddControl($window,'BUTTON','Icon: Application',$x,24,180,44,[uint32]0,$cycleIcon)
    if($Verify){
        $value=$ui.Native.Allocate(4)
        try{
            foreach($pair in @(@('Mica',2),@('Acrylic',3),@('MicaAlt',4))){
                $ui.SetBackdrop($window,$pair[0])
                $hr=$ui.Api.DwmGetWindowAttribute.Invoke($window,[uint32]38,$value,[uint32]4)
                if($hr-lt0 -or [Runtime.InteropServices.Marshal]::ReadInt32($value)-ne$pair[1]){throw "Backdrop verification failed: $($pair[0])"}
            }
            foreach($iconName in $icons){$ui.SetIcon($window,$iconName)}
            for($step=0;$step-lt5;$step++){& $cycleIcon $ui 0}
            if($iconState.Index-ne1){throw 'Icon cycle did not wrap.'}
            'PASS: three backdrop attributes, four small/large icons, and icon cycle wrap.'
        }finally{$ui.Native.Free($value)}
    }else{$ui.Show($window);$ui.Run()}
}finally{$ui.Dispose()}
