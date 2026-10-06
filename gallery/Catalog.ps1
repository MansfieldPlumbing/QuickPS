@{
    SchemaVersion = 1
    Entries = @(
        @{
            Id = 'window'
            Title = 'Native window lifecycle'
            Description = 'Create, show, close, dispatch, and dispose a Win32 HWND without a managed UI framework.'
            Script = 'Window.ps1'
            Launcher = 'Window.cmd'
            Source = '../src/Window.Windows.ps1'
            Verification = 'Window.ps1'
            VerificationArguments = @('-Verify')
            Platform = 'Windows x64; PowerShell 7'
            Status = 'Native lifecycle checks available; visual acceptance separate'
        }
        @{
            Id = 'video-in'
            Title = 'Video capture input viewer'
            Description = 'Show a camera or USB HDMI capture input with its matching audio; Media Foundation renders natively and the script waits only on window messages.'
            Script = 'VideoIn.ps1'
            Launcher = 'VideoIn.cmd'
            Source = '../src/MediaSession.Windows.ps1'
            Verification = 'VideoIn.ps1'
            VerificationArguments = @('-Verify')
            Platform = 'Windows x64; PowerShell 7; Media Foundation; QuickPS.MediaSessionEvents.dll'
            Status = 'Renderer frame statistics checked with an attached input; visual acceptance separate'
        }
        @{
            Id = 'typography'
            Title = 'Direct2D drawing and DirectWrite text'
            Description = 'Render colored geometry and Unicode text in a native window.'
            Script = 'Typography.ps1'
            Launcher = 'Typography.cmd'
            Source = '../src/D2D.Windows.ps1'
            Verification = 'Typography.ps1'
            VerificationArguments = @('-Verify')
            Platform = 'Windows x64; PowerShell 7; Direct2D and DirectWrite'
            Status = 'Native creation and draw checks available; visual acceptance separate'
        }
        @{
            Id = 'backdrop'
            Title = 'System backdrops and window icons'
            Description = 'Mica, Acrylic, MicaAlt, and four system icons.'
            Script = 'Backdrop.ps1'
            Launcher = 'Backdrop.cmd'
            Source = '../src/Win32.Windows.ps1'
            Verification = 'Backdrop.ps1'
            VerificationArguments = @('-Verify')
            Platform = 'Windows x64; PowerShell 7; backdrops require build 22621+'
            Status = 'Native checks available; visual acceptance separate'
        }
        @{
            Id = 'window-controls'
            Title = 'Win32 windows and controls'
            Description = 'Compose native windows, controls, theme data and a trusted Files descriptor.'
            Script = 'WindowControls.ps1'
            Launcher = 'WindowControls.cmd'
            Source = '../src/Win32.Windows.ps1'
            Verification = 'WindowControls.ps1'
            VerificationArguments = @('-Verify')
            Platform = 'Windows x64; PowerShell 7'
            Status = 'Window composition proof; visual acceptance separate'
        }
        @{
            Id = 'sound-recorder'
            Title = 'Native sound recorder'
            Description = 'Portrait recorder with custom waveform, elapsed time and Mic/Apps/Both source choices.'
            Script = 'SoundRecorder.ps1'
            Launcher = 'SoundRecorder.cmd'
            Source = 'SoundRecorder.ps1'
            Verification = 'SoundRecorder.ps1'
            VerificationArguments = @('-Verify')
            Platform = 'Windows x64; PowerShell 7; WASAPI and DWM Mica Alt'
            Status = 'Historical presentation restored; window proof available; live audio and runtime modernization pending'
        }
        @{
            Id = 'window-capture'
            Title = 'Window enumeration and screen capture'
            Description = 'Enumerate windows and capture a requested HWND to BMP through GDI and PrintWindow.'
            Script = 'WindowCapture.ps1'
            Launcher = 'WindowCapture.cmd'
            Source = '../src/WindowCapture.Windows.ps1'
            Verification = 'WindowCapture.ps1'
            VerificationArguments = @('-Verify')
            Platform = 'Windows x64; PowerShell 7; Win32 GDI and PrintWindow'
            Status = 'Task-owned synthetic window verification; visual acceptance separate'
        }
    )
}
