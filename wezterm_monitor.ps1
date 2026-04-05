# wezterm_monitor.ps1 - Multi-project WezTerm SSH/tmux Monitor
# Auto-reconnect SSH + Auto-position windows on laptop's built-in screens
#
# Positioning strategy (workaround for WezTerm/winit DPI bug):
#   1. MoveWindow at Y=0 to set correct size (always works at top of screen)
#   2. SetWindowPos with SWP_NOSIZE to move to final Y (preserves height)
#   3. Iterative Y correction for DPI-scaled coordinates
#
# Usage: powershell -ExecutionPolicy Bypass -File wezterm_monitor.ps1 -Profile <name>
#   -Profile         : rbok | 42t (required unless -RepositionOnly)
#   -RepositionOnly  : just reposition existing windows
#   -ReconnectAll    : kill existing WezTerm and relaunch

param(
    [string]$Profile,
    [switch]$RepositionOnly,
    [switch]$ReconnectAll
)

Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class WinPos {
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int W, int H, bool repaint);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    public const uint SWP_NOSIZE   = 0x0001;
    public const uint SWP_NOZORDER = 0x0004;
}
"@

# --- SSH Config ---
$sshTarget = "194360-10166@gate.jpc.infomaniak.com"
$sshKey    = "~/.ssh/id_rsa"
$wezterm   = "C:\Program Files\WezTerm\wezterm-gui.exe"
$tag        = "[wez-monitor]"

# --- Detect laptop's built-in screens ---
$allScreens = [System.Windows.Forms.Screen]::AllScreens
$screenPad = $allScreens | Where-Object {
    $b = $_.Bounds; ($b.Width / [Math]::Max($b.Height, 1)) -gt 3.0
} | Select-Object -First 1

if ($screenPad) {
    $padX = $screenPad.Bounds.X
    $laptopMain = $allScreens | Where-Object {
        $_.Bounds.X -eq $padX -and $_.DeviceName -ne $screenPad.DeviceName
    } | Select-Object -First 1
    if ($laptopMain) { $scr1 = $laptopMain.WorkingArea; $scr2 = $screenPad.WorkingArea }
    else { $scr1 = $screenPad.WorkingArea; $scr2 = $scr1 }
} else {
    Write-Host "$tag WARNING: No ScreenPad, fallback"
    $fb = $allScreens | Where-Object { -not $_.Primary } | Sort-Object { $_.WorkingArea.Y }
    if ($fb.Count -ge 2) { $scr1 = $fb[0].WorkingArea; $scr2 = $fb[1].WorkingArea }
    elseif ($fb.Count -eq 1) { $scr1 = $fb[0].WorkingArea; $scr2 = $scr1 }
    else { $scr1 = ($allScreens | Where-Object { $_.Primary })[0].WorkingArea; $scr2 = $scr1 }
}

$screen1 = @{ L=$scr1.X; T=$scr1.Y; W=$scr1.Width; H=$scr1.Height }
$screen2 = @{ L=$scr2.X; T=$scr2.Y; W=$scr2.Width; H=$scr2.Height }

Write-Host "$tag Laptop main: ($($screen1.L),$($screen1.T)) $($screen1.W)x$($screen1.H)"
Write-Host "$tag ScreenPad:   ($($screen2.L),$($screen2.T)) $($screen2.W)x$($screen2.H)"

# Win11 invisible borders
$bL = 7; $bT = 0; $bR = 7; $bB = 7

# --- Session profiles ---
$profiles = @{
    "rbok" = @(
        @{ Name="orchestrator"; Tmux="rbok-orchestrator"; Screen=$screen1; Cols=2; Rows=2; Col=0; Row=0 },
        @{ Name="claude";       Tmux="rbok-claude";       Screen=$screen1; Cols=2; Rows=2; Col=1; Row=0 },
        @{ Name="codex";        Tmux="rbok-codex";        Screen=$screen1; Cols=2; Rows=2; Col=0; Row=1 },
        @{ Name="copilot";      Tmux="rbok-copilot";      Screen=$screen1; Cols=2; Rows=2; Col=1; Row=1 },
        @{ Name="cursor";       Tmux="rbok-cursor";       Screen=$screen2; Cols=2; Rows=1; Col=0; Row=0 },
        @{ Name="gemini";       Tmux="rbok-gemini";       Screen=$screen2; Cols=2; Rows=1; Col=1; Row=0 }
    )
    "42t" = @(
        @{ Name="orchestrator"; Tmux="42t-orchestrator"; Screen=$screen1; Cols=2; Rows=2; Col=0; Row=0 },
        @{ Name="claude";       Tmux="42t-claude";       Screen=$screen1; Cols=2; Rows=2; Col=1; Row=0 },
        @{ Name="codex";        Tmux="42t-codex";        Screen=$screen1; Cols=2; Rows=2; Col=0; Row=1 },
        @{ Name="copilot";      Tmux="42t-copilot";      Screen=$screen1; Cols=2; Rows=2; Col=1; Row=1 },
        @{ Name="cursor";       Tmux="42t-cursor";       Screen=$screen2; Cols=2; Rows=1; Col=0; Row=0 },
        @{ Name="gemini";       Tmux="42t-gemini";       Screen=$screen2; Cols=2; Rows=1; Col=1; Row=0 }
    )
}

