# rbok_launcher.ps1 — Multi-Project System Tray Launcher
# Reorganised 2026-05-04 — clean sub-menus + icons + status header
# Runs from system tray. Click for menu.
#
# Usage: powershell -STA -NoProfile -ExecutionPolicy Bypass -File rbok_launcher.ps1

# Allow nested Claude processes spawned from menu items
Remove-Item Env:CLAUDECODE -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# ============================================================
#  Win11 native theming (auto Light/Dark + Mica backdrop)
# ============================================================
# Read AppsUseLightTheme from the system, render the ContextMenuStrip with
# colors that match, and apply DWM Mica backdrop (DWMWA_SYSTEMBACKDROP_TYPE)
# to the popup window so it gets the same translucency as native Win11
# context menus.
function Get-IsDarkMode {
    $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction SilentlyContinue).AppsUseLightTheme
    return ($v -eq 0)
}
$isDark = Get-IsDarkMode

Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class TrayDwm {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
    [DllImport("dwmapi.dll")]
    public static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS pMarInset);

    [StructLayout(LayoutKind.Sequential)]
    public struct MARGINS {
        public int leftWidth;
        public int rightWidth;
        public int topHeight;
        public int bottomHeight;
    }

    public const int DWMWA_TRANSITIONS_FORCEDISABLED = 3;   // disable Win11 fade in/out
    public const int DWMWA_USE_IMMERSIVE_DARK_MODE   = 20;
    public const int DWMWA_WINDOW_CORNER_PREFERENCE  = 33;
    public const int DWMWA_SYSTEMBACKDROP_TYPE       = 38;
    public const int DWMSBT_AUTO       = 0;
    public const int DWMSBT_NONE       = 1;
    public const int DWMSBT_MAINWINDOW = 2;  // Mica
    public const int DWMSBT_TRANSIENT  = 3;  // Acrylic
    public const int DWMSBT_TABBED     = 4;  // Mica Alt
    public const int DWMWCP_DEFAULT     = 0;
    public const int DWMWCP_DONOTROUND  = 1;
    public const int DWMWCP_ROUND       = 2;
    public const int DWMWCP_ROUNDSMALL  = 3;

    public static int ApplyRoundedCorners(IntPtr h, int pref) {
        if (h == IntPtr.Zero) return -1;
        return DwmSetWindowAttribute(h, DWMWA_WINDOW_CORNER_PREFERENCE, ref pref, 4);
    }
    public static int DisableTransitions(IntPtr h) {
        if (h == IntPtr.Zero) return -1;
        int v = 1;
        return DwmSetWindowAttribute(h, DWMWA_TRANSITIONS_FORCEDISABLED, ref v, 4);
    }

    // Sets the DWM dark mode flag only — no SystemBackdrop, no frame extension.
    // We tried DWMSBT_TRANSIENT + DwmExtendFrameIntoClientArea but it draws a
    // visible grey gradient at the top of the form (the "extended frame" area
    // that's supposed to show acrylic, but our form is opaque so it just shows
    // a stale frame artifact). Going opaque + rounded only is cleaner.
    public static int Apply(IntPtr h, bool dark, int backdrop) {
        if (h == IntPtr.Zero) return -1;
        int d = dark ? 1 : 0;
        return DwmSetWindowAttribute(h, DWMWA_USE_IMMERSIVE_DARK_MODE, ref d, 4);
    }
}

// Global low-level mouse hook. Fires for ANY mouse-down anywhere on the
// desktop, regardless of which window owns it. We use it to detect "click
// outside the menu" — much more reliable than Form.Deactivate, which
// flickers like crazy because Win11/Explorer constantly steals foreground
// from windows launched out of the notification area.
public static class TrayMouseHook {
    public delegate void OutsideClickHandler(int x, int y);
    public static event OutsideClickHandler OutsideClick;

    private delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll")] private static extern bool   UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] private static extern IntPtr GetModuleHandle(string name);

    private const int WH_MOUSE_LL    = 14;
    private const int WM_LBUTTONDOWN = 0x0201;
    private const int WM_RBUTTONDOWN = 0x0204;
    private const int WM_MBUTTONDOWN = 0x0207;
    private const int WM_NCLBUTTONDOWN = 0x00A1;

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int x; public int y; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MSLLHOOKSTRUCT {
        public POINT  pt;
        public uint   mouseData;
        public uint   flags;
        public uint   time;
        public IntPtr dwExtraInfo;
    }

    private static IntPtr   _hookId = IntPtr.Zero;
    private static HookProc _procRef;   // keep a strong ref so GC doesn't kill it

    public static void Install() {
        if (_hookId != IntPtr.Zero) return;
        _procRef = new HookProc(Callback);
        IntPtr hMod = GetModuleHandle(null);
        _hookId = SetWindowsHookEx(WH_MOUSE_LL, _procRef, hMod, 0);
    }
    public static void Uninstall() {
        if (_hookId != IntPtr.Zero) {
            UnhookWindowsHookEx(_hookId);
            _hookId = IntPtr.Zero;
            _procRef = null;
        }
    }

    private static IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0) {
            int msg = wParam.ToInt32();
            if (msg == WM_LBUTTONDOWN || msg == WM_RBUTTONDOWN ||
                msg == WM_MBUTTONDOWN || msg == WM_NCLBUTTONDOWN) {
                MSLLHOOKSTRUCT m = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                OutsideClickHandler h = OutsideClick;
                if (h != null) h(m.pt.x, m.pt.y);
            }
        }
        return CallNextHookEx(_hookId, nCode, wParam, lParam);
    }
}

