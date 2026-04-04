# wezterm_monitor.ps1 - Multi-project WezTerm SSH/tmux Monitor
# Auto-reconnect SSH + Auto-position windows on dual screens
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
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

# --- SSH Config ---
$sshTarget = "194360-10166@gate.jpc.infomaniak.com"
$sshKey    = "~/.ssh/id_rsa"
$wezterm   = "C:\Program Files\WezTerm\wezterm-gui.exe"
$tag        = "[wez-monitor]"

# --- Detect monitors ---
$allScreens = [System.Windows.Forms.Screen]::AllScreens
$extScreens = $allScreens | Where-Object { -not $_.Primary } | Sort-Object { $_.WorkingArea.Y }

if ($extScreens.Count -ge 2) {
    $scr1 = $extScreens[0].WorkingArea
    $scr2 = $extScreens[1].WorkingArea
} elseif ($extScreens.Count -eq 1) {
    $scr1 = $extScreens[0].WorkingArea
    $scr2 = $extScreens[0].WorkingArea
} else {
    $primary = ($allScreens | Where-Object { $_.Primary })[0].WorkingArea
    $scr1 = $primary; $scr2 = $primary
}

$screen1 = @{ L=$scr1.X; T=$scr1.Y; W=$scr1.Width; H=$scr1.Height }
$screen2 = @{ L=$scr2.X; T=$scr2.Y; W=$scr2.Width; H=$scr2.Height }

Write-Host "$tag Screen1: ($($screen1.L),$($screen1.T)) $($screen1.W)x$($screen1.H)"
Write-Host "$tag Screen2: ($($screen2.L),$($screen2.T)) $($screen2.W)x$($screen2.H)"

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

# Select profile
if ($Profile -and $profiles.ContainsKey($Profile)) {
    $sessions = $profiles[$Profile]
    $tag = "[$Profile-monitor]"
    Write-Host "$tag Using profile: $Profile"
} elseif ($RepositionOnly) {
    # Reposition doesn't need a profile, operates on all visible WezTerm windows
    $sessions = $profiles["rbok"]  # default layout for positioning
    Write-Host "$tag Reposition mode (default layout)"
} else {
    Write-Host "$tag ERROR: -Profile required. Available: $($profiles.Keys -join ', ')"
    exit 1
}

# --- Functions ---

function Get-WezTermWindows {
    $handles = @()
    $procs = Get-Process -Name "wezterm-gui" -ErrorAction SilentlyContinue
    if (-not $procs) { return $handles }
    foreach ($p in $procs) {
        $h = $p.MainWindowHandle
        if ($h -ne [IntPtr]::Zero -and [WinPos]::IsWindowVisible($h)) {
            $handles += @{ Handle = $h; PID = $p.Id }
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

    # Write a reconnect script to avoid escaping issues across PowerShell->WezTerm->WSL
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

function Position-SingleWindow($handle, $targetX, $targetY, $targetW, $targetH, $name) {
    # Step 1: probe - send desired coords and measure what Windows actually does
    [WinPos]::MoveWindow($handle, $targetX, $targetY, $targetW, $targetH, $true) | Out-Null
    Start-Sleep -Milliseconds 200

    $r = New-Object WinPos+RECT
    [WinPos]::GetWindowRect($handle, [ref]$r) | Out-Null
    $actW = $r.Right - $r.Left
    $actH = $r.Bottom - $r.Top

    # Step 2: if size is wrong, DPI scaling happened during cross-monitor move.
    # Now the window IS on the target monitor, so a second MoveWindow won't scale.
    if ([Math]::Abs($actW - $targetW) -gt 3 -and $actW -gt 0) {
        $scale = [Math]::Round([double]$actW / [double]$targetW, 2)
        Write-Host "$tag $name cross-monitor DPI scale ${scale}x, re-applying"
        [WinPos]::MoveWindow($handle, $targetX, $targetY, $targetW, $targetH, $true) | Out-Null
        Start-Sleep -Milliseconds 200

        [WinPos]::GetWindowRect($handle, [ref]$r) | Out-Null
        $actW = $r.Right - $r.Left; $actH = $r.Bottom - $r.Top
        Write-Host "$tag $name -> ${actW}x${actH} at ($($r.Left),$($r.Top))"
    } else {
        Write-Host "$tag $name -> ($targetX,$targetY) ${actW}x${actH} OK"
    }
}

function Position-AllWindows {
    $windows = Get-WezTermWindows
    if ($windows.Count -eq 0) {
        Write-Host "$tag No WezTerm windows found."
        return $false
    }

    $sorted = $windows | Sort-Object { $_.PID }

    # Win11 invisible borders
    $bL = 7; $bT = 0; $bR = 7; $bB = 7

    for ($i = 0; $i -lt [Math]::Min($sorted.Count, $sessions.Count); $i++) {
        $s = $sessions[$i]
        $h = $sorted[$i].Handle
        $scr = $s.Screen

        $tileW = [Math]::Floor($scr.W / $s.Cols)
        $tileH = [Math]::Floor($scr.H / $s.Rows)
        $tileX = $scr.L + ($s.Col * $tileW) - $bL
        $tileY = $scr.T + ($s.Row * $tileH) - $bT
        $winW  = $tileW + $bL + $bR
        $winH  = $tileH + $bT + $bB

        Position-SingleWindow $h $tileX $tileY $winW $winH $s.Name
    }
    return $true
}

# --- Main ---

if ($RepositionOnly) {
    Write-Host "$tag Repositioning..."
    Position-AllWindows
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

# Purge WezTerm state
$statePath = Join-Path $env:USERPROFILE ".local\share\wezterm"
if (Test-Path $statePath) {
    Remove-Item $statePath -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $statePath -Force | Out-Null
}

Write-Host "$tag Testing SSH..."
if (-not (Test-SSHConnection)) {
    [System.Windows.Forms.MessageBox]::Show(
        "SSH inaccessible: verifier user/cle et acces gateway`nCible: $sshTarget",
        "WezTerm Monitor", "OK", "Error"
    ) | Out-Null
    exit 1
}

Write-Host "$tag SSH OK. Launching $($sessions.Count) sessions..."

foreach ($s in $sessions) {
    $proc = Start-WezTermSession $s
    if ($proc) { Write-Host "$tag Launched $($s.Name) (PID $($proc.Id))" }
    Start-Sleep -Seconds 2
}

Write-Host "$tag Waiting for windows..."
Start-Sleep -Seconds 5

for ($attempt = 1; $attempt -le 3; $attempt++) {
    $windows = Get-WezTermWindows
    if ($windows.Count -ge $sessions.Count) {
        Write-Host "$tag Positioning $($windows.Count) windows..."
        Position-AllWindows
        break
    }
    Write-Host "$tag $($windows.Count)/$($sessions.Count) visible (attempt $attempt/3)..."
    Start-Sleep -Seconds 3
}

Write-Host "$tag Done. Auto-reconnect active in each window."
