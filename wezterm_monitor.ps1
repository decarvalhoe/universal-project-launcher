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

// AppUserModelID grouping for Windows taskbar
// Setting the same AUMID on multiple windows makes Windows combine them
// in a single taskbar group (with hover preview thumbnails).
public class WindowAUMID {
    [DllImport("shell32.dll", PreserveSig = false)]
    public static extern void SHGetPropertyStoreForWindow(
        IntPtr hwnd,
        ref Guid iid,
        [MarshalAs(UnmanagedType.Interface)] out IPropertyStore ppv);

    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [ComImport]
    public interface IPropertyStore {
        void GetCount(out uint cProps);
        void GetAt(uint iProp, out PROPERTYKEY pkey);
        void GetValue(ref PROPERTYKEY key, out PropVariant pv);
        void SetValue(ref PROPERTYKEY key, ref PropVariant pv);
        void Commit();
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROPERTYKEY { public Guid fmtid; public uint pid; }

    [StructLayout(LayoutKind.Sequential)]
    public struct PropVariant {
        public ushort vt;
        public ushort wReserved1, wReserved2, wReserved3;
        public IntPtr pwszVal;
        public IntPtr p2;
    }

    public const ushort VT_LPWSTR = 31;

    public static bool SetAppId(IntPtr hwnd, string aumid) {
        try {
            Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
            IPropertyStore ps;
            SHGetPropertyStoreForWindow(hwnd, ref iid, out ps);
            // PKEY_AppUserModel_ID = {9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}, 5
            PROPERTYKEY key = new PROPERTYKEY {
                fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),
                pid   = 5
            };
            PropVariant pv = new PropVariant {
                vt       = VT_LPWSTR,
                pwszVal  = Marshal.StringToCoTaskMemUni(aumid)
            };
            ps.SetValue(ref key, ref pv);
            ps.Commit();
            Marshal.FreeCoTaskMem(pv.pwszVal);
            Marshal.ReleaseComObject(ps);
            return true;
        } catch (Exception) { return false; }
    }
}
"@

# --- SSH Config ---
$sshTarget = "194360-10166@gate.jpc.infomaniak.com"
$sshKey    = "~/.ssh/id_rsa"
$wezSource = "C:\Program Files\WezTerm\wezterm-gui.exe"
$tag       = "[wez-monitor]"

# Taskbar grouping via w11-theming-suite TaskbarGrouping module if available.
# Falls back to the original wezterm-gui.exe when the module is missing.
# Per-profile EXE hardlinks are required on Windows 11 26200+ where AUMID
# and window class alone are insufficient.
$grouping = $null
$tgModulePath = 'C:\Dev\w11-theming-suite\modules\TaskbarGrouping\TaskbarGrouping.psm1'
if ($Profile -and (Test-Path $tgModulePath)) {
    try {
        Import-Module $tgModulePath -Force -DisableNameChecking -ErrorAction Stop
        # Idempotent: ensures the hardlink + sibling DLLs exist for this profile.
        Set-W11TaskbarGrouping -SourceExe $wezSource -Profile $Profile -WithDependencies | Out-Null
        $grouping = Get-W11TaskbarGroupingLaunchSpec -SourceExe $wezSource -Profile $Profile -App wezterm
        Write-Host "$tag Taskbar grouping module loaded — alias: $($grouping.ExecutablePath)"
    } catch {
        Write-Host "$tag WARNING: TaskbarGrouping module load failed: $_"
    }
}
$wezterm = if ($grouping -and $grouping.ExecutablePath) { $grouping.ExecutablePath } else { $wezSource }
$wezExtraArgs = if ($grouping) { $grouping.ExtraArgs } else { @('start','--always-new-process') }

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
    "nomos" = @(
        @{ Name="orch";    Tmux="orch";    Screen=$screen1; Cols=2; Rows=2; Col=0; Row=0 },
        @{ Name="claude";  Tmux="claude";  Screen=$screen1; Cols=2; Rows=2; Col=1; Row=0 },
        @{ Name="codex";   Tmux="codex";   Screen=$screen1; Cols=2; Rows=2; Col=0; Row=1 },
        @{ Name="copilot"; Tmux="copilot"; Screen=$screen1; Cols=2; Rows=2; Col=1; Row=1 },
        @{ Name="cursor";  Tmux="cursor";  Screen=$screen2; Cols=2; Rows=1; Col=0; Row=0 },
        @{ Name="gemini";  Tmux="gemini";  Screen=$screen2; Cols=2; Rows=1; Col=1; Row=0 }
    )
}