// Foreground stealing: tray-launched popups don't get foreground because the
// click is handled by Explorer's notification area. This is the Microsoft-
// blessed workaround (Raymond Chen, "How can I get my window to be
// foreground?").
public static class TrayForeground {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);

    public static void Force(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero) return;
        IntPtr fg = GetForegroundWindow();
        if (fg == hWnd) return;
        uint fgPid;
        uint fgThread = GetWindowThreadProcessId(fg, out fgPid);
        uint myThread = GetCurrentThreadId();
        if (fgThread != myThread) {
            AttachThreadInput(myThread, fgThread, true);
            BringWindowToTop(hWnd);
            SetForegroundWindow(hWnd);
            AttachThreadInput(myThread, fgThread, false);
        } else {
            BringWindowToTop(hWnd);
            SetForegroundWindow(hWnd);
        }
    }
}

// Acrylic blur for popup windows.
// DWMWA_SYSTEMBACKDROP_TYPE only works on top-level windows with a frame
// (WS_OVERLAPPEDWINDOW). ToolStripDropDown popups are WS_POPUP so Mica via
// DWM is silently ignored. The undocumented SetWindowCompositionAttribute
// + ACCENT_ENABLE_ACRYLICBLURBEHIND DOES work on popup windows and produces
// the same visual effect as Win11 native context-menu acrylic.
public static class TrayAcrylic {
    [DllImport("user32.dll")]
    public static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WindowCompositionAttributeData data);

    [StructLayout(LayoutKind.Sequential)]
    public struct WindowCompositionAttributeData {
        public int    Attribute;
        public IntPtr Data;
        public int    SizeOfData;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct AccentPolicy {
        public int AccentState;
        public int AccentFlags;
        public int GradientColor;   // 0xAABBGGRR
        public int AnimationId;
    }

    public const int ACCENT_DISABLED                  = 0;
    public const int ACCENT_ENABLE_GRADIENT           = 1;
    public const int ACCENT_ENABLE_TRANSPARENTGRADIENT = 2;
    public const int ACCENT_ENABLE_BLURBEHIND         = 3;
    public const int ACCENT_ENABLE_ACRYLICBLURBEHIND  = 4;
    public const int WCA_ACCENT_POLICY                = 19;

    public static void Apply(IntPtr h, bool dark) {
        if (h == IntPtr.Zero) return;
        AccentPolicy accent = new AccentPolicy();
        accent.AccentState  = ACCENT_ENABLE_ACRYLICBLURBEHIND;
        accent.AccentFlags  = 0;
        // Tint over the blur. Format is 0xAABBGGRR (ABGR).
        // Dark : rgba(32, 32, 32, 200)   = 0xC8202020
        // Light: rgba(243,243,243, 200)  = 0xC8F3F3F3
        // Lower the alpha for more transparency / more blur visibility.
        accent.GradientColor = dark
            ? unchecked((int)0xC8202020)
            : unchecked((int)0xC8F3F3F3);
        accent.AnimationId  = 0;

        int size = Marshal.SizeOf(accent);
        IntPtr ptr = Marshal.AllocHGlobal(size);
        try {
            Marshal.StructureToPtr(accent, ptr, false);
            WindowCompositionAttributeData data = new WindowCompositionAttributeData();
            data.Attribute  = WCA_ACCENT_POLICY;
            data.SizeOfData = size;
            data.Data       = ptr;
            SetWindowCompositionAttribute(h, ref data);
        } finally {
            Marshal.FreeHGlobal(ptr);
        }
    }
}

// ====================================================================
// Win11 Flyout — borderless top-level Form replacing ContextMenuStrip.
// ContextMenuStrip is a WS_POPUP and cannot get rounded corners,
// real DWM acrylic, or escape SystemColors hover blue. A real top-level
// Form qualifies for DWMWA_WINDOW_CORNER_PREFERENCE + DWMWA_SYSTEMBACKDROP_TYPE
// and gives 100% control over rendering.
// ====================================================================
public class Win11FlyoutForm : Form {
    public bool NoActivate { get; set; }
    public Win11FlyoutForm() {
        this.DoubleBuffered = true;
        this.SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
    }
    protected override bool ShowWithoutActivation { get { return NoActivate; } }
    protected override CreateParams CreateParams {
        get {
            CreateParams p = base.CreateParams;
            if (NoActivate) p.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
            // WS_EX_TOOLWINDOW: hide from Alt+Tab
            p.ExStyle |= 0x00000080;
            return p;
        }
    }
}

// Single self-painting menu row. No child controls = no MouseLeave flicker
// when moving onto an inner Label, and no SystemColors override path.
public class FlyoutRow : Panel {
    public string Caption       { get; set; }
    public bool   BoldText      { get; set; }
    public bool   IsSubMenu     { get; set; }
    public bool   IsHeader      { get; set; }   // disabled informational row
    public Color  TextColor     { get; set; }
    public Color  DisabledColor { get; set; }
    public Color  HoverColor    { get; set; }
    public Color  NormalColor   { get; set; }

    public event EventHandler RowClicked;
    public event EventHandler RowHovered;

