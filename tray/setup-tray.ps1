# Enable/disable/inspect auto-start of the a2a tray icon on Windows login.
# Creates or removes a hidden-launch shortcut in the user's Startup folder.
#   powershell -ExecutionPolicy Bypass -File setup-tray.ps1 enable
#   powershell -ExecutionPolicy Bypass -File setup-tray.ps1 disable
#   powershell -ExecutionPolicy Bypass -File setup-tray.ps1 status

param([ValidateSet('enable', 'disable', 'status')][string]$Action = 'status')

$trayScript = Join-Path $PSScriptRoot "a2a-tray.ps1"
$startup = [Environment]::GetFolderPath('Startup')
$lnk = Join-Path $startup "a2a-tray.lnk"

switch ($Action) {
    'enable' {
        $ps = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
        $sh = New-Object -ComObject WScript.Shell
        $s = $sh.CreateShortcut($lnk)
        $s.TargetPath = $ps
        $s.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$trayScript`""
        $s.WorkingDirectory = $PSScriptRoot
        $s.WindowStyle = 7   # minimised, no console window
        $s.Description = "a2a daemon tray indicator"
        $s.Save()
        Write-Host "Auto-start enabled: $lnk"
    }
    'disable' {
        if (Test-Path $lnk) { Remove-Item $lnk; Write-Host "Auto-start disabled (removed $lnk)" }
        else { Write-Host "Auto-start was not enabled." }
    }
    'status' {
        if (Test-Path $lnk) { Write-Host "Auto-start: ENABLED ($lnk)" }
        else { Write-Host "Auto-start: disabled" }
    }
}
