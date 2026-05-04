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

$menu = New-Object System.Windows.Forms.ContextMenuStrip

# ============================================================
#  Menu helpers
# ============================================================
function New-MenuItem($text, $action, [switch]$Bold) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem($text)
    if ($action) { $item.Add_Click($action) }
    if ($Bold) { $item.Font = New-Object System.Drawing.Font($item.Font, [System.Drawing.FontStyle]::Bold) }
    return $item
}
function Add-Item($parent, $text, $action, [switch]$Bold) {
    $i = New-MenuItem $text $action -Bold:$Bold
    [void]$parent.Items.Add($i)
    return $i
}
function Add-Sub($parent, $text, [switch]$Bold) {
    $i = New-MenuItem $text $null -Bold:$Bold
    [void]$parent.Items.Add($i)
    return $i
}
function Add-DropItem($parent, $text, $action, [switch]$Bold) {
    $i = New-MenuItem $text $action -Bold:$Bold
    [void]$parent.DropDownItems.Add($i)
    return $i
}
function Add-DropSep($parent) {
    [void]$parent.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
}
function Add-Sep($parent) {
    [void]$parent.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
}

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

# ============================================================
#  Status header (top of menu — informational, no action)
# ============================================================
function Get-ProfileStatus($profileName, $expected = 6) {
    $f = Join-Path $env:LOCALAPPDATA "wezterm-launcher\$profileName.pids"
    if (-not (Test-Path $f)) { return "$profileName ⚪ 0/$expected" }
    $pids = (Get-Content $f -ErrorAction SilentlyContinue) | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    $alive = 0
    foreach ($p in $pids) {
        if (Get-Process -Id $p -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq 'wezterm-gui' }) { $alive++ }
    }
    $glyph = if ($alive -eq 0) { "⚪" } elseif ($alive -lt $expected) { "🟡" } else { "🟢" }
    return "$profileName $glyph $alive/$expected"
}

function Refresh-StatusHeader {
    $header = "Status:  $(Get-ProfileStatus 'rbok')   •   $(Get-ProfileStatus 'nomos')   •   $(Get-ProfileStatus '42t')"
    if ($script:statusHeader) { $script:statusHeader.Text = $header }
}

# ============================================================
#  Menu
# ============================================================

# Top: status row (refreshed when menu opens)
$script:statusHeader = New-Object System.Windows.Forms.ToolStripMenuItem("Status: …")
$script:statusHeader.Enabled = $false
[void]$menu.Items.Add($script:statusHeader)
Add-Sep $menu

# ----- 🚀 RBOK -----
$rbok = Add-Sub $menu "🚀  RBOK  —  6 agents WezTerm" -Bold
Add-DropItem $rbok "🟢  Launch 6 agents"        { Start-Wez 'rbok' } -Bold
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
Add-DropItem $nomos "🔄  Reconnect (this profile only)" { Start-Wez 'nomos' -ReconnectAll }
Add-DropItem $nomos "📐  Reposition windows"     { Start-Wez 'nomos' -RepositionOnly }
Add-DropSep $nomos
Add-DropItem $nomos "📊  CI main"                { Start-Cmd "gh run list --repo RBOKproject/Nomos --branch main --limit 10" }
Add-DropItem $nomos "🔀  PRs open"               { Start-Cmd "gh pr list --repo RBOKproject/Nomos --state open" }
Add-DropItem $nomos "🌐  GitHub: RBOKproject/Nomos" { Start-Process "https://github.com/RBOKproject/Nomos" }

# ----- 🚀 42-Training -----
$ft = Add-Sub $menu "🚀  42 Training  —  6 agents WezTerm" -Bold
Add-DropItem $ft "🟢  Launch 6 agents"           { Start-Wez '42t' } -Bold
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
#  Wire up tray
# ============================================================
$tray.ContextMenuStrip = $menu

# Refresh status header when menu opens
$menu.Add_Opening({ Refresh-StatusHeader })

# Left-click also opens menu
$tray.Add_MouseClick({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $mi = $tray.GetType().GetMethod("ShowContextMenu",
            [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
        if ($mi) { $mi.Invoke($tray, $null) }
    }
})

# Boot toast
$tray.BalloonTipTitle = "RBOK / NOMOS / 42T launcher"
$tray.BalloonTipText  = "Ready. Right-click the tray icon for menu."
$tray.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
$tray.ShowBalloonTip(2000)

[System.Windows.Forms.Application]::Run()