    // Process-wide font cache. The #1 GDI leak source in WinForms tray apps
    // is creating + disposing fonts on every OnPaint. We allocate once and
    // never dispose (lifetime = app lifetime).
    private static Font _boldFontCache;
    private static Font _chevronFontCache;
    private static Font GetBoldFont(Font baseFont) {
        if (_boldFontCache == null || _boldFontCache.Size != baseFont.Size) {
            _boldFontCache = new Font(baseFont.FontFamily, baseFont.Size, FontStyle.Bold);
        }
        return _boldFontCache;
    }
    private static Font GetChevronFont() {
        if (_chevronFontCache == null) {
            try { _chevronFontCache = new Font("Segoe Fluent Icons", 8f); }
            catch { _chevronFontCache = new Font("Segoe MDL2 Assets", 8f); }
        }
        return _chevronFontCache;
    }

    public FlyoutRow() {
        this.SetStyle(
            ControlStyles.AllPaintingInWmPaint |
            ControlStyles.OptimizedDoubleBuffer |
            ControlStyles.UserPaint |
            ControlStyles.ResizeRedraw |
            ControlStyles.SupportsTransparentBackColor, true);
        this.DoubleBuffered = true;
        this.MouseEnter += new EventHandler(OnRowMouseEnter);
        this.MouseLeave += new EventHandler(OnRowMouseLeave);
        this.Click      += new EventHandler(OnRowClick);
    }

    private void OnRowMouseEnter(object s, EventArgs e) {
        if (IsHeader) return;
        this.BackColor = HoverColor;
        if (RowHovered != null) RowHovered(this, EventArgs.Empty);
    }
    private void OnRowMouseLeave(object s, EventArgs e) {
        this.BackColor = NormalColor;
    }
    private void OnRowClick(object s, EventArgs e) {
        if (IsHeader) return;
        if (RowClicked != null) RowClicked(this, EventArgs.Empty);
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode      = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        g.TextRenderingHint  = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

        // Paint hover/normal bg with rounded corners (Win11 inset-pill look)
        Rectangle pill = new Rectangle(4, 2, this.Width - 8, this.Height - 4);
        if (this.BackColor != NormalColor) {
            using (System.Drawing.Drawing2D.GraphicsPath path = RoundedRect(pill, 4)) {
                using (SolidBrush b = new SolidBrush(this.BackColor)) {
                    g.FillPath(b, path);
                }
            }
        }

        // Text — use cached fonts (no per-paint allocation)
        Font f = BoldText ? GetBoldFont(this.Font) : this.Font;
        int chevW = IsSubMenu ? 28 : 12;
        Rectangle textRect = new Rectangle(16, 0, this.Width - 16 - chevW, this.Height);
        Color tc = IsHeader ? DisabledColor : TextColor;
        TextRenderer.DrawText(g, Caption, f, textRect, tc,
            TextFormatFlags.VerticalCenter | TextFormatFlags.Left |
            TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);

        // Sub-menu chevron (right-pointing > glyph from Segoe Fluent Icons) — cached
        if (IsSubMenu) {
            Font cf = GetChevronFont();
            Rectangle cr = new Rectangle(this.Width - 24, 0, 16, this.Height);
            TextRenderer.DrawText(g, "", cf, cr, tc,
                TextFormatFlags.VerticalCenter | TextFormatFlags.HorizontalCenter |
                TextFormatFlags.NoPrefix);
        }
    }

    private static System.Drawing.Drawing2D.GraphicsPath RoundedRect(Rectangle r, int radius) {
        var path = new System.Drawing.Drawing2D.GraphicsPath();
        int d = radius * 2;
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
"@

# ============================================================
#  Configuration
# ============================================================
$scriptDir            = Split-Path -Parent $PSCommandPath
$repoDir              = "C:\dev\RBOK-clone"
$personalProjectsDir  = "$env:USERPROFILE\42_training"
$universalLauncherDir = "$env:USERPROFILE\universal-project-launcher"
$wezMonitor           = Join-Path $scriptDir "wezterm_monitor.ps1"

# ============================================================
#  Tray icon
# ============================================================
$icon = [System.Drawing.SystemIcons]::Application
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class IconEx {
    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr ExtractIcon(IntPtr hInst, string file, int index);
}
"@ -ErrorAction SilentlyContinue
    $shellDll = [System.IO.Path]::Combine($env:SystemRoot, "System32", "shell32.dll")
    $hIcon = [IconEx]::ExtractIcon([IntPtr]::Zero, $shellDll, 18)
    if ($hIcon -ne [IntPtr]::Zero) { $icon = [System.Drawing.Icon]::FromHandle($hIcon) }
} catch {}

$tray         = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon    = $icon
$tray.Text    = "RBOK / NOMOS / 42T launcher"
$tray.Visible = $true

# ============================================================
#  Win11 Flyout — Form-based menu (rounded corners + acrylic + tokens)
# ============================================================
# A real top-level Form qualifies for DWMWA_WINDOW_CORNER_PREFERENCE +
# DWMWA_SYSTEMBACKDROP_TYPE (impossible on ContextMenuStrip's WS_POPUP).
# Every row paints itself via FlyoutRow — no SystemColors path can leak
# through, the hover never shows the system accent blue.

$script:OpenFlyouts = New-Object System.Collections.ArrayList   # currently visible
$script:AllFlyouts  = New-Object System.Collections.ArrayList   # everything ever created

function Close-AllFlyouts {
    [void]$script:OpenFlyouts.Clear()
    # Hide EVERY known flyout, not just the "open" list — defends against
    # desync between bookkeeping and what's actually on screen.
    foreach ($f in @($script:AllFlyouts)) {
        try {
            if ($f -and -not $f.IsDisposed) {
                $f.Hide()
                $f.CurrentSub = $null
            }
        } catch {}
    }
}

function New-Win11Flyout([switch]$NoActivate) {
    $f = New-Object Win11FlyoutForm
    $f.NoActivate     = $NoActivate.IsPresent
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $f.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
    $f.ShowInTaskbar   = $false
    $f.TopMost         = $true
    $f.AutoSize        = $true
    $f.AutoSizeMode    = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $f.Padding         = New-Object System.Windows.Forms.Padding(0, 6, 0, 6)
    $f.Font            = New-Object System.Drawing.Font('Segoe UI Variable', 9.5)
    if ($isDark) {
        # Aligned with Win11 Start menu surface
        $f.BackColor = [System.Drawing.Color]::FromArgb(26, 26, 26)   # #1A1A1A
        $f.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 255)
    } else {
        $f.BackColor = [System.Drawing.Color]::FromArgb(249, 249, 249) # #F9F9F9
        $f.ForeColor = [System.Drawing.Color]::FromArgb(26, 26, 26)
    }