# --- Functions ---

function Get-WezTermWindows {
    $handles = @()
    Get-Process | Where-Object { $_.Name -like 'wezterm-gui*' } -ErrorAction SilentlyContinue | ForEach-Object {
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
    # Profile-tagged script path so multiple profiles can coexist on disk
    $scriptPath = Join-Path $env:TEMP "wez_connect_${Profile}_$name.sh"
    @"
#!/bin/bash
printf '\e]0;[$Profile-$name]\a'
while true; do
    clear
    printf '\e]0;[$Profile-$name]\a'
    echo "[$Profile-$name] Connecting..."
    ssh -tt -p 3022 \
        -o ConnectTimeout=10 \
        -o ServerAliveInterval=15 \
        -o ServerAliveCountMax=3 \
        -o StrictHostKeyChecking=no \
        -i ~/.ssh/id_rsa \
        $sshTarget \
        "tmux attach-session -t $name 2>/dev/null || tmux new-session -As $name"
    echo ""
    echo "[$Profile-$name] Disconnected. Reconnecting in 5s... (Ctrl+C to stop)"
    sleep 5
done
"@.Replace("`r`n", "`n") | ForEach-Object { [System.IO.File]::WriteAllText($scriptPath, $_, (New-Object System.Text.UTF8Encoding $false)) }
    $wslPath = $scriptPath -replace '\\','/' -replace '^C:','/mnt/c'
    # Build full arg list: TaskbarGrouping module's launch-spec args (which
    # include `start --class W11ThemingSuite.<profile> --always-new-process`)
    # plus the program separator and the wsl bash command.
    $args = @() + $wezExtraArgs + @('--','wsl','bash',$wslPath)
    $proc = Start-Process -FilePath $wezterm -ArgumentList $args -PassThru
    return $proc
}

function Get-PidFilePath($profileName) {
    $dir = Join-Path $env:LOCALAPPDATA "wezterm-launcher"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return (Join-Path $dir "$profileName.pids")
}

function Save-PidsForProfile($profileName, $pids) {
    $f = Get-PidFilePath $profileName
    $pids -join "`n" | Set-Content -Path $f -Encoding utf8
}

function Get-WezTermWindowsForProfile($profileName) {
    # PID-file tracking: more reliable than title matching, because tmux
    # overwrites the OSC 0 title we set on connect.
    $f = Get-PidFilePath $profileName
    if (-not (Test-Path $f)) { return @() }
    $tracked = (Get-Content $f -ErrorAction SilentlyContinue) | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    if (-not $tracked) { return @() }
    $alive = @()
    foreach ($wpid in $tracked) {
        $p = Get-Process -Id $wpid -ErrorAction SilentlyContinue
        if ($p -and $p.ProcessName -eq 'wezterm-gui') {
            $h = $p.MainWindowHandle
            if ($h -ne [IntPtr]::Zero -and [WinPos]::IsWindowVisible($h)) {
                $alive += @{ Handle = $h; PID = $p.Id; Title = $p.MainWindowTitle }
            }
        }
    }
    return $alive
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
    # FIX B3: kill ONLY windows tagged for this profile, not every wezterm-gui
    Write-Host "$tag Killing existing WezTerm windows for profile '$Profile'..."
    $myWindows = Get-WezTermWindowsForProfile $Profile
    if ($myWindows.Count -gt 0) {
        $myWindows | ForEach-Object {
            Stop-Process -Id $_.PID -Force -ErrorAction SilentlyContinue
            Write-Host "$tag   killed PID $($_.PID) ($($_.Title))"
        }
        Start-Sleep -Seconds 2
    } else {
        Write-Host "$tag   (no existing windows for profile $Profile)"
    }
}

if (-not $ReconnectAll) {
    # FIX B1: count only windows for THIS profile, not all wez-gui across profiles.
    # This allows RBOK + NOMOS (+ 42T) to coexist on screen.
    $existingForProfile = Get-WezTermWindowsForProfile $Profile
    if ($existingForProfile -and $existingForProfile.Count -ge $sessions.Count) {
        Write-Host "$tag Profile '$Profile' already has $($existingForProfile.Count) windows running. Use -RepositionOnly or -ReconnectAll to refresh."
        exit 0
    }
    if ($existingForProfile -and $existingForProfile.Count -gt 0 -and $existingForProfile.Count -lt $sessions.Count) {
        Write-Host "$tag Profile '$Profile' partial: $($existingForProfile.Count)/$($sessions.Count) windows. Will not duplicate; use -ReconnectAll to refresh from scratch."
        exit 0
    }
}

# FIX B2: only wipe the wezterm state dir on -ReconnectAll. Otherwise it
# kills the local state of OTHER profiles' windows (RBOK ↔ NOMOS coexistence).
if ($ReconnectAll) {
    $statePath = Join-Path $env:USERPROFILE ".local\share\wezterm"
    if (Test-Path $statePath) {
        Remove-Item $statePath -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $statePath -Force | Out-Null
    }
}

Write-Host "$tag Testing SSH..."
if (-not (Test-SSHConnection)) {
    [System.Windows.Forms.MessageBox]::Show("SSH inaccessible`nCible: $sshTarget", "WezTerm Monitor", "OK", "Error") | Out-Null
    exit 1
}

Write-Host "$tag SSH OK. Launching $($sessions.Count) sessions..."

$positionedHandles = @{}
$knownHandlesBefore = @{}
$spawnedPids = @()  # FIX B1: track PIDs we spawn for THIS profile so future calls
                    # can detect which windows belong to which profile.
Get-WezTermWindows | ForEach-Object { $knownHandlesBefore[$_.Handle] = $true }

foreach ($s in $sessions) {
    $proc = Start-WezTermSession $s
    if ($proc) { Write-Host "$tag Launched $($s.Name)" }

    $newHandle = $null
    $newPid = $null
    for ($wait = 0; $wait -lt 20; $wait++) {
        Start-Sleep -Milliseconds 500
        foreach ($w in (Get-WezTermWindows)) {
            if (-not $knownHandlesBefore.ContainsKey($w.Handle) -and -not $positionedHandles.ContainsKey($w.Handle)) {
                $newHandle = $w.Handle
                $newPid = $w.PID
                break
            }
        }
        if ($newHandle) { break }
    }

    if ($newHandle) {
        Position-Window $newHandle $s
        # Set AUMID so Windows groups all 6 windows of THIS profile in a
        # single taskbar button with hover preview thumbnails.
        # AUMID format: <Vendor>.<App>.<Profile> — must be unique per group.
        $aumid = "Realisons.RBOKLauncher.$Profile"
        $ok = [WindowAUMID]::SetAppId($newHandle, $aumid)
        if ($ok) { Write-Host "$tag   $($s.Name) -> taskbar group '$aumid'" }
        $positionedHandles[$newHandle] = $true
        if ($newPid) { $spawnedPids += $newPid }
    } else {
        Write-Host "$tag WARNING: no new window for $($s.Name)"
    }
}

# Restore any minimized windows
foreach ($h in $positionedHandles.Keys) {
    if ([WinPos]::IsIconic($h)) { [WinPos]::ShowWindow($h, 9) }
}

# FIX B1: persist the PIDs so subsequent calls (parallel profile launch,
# -ReconnectAll for THIS profile only, status check) can find OUR windows
# without confusing them with other profiles' windows.
if ($spawnedPids.Count -gt 0) {
    Save-PidsForProfile $Profile $spawnedPids
    Write-Host "$tag Tracked $($spawnedPids.Count) PIDs for profile '$Profile' in $(Get-PidFilePath $Profile)"
}

Write-Host "$tag Done. Auto-reconnect active in each window."
