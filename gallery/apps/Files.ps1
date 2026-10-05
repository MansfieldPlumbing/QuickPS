@{
    ApiVersion=2
    Id='files'
    Title='Files'
    Create={
        param($ui)
        $window=$ui.CreateWindow('Files',800,620)
        $model=@{Path=[Environment]::GetFolderPath('UserProfile'); Window=$window; Entries=@(); Label=[IntPtr]::Zero; List=[IntPtr]::Zero}
        $model.Label=$ui.AddControl($window,'STATIC',$model.Path,20,16,740,28,[uint32]0,$null)
        $refresh={
            param($hostFacade)
            $model.Entries=@(Get-ChildItem -LiteralPath $model.Path -ErrorAction Stop | Sort-Object @{Expression='PSIsContainer';Descending=$true},Name)
            $labels=@(foreach($item in $model.Entries){if($item.PSIsContainer){'[Folder] '+$item.Name}else{$item.Name}})
            $hostFacade.SetItems($model.List,[string[]]$labels)
            $hostFacade.SetText($model.Label,$model.Path)
        }.GetNewClosure()
        $open={
            param($hostFacade,$notification)
            if($notification-ne2){return}
            $selected=$hostFacade.SelectedIndex($model.List)
            if($selected-ge0 -and $selected-lt$model.Entries.Count -and $model.Entries[$selected].PSIsContainer){
                $model.Path=$model.Entries[$selected].FullName
                & $refresh $hostFacade
            }
        }.GetNewClosure()
        $model.List=$ui.AddControl($window,'LISTBOX','',20,96,740,460,[uint32]0x00A00101,$open)
        $up={param($hostFacade,$notification)
            if($notification-ne0){return}
            $parent=[IO.Directory]::GetParent($model.Path)
            if($parent){$model.Path=$parent.FullName;& $refresh $hostFacade}
        }.GetNewClosure()
        $null=$ui.AddControl($window,'BUTTON','Up',20,50,88,32,[uint32]0,$up)
        & $refresh $ui
        return $window
    }
}