    $stack = New-Object System.Windows.Forms.FlowLayoutPanel
    $stack.FlowDirection  = [System.Windows.Forms.FlowDirection]::TopDown
    $stack.WrapContents   = $false
    $stack.AutoSize       = $true
    $stack.AutoSizeMode   = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $stack.Dock           = [System.Windows.Forms.DockStyle]::Fill
    $stack.BackColor      = [System.Drawing.Color]::Transparent
    $stack.Padding        = New-Object System.Windows.Forms.Padding(0)
    $stack.Margin         = New-Object System.Windows.Forms.Padding(0)
    $f.Controls.Add($stack)
    $f | Add-Member -NotePropertyName Stack -NotePropertyValue $stack -Force
    $f | Add-Member -NotePropertyName CurrentSub -NotePropertyValue $null -Force

    # Apply Win11 native chrome on Show — rounded corners + dark mode flag.
    # We DON'T apply DWMWA_SYSTEMBACKDROP_TYPE because the form is opaque
    # (acrylic can't show through anyway) and it draws a visible grey
    # gradient artifact at the top.
    $f.add_Shown({
        try {
            [TrayDwm]::ApplyRoundedCorners($this.Handle, [TrayDwm]::DWMWCP_ROUND)
            [TrayDwm]::Apply($this.Handle, $isDark, 0)
            [TrayDwm]::DisableTransitions($this.Handle)
        } catch {}
    })
    # Force handle creation NOW (before any Show) so we can disable Win11's
    # automatic fade-in/fade-out animations. Without this, swapping subs
    # creates a visible cross-fade flash because the OLD sub is still
    # animating its hide while the NEW sub animates its show.
    $f.add_HandleCreated({
        try { [TrayDwm]::DisableTransitions($this.Handle) } catch {}
    })
    # Touch .Handle now → forces Win32 window creation right away → fires
    # HandleCreated → DisableTransitions runs BEFORE the form is ever shown.
    [void]$f.Handle
    [void][TrayDwm]::DisableTransitions($f.Handle)

    # Auto-close is handled by a global low-level mouse hook installed
    # below — we DELIBERATELY don't subscribe to Form.Deactivate. On Win11,
    # Explorer constantly steals foreground from windows launched out of the
    # tray, which made Deactivate fire on every mouse move into the menu
    # (= flickering close). The hook fires only on actual mouse-down anywhere
    # on the desktop, which is the real "user dismissed the menu" signal.
    [void]$script:AllFlyouts.Add($f)
    return $f
}

function _New-FlyoutRow($flyout, [string]$Text, [bool]$Bold, [bool]$IsSub, [bool]$IsHeader) {
    $row = New-Object FlyoutRow
    $row.Caption       = $Text
    $row.BoldText      = $Bold
    $row.IsSubMenu     = $IsSub
    $row.IsHeader      = $IsHeader
    $row.Font          = $flyout.Font
    $row.Width         = 360
    $row.Height        = 32
    $row.Margin        = New-Object System.Windows.Forms.Padding(0)
    $row.NormalColor   = $flyout.BackColor
    if ($isDark) {
        # Win11 Fluent 2 dark menu tokens (resolved from semi-transparent on #1A1A1A)
        $row.TextColor     = [System.Drawing.Color]::FromArgb(255, 255, 255)  # TextFillColorPrimary
        $row.DisabledColor = [System.Drawing.Color]::FromArgb(140, 140, 140)  # TextFillColorDisabled
        $row.HoverColor    = [System.Drawing.Color]::FromArgb(44, 44, 44)     # SubtleFillColorSecondary on #1A1A1A
    } else {
        $row.TextColor     = [System.Drawing.Color]::FromArgb(26, 26, 26)
        $row.DisabledColor = [System.Drawing.Color]::FromArgb(140, 140, 140)
        $row.HoverColor    = [System.Drawing.Color]::FromArgb(235, 235, 235)
    }
    $row.BackColor = $row.NormalColor
    $row.Cursor    = if ($IsHeader) { [System.Windows.Forms.Cursors]::Default } else { [System.Windows.Forms.Cursors]::Hand }
    [void]$flyout.Stack.Controls.Add($row)
    # Hovering a TERMINAL (non-sub) row closes any previously-opened sub.
    # Sub-rows are handled by openSub directly (show-new-then-hide-old to
    # avoid the visible flash between hide + show).
    $closePrevSub = {
        param($s, $e)
        if ($row.Tag -is [System.Windows.Forms.Form]) { return }   # sub-row: openSub handles
        if ($flyout.CurrentSub) {
            try { $flyout.CurrentSub.Hide() } catch {}
            [void]$script:OpenFlyouts.Remove($flyout.CurrentSub)
            $flyout.CurrentSub = $null
        }
    }.GetNewClosure()
    $row.add_RowHovered($closePrevSub)
    return $row
}

