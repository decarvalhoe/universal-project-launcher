# rbok_launcher.ps1  RBOK & Personal Projects Launcher (System Tray)
# Updated: 2026-03-05 - Integrated Universal Project Launcher
# Runs as admin, sits in system tray, click for menu
#
# Usage: powershell -ExecutionPolicy Bypass -File rbok_launcher.ps1

# Clear nested session guard so child Claude processes can start
Remove-Item Env:CLAUDECODE -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# --- Config ---
$scriptDir = Split-Path -Parent $PSCommandPath
$repoDir = "C:\dev\RBOK-clone"
$personalProjectsDir = "$env:USERPROFILE\42_training"
$universalLauncherDir = "$env:USERPROFILE\universal-project-launcher"

# --- Create tray icon ---
$icon = [System.Drawing.SystemIcons]::Application
try {
    $shellDll = [System.IO.Path]::Combine($env:SystemRoot, "System32", "shell32.dll")
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class IconEx {
    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr ExtractIcon(IntPtr hInst, string file, int index);
}
"@
    $hIcon = [IconEx]::ExtractIcon([IntPtr]::Zero, $shellDll, 18)
    if ($hIcon -ne [IntPtr]::Zero) {
        $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    }
} catch {}

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $icon
$tray.Text = "RBOK & Projects Orchestrator"
$tray.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip

# --- Helpers ---
function Add-MenuItem($text, $action, [switch]$Bold) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem($text)
    $item.Add_Click($action)
    if ($Bold) { $item.Font = New-Object System.Drawing.Font($item.Font, [System.Drawing.FontStyle]::Bold) }
    [void]$menu.Items.Add($item)
}

function Add-Sep { [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) }

# Launch via Windows Terminal (wt.exe) for proper visuals (font, colors, acrylic)
# Guard: kill existing orchestrator terminals before opening a new one
function Start-Script($file, $extraArgs = "") {
    # Kill any existing claude.exe processes to avoid accumulation
    Get-Process -Name "claude" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Process wt.exe "new-tab powershell.exe -ExecutionPolicy Bypass -File `"$file`" $extraArgs"
}

function Start-Cmd($command) {
    Start-Process wt.exe "new-tab powershell.exe -ExecutionPolicy Bypass -Command $command"
}

function Start-WSLBash($command) {
    Start-Process wt.exe "new-tab wsl.exe bash -c `"$command`""
}

# ==================== MENU ====================

# --- RBOK Section ---
Add-MenuItem "RBOK Orchestrator (YOLO)" {
    Start-Script "$scriptDir\rbok_orchestrator.ps1"
} -Bold

Add-MenuItem "RBOK Orchestrator (Resume)" {
    Start-Script "$scriptDir\rbok_orchestrator.ps1" "-Continue"
}

Add-MenuItem "RBOK Orchestrator (Safe)" {
    Start-Script "$scriptDir\rbok_orchestrator.ps1" "-Safe"
}

Add-MenuItem "RBOK Orchestrator (No Chrome)" {
    Start-Script "$scriptDir\rbok_orchestrator.ps1" "-NoBrowser"
}

Add-Sep

Add-MenuItem "Codex Orchestrator (YOLO)" {
    Start-Script "$scriptDir\rbok_orchestrator_codex.ps1"
} -Bold

Add-MenuItem "Codex Orchestrator (Safe)" {
    Start-Script "$scriptDir\rbok_orchestrator_codex.ps1" "-Safe"
}

Add-Sep

Add-MenuItem "6 Agents RBOK (WezTerm)" {
    $ps1 = "$scriptDir\wezterm_monitor.ps1"
    if (Test-Path $ps1) {
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$ps1`" -Profile rbok" -WindowStyle Hidden
    } else {
        [System.Windows.Forms.MessageBox]::Show("wezterm_monitor.ps1 introuvable", "RBOK")
    }
}

Add-MenuItem "RBOK Reconnect All" {
    $ps1 = "$scriptDir\wezterm_monitor.ps1"
    if (Test-Path $ps1) {
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$ps1`" -Profile rbok -ReconnectAll" -WindowStyle Hidden
    }
}

Add-MenuItem "Reposition WezTerm" {
    $ps1 = "$scriptDir\wezterm_monitor.ps1"
    if (Test-Path $ps1) {
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$ps1`" -RepositionOnly" -WindowStyle Hidden
    }
}

Add-Sep

# --- 42-Training Multi-Agent Section ---
Add-MenuItem "42T 6 Agents (WezTerm)" {
    $ps1 = "$scriptDir\wezterm_monitor.ps1"
    if (Test-Path $ps1) {
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$ps1`" -Profile 42t" -WindowStyle Hidden
    } else {
        [System.Windows.Forms.MessageBox]::Show("wezterm_monitor.ps1 introuvable", "42-Training")
    }
} -Bold