# --- Functions ---

function Get-WezTermWindows {
    $handles = @()
    Get-Process -Name "wezterm-gui" -ErrorAction SilentlyContinue | ForEach-Object {
        $h = $_.MainWindowHandle
        if ($h -ne [IntPtr]::Zero -and [WinPos]::IsWindowVisible($h)) {
            $handles += @{ Handle = $h; PID = $_.Id }
        }
    }
    return $handles
}

function Test-SSHConnection {
    $result = & wsl bash -lc "ssh -p 3022 -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no -i $sshKey $sshTarget 'echo ok' 2>/dev/null"
    return ($result -eq "ok")
}

function Start-WezTermSession($session) {
    $name = $session.Tmux
    $scriptPath = Join-Path $env:TEMP "wez_connect_$name.sh"
    @"
#!/bin/bash
while true; do
    clear
    echo "[$name] Connecting..."
    ssh -tt -p 3022 \
        -o ConnectTimeout=10 \
        -o ServerAliveInterval=15 \
        -o ServerAliveCountMax=3 \
        -o StrictHostKeyChecking=no \
        -i ~/.ssh/id_rsa \
        $sshTarget \
        "tmux attach-session -t $name 2>/dev/null || tmux new-session -As $name"
    echo ""
    echo "[$name] Disconnected. Reconnecting in 5s... (Ctrl+C to stop)"
    sleep 5
done
"@ | Set-Content -Path $scriptPath -Encoding UTF8 -NoNewline
    $wslPath = $scriptPath -replace '\\','/' -replace '^C:','/mnt/c'
    $proc = Start-Process -FilePath $wezterm -ArgumentList "start --always-new-process -- wsl bash $wslPath" -PassThru
    return $proc
}

function Position-Window($handle, $session) {
    $scr = $session.Screen
    $tileW = [Math]::Floor($scr.W / $session.Cols)
    $tileH = [Math]::Floor($scr.H / $session.Rows)
    $finalX = $scr.L + ($session.Col * $tileW) - $bL
    $finalY = $scr.T + ($session.Row * $tileH) - $bT
    $winW   = $tileW + $bL + $bR
    $winH   = $tileH + $bT + $bB
    $name   = $session.Name

    # Step 1: MoveWindow at screen top (Y = screen.T) to set correct size
    # MoveWindow at top of screen always works regardless of DPI
    $topY = $scr.T
    [WinPos]::MoveWindow($handle, $finalX, $topY, $winW, $winH, $true) | Out-Null
    Start-Sleep -Milliseconds 300

    # DPI correction: if size is wrong, re-apply (window now on target monitor)
    $r = New-Object WinPos+RECT
    [WinPos]::GetWindowRect($handle, [ref]$r) | Out-Null
    $actW = $r.Right - $r.Left; $actH = $r.Bottom - $r.Top
    if ([Math]::Abs($actW - $winW) -gt 3 -or [Math]::Abs($actH - $winH) -gt 3) {
        [WinPos]::MoveWindow($handle, $finalX, $topY, $winW, $winH, $true) | Out-Null
        Start-Sleep -Milliseconds 300
    }

    # Step 2: if final Y differs from top, use SetWindowPos + SWP_NOSIZE to move down
    if ($finalY -ne $topY) {
        # Probe: send target Y, measure actual Y, calculate scale factor
        $flags = [WinPos]::SWP_NOSIZE -bor [WinPos]::SWP_NOZORDER
        [WinPos]::SetWindowPos($handle, [IntPtr]::Zero, $finalX, $finalY, 0, 0, $flags) | Out-Null
        Start-Sleep -Milliseconds 200

        [WinPos]::GetWindowRect($handle, [ref]$r) | Out-Null
        $actY = $r.Top

        # If Y is wrong, iteratively correct
        if ([Math]::Abs($actY - $finalY) -gt 3) {
            $scale = if ($finalY -ne 0) { [double]$actY / [double]$finalY } else { 1.0 }
            if ($scale -gt 0.1 -and $scale -lt 10) {
                $compensatedY = [Math]::Round($finalY / $scale)
                [WinPos]::SetWindowPos($handle, [IntPtr]::Zero, $finalX, $compensatedY, 0, 0, $flags) | Out-Null
                Start-Sleep -Milliseconds 200
                [WinPos]::GetWindowRect($handle, [ref]$r) | Out-Null
                $actY = $r.Top
            }
        }
    }

    # Final read
    [WinPos]::GetWindowRect($handle, [ref]$r) | Out-Null
    $actW = $r.Right - $r.Left; $actH = $r.Bottom - $r.Top
    Write-Host "$tag $name -> ($($r.Left),$($r.Top)) ${actW}x${actH}"
}