function Add-Item($parent, $text, $action, [switch]$Bold) {
    $row = _New-FlyoutRow $parent $text $Bold.IsPresent $false $false
    if ($action) {
        $click = { Close-AllFlyouts; & $action }.GetNewClosure()
        $row.add_RowClicked($click)
    }
}

function Add-Sub($parent, $text, [switch]$Bold) {
    $row = _New-FlyoutRow $parent $text $Bold.IsPresent $true $false
    # Sub-flyout is built now (so Add-DropItem calls work) but only added to
    # OpenFlyouts list when actually shown.
    $sub = New-Win11Flyout -NoActivate
    $row.Tag = $sub

    $openSub = {
        param($s, $e)
        $prevSub = $parent.CurrentSub
        if ($prevSub -eq $sub) { return }   # already showing this sub, no-op

        # Force layout so PreferredSize is real before placing
        $sub.PerformLayout()
        $w = $sub.PreferredSize.Width
        $h = $sub.PreferredSize.Height
        if ($w -lt 200) { $w = 360 }
        if ($h -lt 32)  { $h = 200 }

        $rowScreen = $row.PointToScreen([System.Drawing.Point]::new(0, 0))
        $screen    = [System.Windows.Forms.Screen]::FromPoint($rowScreen).WorkingArea

        # Prefer right of the row; flip to LEFT if no room (tray near right edge)
        $x = $rowScreen.X + $row.Width - 4
        if (($x + $w) -gt ($screen.Right - 8)) {
            $x = $rowScreen.X - $w + 4
        }
        if ($x -lt ($screen.Left + 8)) { $x = $screen.Left + 8 }

        # Vertical: align to row top, clamp inside the working area
        $y = $rowScreen.Y - 6
        if (($y + $h) -gt ($screen.Bottom - 8)) {
            $y = $screen.Bottom - $h - 8
        }
        if ($y -lt ($screen.Top + 8)) { $y = $screen.Top + 8 }

        # SHOW NEW BEFORE HIDING OLD — eliminates the empty-frame flicker
        # between the previous sub disappearing and the new sub appearing.
        $sub.Location = New-Object System.Drawing.Point([int]$x, [int]$y)
        if (-not $script:OpenFlyouts.Contains($sub)) { [void]$script:OpenFlyouts.Add($sub) }
        $sub.Show()
        $parent.CurrentSub = $sub
        if ($prevSub) {
            try { $prevSub.Hide() } catch {}
            [void]$script:OpenFlyouts.Remove($prevSub)
        }
    }.GetNewClosure()
    $row.add_RowHovered($openSub)
    return $sub
}

function Add-DropItem($subFlyout, $text, $action, [switch]$Bold) {
    Add-Item $subFlyout $text $action -Bold:$Bold
}

function Add-DropSep($subFlyout) { Add-Sep $subFlyout }

function Add-Sep($flyout) {
    $sep = New-Object System.Windows.Forms.Panel
    $sep.Height    = 1
    $sep.Width     = 340
    $sep.Margin    = New-Object System.Windows.Forms.Padding(12, 6, 12, 6)
    $sep.BackColor = if ($isDark) { [System.Drawing.Color]::FromArgb(60, 60, 60) } else { [System.Drawing.Color]::FromArgb(218, 218, 218) }
    [void]$flyout.Stack.Controls.Add($sep)
}

# Root flyout (the menu shown when tray is clicked)
$menu = New-Win11Flyout

# ============================================================
#  Action wrappers
# ============================================================
function Start-Script($file, $extraArgs = "") {
    Get-Process -Name "claude" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Process wt.exe "new-tab powershell.exe -ExecutionPolicy Bypass -File `"$file`" $extraArgs"
}
function Start-Cmd($command) {
    Start-Process wt.exe "new-tab powershell.exe -ExecutionPolicy Bypass -Command $command"
}
function Start-WSLBash($command) {
    Start-Process wt.exe "new-tab wsl.exe bash -c `"$command`""
}
function Start-Wez($profileName, [switch]$ReconnectAll, [switch]$RepositionOnly) {
    if (-not (Test-Path $wezMonitor)) {
        [System.Windows.Forms.MessageBox]::Show("wezterm_monitor.ps1 introuvable", $profileName) | Out-Null
        return
    }
    $args = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$wezMonitor,"-Profile",$profileName)
    if ($ReconnectAll)   { $args += "-ReconnectAll" }
    if ($RepositionOnly) { $args += "-RepositionOnly" }
    Start-Process powershell.exe -ArgumentList $args -WindowStyle Hidden
}