Add-MenuItem "42T Reconnect All" {
    $ps1 = "$scriptDir\wezterm_monitor.ps1"
    if (Test-Path $ps1) {
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$ps1`" -Profile 42t -ReconnectAll" -WindowStyle Hidden
    }
}

Add-MenuItem "42T Agent Status (SSH)" {
    Start-WSLBash "ssh -p 3022 -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa 194360-10166@gate.jpc.infomaniak.com 'tmux list-sessions 2>/dev/null | grep 42t-'; exec bash"
}

Add-MenuItem "42T GitHub Board" {
    Start-Process "https://github.com/users/decarvalhoe/projects/1"
}

Add-MenuItem "42T Issues (open)" {
    Start-Cmd "gh issue list --repo decarvalhoe/42-training --state open --limit 30"
}

Add-MenuItem "42T CI Status" {
    Start-Cmd "gh run list --repo decarvalhoe/42-training --limit 10"
}

Add-Sep

# --- Personal Projects Section ---
Add-MenuItem " 42 Training (Claude Optimized)" {
    Start-WSLBash "cd ~/.agent-conductor && python3 context_generator.py profiles/42-training.yaml 2>/dev/null; cd ~/42_training; exec bash"
} -Bold

Add-MenuItem "42 Training (Edit Progress)" {
    Start-WSLBash "cd ~/42_training && nano progression.json"
}

Add-MenuItem "42 Training (Git Status)" {
    Start-WSLBash "cd ~/42_training && git status && echo '' && git log --oneline -5 && exec bash"
}

Add-MenuItem "42 Training (Push to GitHub)" {
    Start-WSLBash "cd ~/42_training && ~/push-personal-repo.sh main && exec bash"
}

Add-Sep

Add-MenuItem " Universal Launcher (Add Project)" {
    Start-WSLBash "cd ~/.agent-conductor && python3 add_project.py && exec bash"
}

Add-MenuItem "Universal Launcher (List Profiles)" {
    Start-WSLBash "ls ~/.agent-conductor/profiles/*.yaml 2>/dev/null && exec bash"
}

Add-MenuItem "Universal Launcher (Generate Context)" {
    $profileName = [Microsoft.VisualBasic.Interaction]::InputBox("Enter profile name (without .yaml):", "Generate Context", "42-training")
    if ($profileName) {
        Start-WSLBash "cd ~/.agent-conductor; if [ -f profiles/$profileName.yaml ]; then python3 context_generator.py profiles/$profileName.yaml && echo '' && echo 'Context generated for: $profileName'; else echo 'Profile not found: $profileName' && ls profiles/ | grep yaml; fi; exec bash"
    }
}

Add-Sep

# --- CI/DevOps Section ---
Add-MenuItem "CI develop" {
    Start-Cmd "cd '$repoDir'; gh run list --branch develop --limit 10"
}

Add-MenuItem "PRs open" {
    Start-Cmd "cd '$repoDir'; gh pr list --state open"
}

Add-MenuItem "SSH dev node" {
    Start-Cmd "ssh -p 3022 -i ~/.ssh/id_rsa 194360-10166@gate.jpc.infomaniak.com"
}

Add-MenuItem "Smoke tests (dev)" {
    Start-Cmd "cd '$repoDir'; bash scripts/smoke_tests.sh dev"
}

Add-Sep

# --- File Explorer Shortcuts ---
Add-MenuItem " RBOK-clone" { Start-Process explorer.exe $repoDir }
Add-MenuItem " 42_training" {
    if (Test-Path $personalProjectsDir) {
        Start-Process explorer.exe $personalProjectsDir
    } else {
        [System.Windows.Forms.MessageBox]::Show("42_training folder not found", "Info")
    }
}
Add-MenuItem " Universal Launcher" {
    if (Test-Path $universalLauncherDir) {
        Start-Process explorer.exe $universalLauncherDir
    } else {
        [System.Windows.Forms.MessageBox]::Show("universal-project-launcher folder not found", "Info")
    }
}
Add-MenuItem " ~/.claude/" { Start-Process explorer.exe "$env:USERPROFILE\.claude" }
Add-MenuItem " ~/.agent-conductor/" {
    Start-Process explorer.exe "\wsl`$\Ubuntu\home\decarvalhoe\.agent-conductor"
}

Add-Sep

# --- GitHub Quick Access ---
Add-MenuItem " GitHub: 42-training" {
    Start-Process "https://github.com/decarvalhoe/42-training"
}

Add-MenuItem " GitHub: Universal Launcher" {
    Start-Process "https://github.com/decarvalhoe/universal-project-launcher"
}

Add-MenuItem " GitHub: RBOK Project" {
    Start-Process "https://github.com/RBOKproject/RBOK"
}

Add-Sep

Add-MenuItem "Exit" {
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Forms.Application]::Exit()
}

# ==================== RUN ====================

$tray.ContextMenuStrip = $menu

# Left-click also opens menu
$tray.Add_MouseClick({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $mi = $tray.GetType().GetMethod("ShowContextMenu",
            [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
        if ($mi) { $mi.Invoke($tray, $null) }
    }
})

$tray.BalloonTipTitle = "RBOK & Projects Orchestrator"
$tray.BalloonTipText = "Ready - RBOK + Personal Projects integrated"
$tray.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
$tray.ShowBalloonTip(3000)

[System.Windows.Forms.Application]::Run()
