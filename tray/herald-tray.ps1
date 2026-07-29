# herald tray icon - shows daemon state in the Windows notification area.
#   green  = running (idle)   blue up-arrow = sending   purple down-arrow = receiving
#   grey X = daemon down / heartbeat stale
# Reads ~/.herald/status.json and ~/.herald/activity/{send,recv} from WSL over \\wsl$.
# Run hidden:  powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File herald-tray.ps1

param(
    [string]$HeraldDir,                     # Windows path to the WSL ~/.herald dir; auto-detected if omitted
    [string]$DaemonCmd = "if systemctl --user cat herald-daemon.service >/dev/null 2>&1; then systemctl --user restart herald-daemon; else pkill -f '[h]erald.py daemon' 2>/dev/null; setsid `"`$HOME/.local/bin/herald`" daemon >/dev/null 2>&1 </dev/null & disown; fi",  # systemd if present, else the PATH wrapper - machine-agnostic
    [int]$HeartbeatTimeout = 15,         # seconds without a heartbeat => daemon considered down
    [double]$ActiveWindow = 4.0          # seconds an arrow lingers after a send/recv event
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$iconDir = Join-Path $PSScriptRoot "icons"

function Get-BarTheme {
    # SystemUsesLightTheme = 1 => light taskbar, else dark. Default dark.
    try {
        $v = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
             -Name SystemUsesLightTheme -ErrorAction Stop
        if ($v -eq 1) { return 'light' }
    } catch {}
    return 'dark'
}

# Resolve the WSL ~/.herald directory as a Windows path. At login the tray starts
# before WSL is warm, so this can return nothing; it is retried lazily in
# Poll-State rather than resolved only once - otherwise a cold boot would pin
# the icon to 'offline' forever even after WSL and the daemon come up.
function Resolve-HeraldDir {
    try {
        $prev = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $d = (& wsl.exe -e bash -lc "wslpath -w ~/.herald" 2>$null | Select-Object -First 1)
        [Console]::OutputEncoding = $prev
        if ($d) { return $d.Trim() }
    } catch {}
    return $null
}

function Set-HeraldPaths($dir) {
    $script:heraldDir     = $dir
    $script:statusPath = if ($dir) { Join-Path $dir "status.json" } else { $null }
    $script:sendMarker = if ($dir) { Join-Path $dir "activity\send" } else { $null }
    $script:recvMarker = if ($dir) { Join-Path $dir "activity\recv" } else { $null }
}

$script:lastResolve = 0
if (-not $HeraldDir) { $HeraldDir = Resolve-HeraldDir }
Set-HeraldPaths $HeraldDir

$script:FrameCount = 8
$script:icons = @{ dark = @{}; light = @{} }
$script:frames = @{ dark = @{ send = @(); recv = @() }; light = @{ send = @(); recv = @() } }
foreach ($theme in 'dark', 'light') {
    foreach ($s in 'idle', 'send', 'recv', 'offline') {
        $script:icons[$theme][$s] = New-Object System.Drawing.Icon (Join-Path $iconDir "$theme\$s.ico")
    }
    foreach ($s in 'send', 'recv') {
        $script:frames[$theme][$s] = 0..($script:FrameCount - 1) | ForEach-Object {
            New-Object System.Drawing.Icon (Join-Path $iconDir "$theme\${s}_$_.ico")
        }
    }
}

$script:ni = New-Object System.Windows.Forms.NotifyIcon
$script:ni.Icon = $script:icons[(Get-BarTheme)]['offline']
$script:ni.Text = "herald: starting..."
$script:ni.Visible = $true

function Now-Unix { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0 }

function Read-Marker($path) {
    if ($path -and (Test-Path $path)) {
        try { return [double](Get-Content -Raw $path) } catch { return 0 }
    }
    return 0
}

$script:state = 'offline'

# Read status + activity markers and decide the current state + tooltip.
# Runs on a throttle (not every animation frame) to keep \\wsl$ reads light.
function Poll-State {
    $now = Now-Unix
    if (-not $script:heraldDir -and ($now - $script:lastResolve) -ge 5) {
        $script:lastResolve = $now
        Set-HeraldPaths (Resolve-HeraldDir)   # cold-boot self-heal: retry until WSL answers
    }
    $status = $null
    if ($script:statusPath -and (Test-Path $script:statusPath)) {
        try { $status = Get-Content -Raw $script:statusPath | ConvertFrom-Json } catch { $status = $null }
    }
    if (-not $status -or ($now - [double]$status.heartbeat) -gt $HeartbeatTimeout) {
        $script:state = 'offline'
        $script:ni.Text = "herald: daemon not running"
        return
    }
    $send = Read-Marker $script:sendMarker
    $recv = Read-Marker $script:recvMarker
    $script:state = 'idle'
    if (($now - $send) -lt $ActiveWindow -and $send -ge $recv) { $script:state = 'send' }
    elseif (($now - $recv) -lt $ActiveWindow) { $script:state = 'recv' }

    $verb = @{ idle = 'running'; send = 'sending'; recv = 'receiving' }[$script:state]
    $q = if ($status.queued) { " | $($status.queued) queued" } else { "" }
    $text = "herald v$($status.version): $verb - $($status.me) on $($status.listen)$q"
    if ($text.Length -gt 127) { $text = $text.Substring(0, 127) }
    $script:ni.Text = $text
}

# Fast tick: refresh state periodically, animate send/recv, stay static otherwise.
$script:tick = 0
$script:animIdx = 0
function Update-Tray {
    if ($script:tick % 6 -eq 0) { Poll-State }
    $script:tick++
    $set = $script:icons[(Get-BarTheme)]
    if ($script:state -eq 'send' -or $script:state -eq 'recv') {
        $frames = $script:frames[(Get-BarTheme)][$script:state]
        $script:ni.Icon = $frames[$script:animIdx % $script:FrameCount]
        $script:animIdx++
    }
    else {
        $script:animIdx = 0
        $script:ni.Icon = $set[$script:state]
    }
}

# Context menu: Status balloon, Restart daemon, Exit.
$menu = New-Object System.Windows.Forms.ContextMenuStrip

$miStatus = $menu.Items.Add("Show status")
$miStatus.add_Click({
    $t = $script:ni.Text
    $script:ni.ShowBalloonTip(3000, "herald", $t, [System.Windows.Forms.ToolTipIcon]::Info)
})

$miRestart = $menu.Items.Add("Restart daemon")
$miRestart.add_Click({
    try { Start-Process -WindowStyle Hidden wsl.exe -ArgumentList @('-e', 'bash', '-lc', $DaemonCmd) } catch {}
})

$miExit = $menu.Items.Add("Exit")
$miExit.add_Click({
    $script:timer.Stop()
    $script:ni.Visible = $false
    $script:ni.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

$script:ni.ContextMenuStrip = $menu
$script:ni.add_MouseDoubleClick({ $miStatus.PerformClick() })

$script:timer = New-Object System.Windows.Forms.Timer
$script:timer.Interval = 90
$script:timer.add_Tick({ Update-Tray })
Poll-State
Update-Tray
$script:timer.Start()

[System.Windows.Forms.Application]::Run((New-Object System.Windows.Forms.ApplicationContext))