# Bring all 6 windows of a profile to the foreground (Z-order raise + focus).
# Uses Show-W11TaskbarGroup from the w11-theming-suite TaskbarGrouping module.
$tgModulePath = 'C:\Dev\w11-theming-suite\modules\TaskbarGrouping\TaskbarGrouping.psm1'
if (Test-Path $tgModulePath) {
    Import-Module $tgModulePath -Force -DisableNameChecking -ErrorAction SilentlyContinue
}
function Bring-WezGroupToFront($profileName) {
    if (Get-Command Show-W11TaskbarGroup -ErrorAction SilentlyContinue) {
        Show-W11TaskbarGroup -Profile $profileName | Out-Null
    }
}

# ============================================================
#  Status header (top of menu — informational, no action)
# ============================================================
function Get-ProfileStatus($profileName, $expected = 6) {
    $f = Join-Path $env:LOCALAPPDATA "wezterm-launcher\$profileName.pids"
    if (-not (Test-Path $f)) { return "$profileName ⚪ 0/$expected" }
    $pids = (Get-Content $f -ErrorAction SilentlyContinue) | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    $alive = 0
    foreach ($p in $pids) {
        # Match bare 'wezterm-gui' AND per-profile aliases 'wezterm-gui-rbok' etc.
        if (Get-Process -Id $p -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'wezterm-gui*' }) { $alive++ }
    }
    $glyph = if ($alive -eq 0) { "⚪" } elseif ($alive -lt $expected) { "🟡" } else { "🟢" }
    return "$profileName $glyph $alive/$expected"
}

function Refresh-StatusHeader {
    $header = "Status:  $(Get-ProfileStatus 'rbok')   |   $(Get-ProfileStatus 'nomos')   |   $(Get-ProfileStatus '42t')"
    if ($script:statusHeader) {
        $script:statusHeader.Caption = $header
        $script:statusHeader.Invalidate()
    }
}

# ============================================================
#  Menu
# ============================================================

# Top: status row (refreshed when menu opens)
$script:statusHeader = _New-FlyoutRow $menu "Status: ..." $false $false $true
Add-Sep $menu

# ----- 🚀 RBOK -----
$rbok = Add-Sub $menu "🚀  RBOK  —  6 agents WezTerm" -Bold
Add-DropItem $rbok "🟢  Launch 6 agents"        { Start-Wez 'rbok' } -Bold
Add-DropItem $rbok "🪟  Bring all to front (Ctrl+Alt+R)" { Bring-WezGroupToFront 'rbok' } -Bold
Add-DropItem $rbok "🔄  Reconnect (this profile only)" { Start-Wez 'rbok' -ReconnectAll }
Add-DropItem $rbok "📐  Reposition windows"     { Start-Wez 'rbok' -RepositionOnly }
Add-DropSep $rbok
Add-DropItem $rbok "📊  CI develop"             { Start-Cmd "cd '$repoDir'; gh run list --branch develop --limit 10" }
Add-DropItem $rbok "🔀  PRs open"               { Start-Cmd "cd '$repoDir'; gh pr list --state open" }
Add-DropItem $rbok "🌐  GitHub: RBOKproject/RBOK" { Start-Process "https://github.com/RBOKproject/RBOK" }
Add-DropSep $rbok
Add-DropItem $rbok "💻  Local Orchestrator (YOLO)"   { Start-Script "$scriptDir\rbok_orchestrator.ps1" }
Add-DropItem $rbok "💻  Local Orchestrator (Safe)"   { Start-Script "$scriptDir\rbok_orchestrator.ps1" "-Safe" }
Add-DropItem $rbok "💻  Local Orchestrator (Resume)" { Start-Script "$scriptDir\rbok_orchestrator.ps1" "-Continue" }

# ----- 🚀 NOMOS -----
$nomos = Add-Sub $menu "🚀  NOMOS  —  6 agents WezTerm" -Bold
Add-DropItem $nomos "🟢  Launch 6 agents"        { Start-Wez 'nomos' } -Bold
Add-DropItem $nomos "🪟  Bring all to front (Ctrl+Alt+N)" { Bring-WezGroupToFront 'nomos' } -Bold
Add-DropItem $nomos "🔄  Reconnect (this profile only)" { Start-Wez 'nomos' -ReconnectAll }
Add-DropItem $nomos "📐  Reposition windows"     { Start-Wez 'nomos' -RepositionOnly }
Add-DropSep $nomos
Add-DropItem $nomos "📊  CI main"                { Start-Cmd "gh run list --repo RBOKproject/Nomos --branch main --limit 10" }
Add-DropItem $nomos "🔀  PRs open"               { Start-Cmd "gh pr list --repo RBOKproject/Nomos --state open" }
Add-DropItem $nomos "🌐  GitHub: RBOKproject/Nomos" { Start-Process "https://github.com/RBOKproject/Nomos" }