# --- Main ---

if ($Profile -and $profiles.ContainsKey($Profile)) {
    $sessions = $profiles[$Profile]
    $tag = "[$Profile-monitor]"
    Write-Host "$tag Using profile: $Profile"
} elseif ($RepositionOnly) {
    $sessions = $profiles["rbok"]
    Write-Host "$tag Reposition mode"
} else {
    Write-Host "$tag ERROR: -Profile required. Available: $($profiles.Keys -join ', ')"
    exit 1
}

if ($RepositionOnly) {
    Write-Host "$tag Repositioning..."
    $windows = Get-WezTermWindows
    if ($windows.Count -eq 0) { Write-Host "$tag No windows found."; exit 0 }
    $sorted = $windows | Sort-Object { $_.PID }
    for ($i = 0; $i -lt [Math]::Min($sorted.Count, $sessions.Count); $i++) {
        Position-Window $sorted[$i].Handle $sessions[$i]
    }
    exit 0
}

if ($ReconnectAll) {
    Write-Host "$tag Killing existing WezTerm..."
    Get-Process -Name "wezterm-gui" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

if (-not $ReconnectAll) {
    $existing = Get-Process -Name "wezterm-gui" -ErrorAction SilentlyContinue
    if ($existing -and $existing.Count -ge 6) {
        Write-Host "$tag Already running ($($existing.Count) windows). Use -RepositionOnly or -ReconnectAll."
        exit 0
    }
}

$statePath = Join-Path $env:USERPROFILE ".local\share\wezterm"
if (Test-Path $statePath) {
    Remove-Item $statePath -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $statePath -Force | Out-Null
}

Write-Host "$tag Testing SSH..."
if (-not (Test-SSHConnection)) {
    [System.Windows.Forms.MessageBox]::Show("SSH inaccessible`nCible: $sshTarget", "WezTerm Monitor", "OK", "Error") | Out-Null
    exit 1
}

Write-Host "$tag SSH OK. Launching $($sessions.Count) sessions..."

$positionedHandles = @{}
$knownHandlesBefore = @{}
Get-WezTermWindows | ForEach-Object { $knownHandlesBefore[$_.Handle] = $true }

foreach ($s in $sessions) {
    $proc = Start-WezTermSession $s
    if ($proc) { Write-Host "$tag Launched $($s.Name)" }

    $newHandle = $null
    for ($wait = 0; $wait -lt 20; $wait++) {
        Start-Sleep -Milliseconds 500
        foreach ($w in (Get-WezTermWindows)) {
            if (-not $knownHandlesBefore.ContainsKey($w.Handle) -and -not $positionedHandles.ContainsKey($w.Handle)) {
                $newHandle = $w.Handle
                break
            }
        }
        if ($newHandle) { break }
    }

    if ($newHandle) {
        Position-Window $newHandle $s
        $positionedHandles[$newHandle] = $true
    } else {
        Write-Host "$tag WARNING: no new window for $($s.Name)"
    }
}

# Restore any minimized windows
foreach ($h in $positionedHandles.Keys) {
    if ([WinPos]::IsIconic($h)) { [WinPos]::ShowWindow($h, 9) }
}

Write-Host "$tag Done. Auto-reconnect active in each window."