# ----- 🚀 42-Training -----
$ft = Add-Sub $menu "🚀  42 Training  —  6 agents WezTerm" -Bold
Add-DropItem $ft "🟢  Launch 6 agents"           { Start-Wez '42t' } -Bold
Add-DropItem $ft "🪟  Bring all to front (Ctrl+Alt+T)" { Bring-WezGroupToFront '42t' } -Bold
Add-DropItem $ft "🔄  Reconnect (this profile only)" { Start-Wez '42t' -ReconnectAll }
Add-DropItem $ft "📐  Reposition windows"        { Start-Wez '42t' -RepositionOnly }
Add-DropSep $ft
Add-DropItem $ft "📊  CI status"                 { Start-Cmd "gh run list --repo decarvalhoe/42-training --limit 10" }
Add-DropItem $ft "🐛  Issues (open)"             { Start-Cmd "gh issue list --repo decarvalhoe/42-training --state open --limit 30" }
Add-DropItem $ft "📋  Project board"             { Start-Process "https://github.com/users/decarvalhoe/projects/1" }
Add-DropItem $ft "🌐  GitHub: 42-training"       { Start-Process "https://github.com/decarvalhoe/42-training" }
Add-DropSep $ft
Add-DropItem $ft "🧠  Local 42T (Claude optimized)" { Start-WSLBash 'cd ~/.agent-conductor && python3 context_generator.py profiles/42-training.yaml 2>/dev/null; cd ~/42_training; exec bash' }
Add-DropItem $ft "📝  Edit progression.json"     { Start-WSLBash 'cd ~/42_training && nano progression.json' }
Add-DropItem $ft "🔍  Local Git status"          { Start-WSLBash 'cd ~/42_training && git status && echo "" && git log --oneline -5 && exec bash' }
Add-DropItem $ft "⬆️  Push to GitHub"            { Start-WSLBash 'cd ~/42_training && ~/push-personal-repo.sh main && exec bash' }

Add-Sep $menu

# ----- 🛠️ Tools / Universal Launcher -----
$tools = Add-Sub $menu "🛠️  Tools / Universal Launcher"
Add-DropItem $tools "➕  Add a new project (interactive)" { Start-WSLBash 'cd ~/.agent-conductor && python3 add_project.py && exec bash' }
Add-DropItem $tools "📋  List profiles"          { Start-WSLBash 'ls ~/.agent-conductor/profiles/*.yaml 2>/dev/null && exec bash' }
Add-DropItem $tools "⚙️  Generate context"       {
    $p = [Microsoft.VisualBasic.Interaction]::InputBox("Profile name (no .yaml):", "Generate context", "42-training")
    if ($p) {
        $cmd = 'cd ~/.agent-conductor; if [ -f profiles/{0}.yaml ]; then python3 context_generator.py profiles/{0}.yaml && echo "" && echo "Context generated for: {0}"; else echo "Profile not found: {0}" && ls profiles/ | grep yaml; fi; exec bash' -f $p
        Start-WSLBash $cmd
    }
}
Add-DropSep $tools
Add-DropItem $tools "💻  Codex Orchestrator (legacy)" { Start-Script "$scriptDir\rbok_orchestrator_codex.ps1" }
Add-DropItem $tools "💻  Codex Orchestrator (Safe)"   { Start-Script "$scriptDir\rbok_orchestrator_codex.ps1" "-Safe" }

# ----- 🔧 SSH / Infra -----
$infra = Add-Sub $menu "🔧  SSH / Infra"
Add-DropItem $infra "🖥️  SSH dev node (interactive)" { Start-Cmd "ssh -p 3022 -i ~/.ssh/id_rsa 194360-10166@gate.jpc.infomaniak.com" }
Add-DropItem $infra "💨  Smoke tests (dev)"      { Start-Cmd "cd '$repoDir'; bash scripts/smoke_tests.sh dev" }
Add-DropItem $infra "📡  42T tmux status (SSH)"  { Start-WSLBash 'ssh -p 3022 -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa 194360-10166@gate.jpc.infomaniak.com "tmux list-sessions 2>/dev/null | grep 42t-"; exec bash' }

# ----- 📁 Folders -----
$folders = Add-Sub $menu "📁  Folders"
Add-DropItem $folders "📁  RBOK-clone"           { Start-Process explorer.exe $repoDir }
Add-DropItem $folders "📁  42_training" {
    if (Test-Path $personalProjectsDir) { Start-Process explorer.exe $personalProjectsDir }
    else { [System.Windows.Forms.MessageBox]::Show("42_training folder not found", "Info") | Out-Null }
}
Add-DropItem $folders "📁  Universal Launcher" {
    if (Test-Path $universalLauncherDir) { Start-Process explorer.exe $universalLauncherDir }
    else { [System.Windows.Forms.MessageBox]::Show("universal-project-launcher folder not found", "Info") | Out-Null }
}
Add-DropItem $folders "📁  ~/.claude"            { Start-Process explorer.exe "$env:USERPROFILE\.claude" }
Add-DropItem $folders "📁  ~/.agent-conductor"   { Start-Process explorer.exe "\\wsl`$\Ubuntu\home\decarvalhoe\.agent-conductor" }

# ----- 🌐 GitHub bookmarks -----
$gh = Add-Sub $menu "🌐  GitHub bookmarks"
Add-DropItem $gh "📦  Universal Launcher"        { Start-Process "https://github.com/decarvalhoe/universal-project-launcher" }
Add-DropItem $gh "📦  RBOK Project"              { Start-Process "https://github.com/RBOKproject/RBOK" }
Add-DropItem $gh "📦  NOMOS Project"             { Start-Process "https://github.com/RBOKproject/Nomos" }
Add-DropItem $gh "📦  42-training"               { Start-Process "https://github.com/decarvalhoe/42-training" }

Add-Sep $menu

# ----- 🔄 Refresh status -----
Add-Item $menu "🔄  Refresh status" { Refresh-StatusHeader }

# ----- ⏏️ Quit -----
Add-Item $menu "⏏️  Quit" {
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Forms.Application]::Exit()
}

# ============================================================
#  Wire up tray — show Win11Flyout at cursor on click
# ============================================================
function Show-TrayMenu {
    Refresh-StatusHeader
    # Position above the tray cursor, snapped above the taskbar.
    $cur = [System.Windows.Forms.Cursor]::Position
    $screen = [System.Windows.Forms.Screen]::FromPoint($cur).WorkingArea
    # Force layout pass so AutoSize gives us the real menu size before placing
    $menu.PerformLayout()
    $w = $menu.PreferredSize.Width
    $h = $menu.PreferredSize.Height
    $x = [Math]::Min($cur.X, $screen.Right  - $w - 8)
    $y = [Math]::Min($cur.Y - $h - 8, $screen.Bottom - $h - 8)
    if ($x -lt $screen.Left)   { $x = $screen.Left + 8 }
    if ($y -lt $screen.Top)    { $y = $screen.Top + 8 }
    $menu.Location = New-Object System.Drawing.Point($x, $y)
    if (-not $script:OpenFlyouts.Contains($menu)) { [void]$script:OpenFlyouts.Add($menu) }
    $menu.Show()
    [void][TrayDwm]::ApplyRoundedCorners($menu.Handle, [TrayDwm]::DWMWCP_ROUND)
    [void][TrayDwm]::Apply($menu.Handle, $isDark, 0)   # dark mode flag only
    [void][TrayDwm]::DisableTransitions($menu.Handle)
    # Steal foreground from Explorer (which owns the tray) so the menu has
    # input focus immediately.
    [TrayForeground]::Force($menu.Handle)
}

$tray.Add_MouseClick({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -or
        $e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        Show-TrayMenu
    }
})

# Install global mouse hook ONCE at startup. The hook fires on every
# mouse-down anywhere on the desktop. We close the menu only if the click
# is OUTSIDE every flyout — clicks inside fall through to FlyoutRow's own
# Click handler which runs the action and Close-AllFlyouts itself.
[TrayMouseHook]::Install()
[TrayMouseHook]::add_OutsideClick({
    param($x, $y)
    # Defer to UI thread? We're on the installing thread (= main UI thread)
    # because WH_MOUSE_LL is dispatched via the message pump of the thread
    # that called SetWindowsHookEx, so direct calls to .Hide() are safe.
    $cur = New-Object System.Drawing.Point([int]$x, [int]$y)
    $insideAny = $false
    foreach ($fl in @($script:AllFlyouts)) {
        try {
            if ($fl -and -not $fl.IsDisposed -and $fl.Visible -and $fl.Bounds.Contains($cur)) {
                $insideAny = $true; break
            }
        } catch {}
    }
    if (-not $insideAny) { Close-AllFlyouts }
})

# ============================================================
#  Global hotkeys: Ctrl+Alt+R / Ctrl+Alt+N / Ctrl+Alt+T
#  Bring all windows of a profile to the foreground in one shot.
# ============================================================
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class HotkeyForm : Form {
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public const int WM_HOTKEY = 0x0312;
    public const uint MOD_ALT = 0x1, MOD_CTRL = 0x2;
    public Action<int> OnHotkey;
    public HotkeyForm() {
        this.ShowInTaskbar = false;
        this.WindowState = FormWindowState.Minimized;
        this.FormBorderStyle = FormBorderStyle.FixedToolWindow;
        this.Opacity = 0;
        this.Load += (s,e) => this.Visible = false;
    }
    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && OnHotkey != null) OnHotkey((int)m.WParam);
        base.WndProc(ref m);
    }
}
"@ -ReferencedAssemblies System.Windows.Forms -ErrorAction SilentlyContinue

$hkForm = New-Object HotkeyForm
$hkForm.OnHotkey = {
    param($id)
    switch ($id) {
        1 { Bring-WezGroupToFront 'rbok' }
        2 { Bring-WezGroupToFront 'nomos' }
        3 { Bring-WezGroupToFront '42t' }
    }
}
# VK_R = 0x52, VK_N = 0x4E, VK_T = 0x54
$mod = [HotkeyForm]::MOD_CTRL -bor [HotkeyForm]::MOD_ALT
[HotkeyForm]::RegisterHotKey($hkForm.Handle, 1, $mod, 0x52) | Out-Null
[HotkeyForm]::RegisterHotKey($hkForm.Handle, 2, $mod, 0x4E) | Out-Null
[HotkeyForm]::RegisterHotKey($hkForm.Handle, 3, $mod, 0x54) | Out-Null

# Boot toast
$tray.BalloonTipTitle = "RBOK / NOMOS / 42T launcher"
$tray.BalloonTipText  = "Ready. Hotkeys: Ctrl+Alt+R/N/T to bring profile groups to front."
$tray.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
$tray.ShowBalloonTip(2500)

[System.Windows.Forms.Application]::Run($hkForm)
