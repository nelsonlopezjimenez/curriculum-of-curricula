# 🖥️ First Logon Setup — README

> **Edmonds College / Monroe Correctional Complex**  
> Windows 10 Domain-Joined Workstation Profile Automation  
> Scripts: `Setup-FirstLogon.ps1` · `Register-FirstLogonTask.ps1`

---

## 📋 Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [File Structure](#file-structure)
- [Configuration](#configuration)
- [Image Preparation](#image-preparation)
- [Testing](#testing)
- [Production Run](#production-run)
- [Logs](#logs)
- [Troubleshooting](#troubleshooting)

---

## Overview

This automation runs **once per user** on first login to a domain-joined workstation.  
It configures junctions, registry entries, file associations, and power settings  
so every new user gets a consistent, pre-configured environment.

Two modes are available via the `$isOsn` flag:

| Mode | Flag | What runs |
|------|------|-----------|
| **Full** | `$isOsn = $false` | Everything — junctions, VS Code, Git Bash, Chrome associations, shortcuts |
| **OSN** | `$isOsn = $true` | Power settings + Edge file associations + logon flag only |

---

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    BASE IMAGE PREPARATION                   │
│                                                             │
│  1. Copy Setup-FirstLogon.ps1 → C:\Users\Public\bin\        │
│  2. Run Register-FirstLogonTask.ps1 (once, as admin)        │
│  3. Scheduled Task registered ✓                             │
│  4. Image the machine                                       │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                    NEW USER LOGS IN                         │
│                                                             │
│  Windows creates C:\Users\<newuser> from Default profile    │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              SCHEDULED TASK FIRES (as SYSTEM)               │
│                                                             │
│  Checks registry flag → first logon? YES → proceed         │
└───────────────────────┬─────────────────────────────────────┘
                        │
            ┌───────────┴───────────┐
            ▼                       ▼
    ┌───────────────┐       ┌───────────────┐
    │  isOsn=false  │       │  isOsn=true   │
    │  FULL MODE    │       │  OSN MODE     │
    └───────┬───────┘       └───────┬───────┘
            │                       │
            ▼                       ▼
    ┌───────────────┐       ┌───────────────┐
    │ ✅ Power      │       │ ✅ Power      │
    │ ✅ AppData ─┐ │       │ ❌ Junctions  │
    │ ✅ .vscode ─┤ │       │ ❌ VS Code    │
    │ ✅ Dotfiles ─┘│       │ ❌ Git Bash   │
    │ ✅ VS Code    │       │ ✅ Edge assoc │
    │ ✅ Git Bash   │       │ ✅ Flag       │
    │ ✅ Chrome     │       └───────────────┘
    │ ✅ Shortcuts  │
    │ ✅ Flag       │
    └───────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              REGISTRY FLAG SET — NEVER RUNS AGAIN           │
│   HKLM:\SOFTWARE\EdmondsCollege\FirstLogon\<username>=done  │
└─────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
C:\Users\Public\bin\
│
├── Setup-FirstLogon.ps1          ← main script (this one)
├── Register-FirstLogonTask.ps1   ← registers scheduled task
│
├── golden25-AppData\             ← AppData junction target
│   ├── Local\
│   │   ├── Programs\
│   │   │   └── Microsoft VS Code\
│   │   └── Google\Chrome\
│   └── Roaming\
│
├── vscode\                       ← .vscode junction target
│   └── extensions\
│
└── dotfiles\                     ← dotfiles junction targets
    ├── .gitconfig
    ├── .npmrc
    ├── .bash_profile
    ├── .bash_history
    ├── .nvs
    └── Desktop\
        └── *.lnk                 ← desktop shortcuts

C:\Logs\                          ← all log files written here
```

---

## Configuration

Open `Setup-FirstLogon.ps1` and edit the top section:

```powershell
# ── PATHS ──────────────────────────────────────────────
$PublicBin      = "C:\Users\Public\bin"
$AppDataTarget  = "$PublicBin\golden25-AppData"
$VscodeTarget   = "$PublicBin\vscode"
$DotfilesTarget = "$PublicBin\dotfiles"

# ── BROWSERS ───────────────────────────────────────────
$ChromePath = "$AppDataTarget\Local\Google\Chrome\Application\chrome.exe"
$EdgePath   = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

# ── MODE ───────────────────────────────────────────────
$isOsn = $false   # ← change to $true for OSN mode
```

### File associations configured

| Extension | Full mode (Chrome) | OSN mode (Edge) |
|-----------|-------------------|-----------------|
| `.mp4` `.avi` `.mkv` `.mov` `.webm` | ✅ | ✅ |
| `.jpg` `.jpeg` `.png` `.gif` `.bmp` | ✅ | ✅ |
| `.pdf` | ✅ | ✅ |

---

## Image Preparation

> Run these steps **once** on the reference machine before imaging.

### Step 1 — Copy scripts to Public bin

```powershell
# As Administrator
Copy-Item "Setup-FirstLogon.ps1"    "C:\Users\Public\bin\" -Force
Copy-Item "Register-FirstLogonTask.ps1" "C:\Users\Public\bin\" -Force
```

### Step 2 — Verify folder structure exists

```powershell
Test-Path "C:\Users\Public\bin\golden25-AppData"   # must be TRUE
Test-Path "C:\Users\Public\bin\vscode"             # must be TRUE
Test-Path "C:\Users\Public\bin\dotfiles"           # must be TRUE
```

### Step 3 — Register the Scheduled Task

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Register-FirstLogonTask.ps1
```

Expected output:
```
Scheduled Task registered: EdmondsCollege-FirstLogonSetup
Fires: At every user logon, runs as SYSTEM
Script: C:\Users\Public\bin\Setup-FirstLogon.ps1
```

### Step 4 — Verify task is registered

```powershell
Get-ScheduledTask -TaskName "EdmondsCollege-FirstLogonSetup" |
    Select-Object TaskName, State
```

### Step 5 — Image the machine

Proceed with your standard imaging process. The Scheduled Task is baked in.

---

## Testing

> ⚠️ Always test before imaging 20 machines.

### Option A — Test user (recommended)

```
┌──────────────────────────────────────────────────────┐
│  STEP 1 — Create test user (as admin, PowerShell)    │
└──────────────────────────────────────────────────────┘
```
```powershell
net user testuser Password123! /add
net localgroup Users testuser /add
```

```
┌──────────────────────────────────────────────────────┐
│  STEP 2 — Make sure scheduled task is registered     │
└──────────────────────────────────────────────────────┘
```
```powershell
Get-ScheduledTask -TaskName "EdmondsCollege-FirstLogonSetup"
```

```
┌──────────────────────────────────────────────────────┐
│  STEP 3 — Log in as testuser                         │
│  (Switch user or Remote Desktop)                     │
└──────────────────────────────────────────────────────┘
```

```
┌──────────────────────────────────────────────────────┐
│  STEP 4 — Check log (back as admin)                  │
└──────────────────────────────────────────────────────┘
```
```powershell
Get-ChildItem "C:\Logs\FirstLogon_testuser_*.log" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 |
    Get-Content
```

```
┌──────────────────────────────────────────────────────┐
│  STEP 5 — Verify results                             │
└──────────────────────────────────────────────────────┘
```
```powershell
# Junction created?
(Get-Item "C:\Users\testuser\AppData" -Force).Attributes
(Get-Item "C:\Users\testuser\.vscode" -Force).Attributes

# Registry flag set?
Get-ItemProperty "HKLM:\SOFTWARE\EdmondsCollege\FirstLogon" -Name "testuser"

# File associations set?
reg query "HKCU\Software\Classes\.mp4"

# VS Code context menu?
Test-Path "HKCU:\Software\Classes\*\shell\VSCode"
```

```
┌──────────────────────────────────────────────────────┐
│  STEP 6 — Clean up test user when done               │
└──────────────────────────────────────────────────────┘
```
```powershell
net user testuser /delete
Remove-Item "C:\Users\testuser" -Recurse -Force -ErrorAction SilentlyContinue

# Remove registry flag for testuser
Remove-ItemProperty "HKLM:\SOFTWARE\EdmondsCollege\FirstLogon" -Name "testuser" -ErrorAction SilentlyContinue
```

---

### Option B — Manual run as admin (quick check)

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Setup-FirstLogon.ps1
```

> ⚠️ Runs in context of current admin user — junctions point to admin profile.  
> Good for syntax/logic check only, not a full simulation.

---

### Option C — Dry run (check paths only, no changes)

Add `-WhatIf` to destructive calls, or temporarily set this at top of script:

```powershell
# Add at top of script for dry run simulation
$WhatIfPreference = $true
```

---

## Production Run

Once testing passes on one machine:

```
Machine 1 ──┐
Machine 2 ──┤
Machine 3 ──┤──→ Image from reference machine → done
   ...      │
Machine 20 ─┘
```

Each machine gets:
- `Setup-FirstLogon.ps1` at `C:\Users\Public\bin\`
- Scheduled Task `EdmondsCollege-FirstLogonSetup` pre-registered
- All Public\bin folder structure intact

No further action needed — script fires automatically on first user login.

---

## Logs

All logs written to `C:\Logs\`:

```
C:\Logs\
└── FirstLogon_<username>_<timestamp>.log
```

### Log format

```
2026-05-30 09:15:32 [INFO]  [testuser] ====== First Logon Setup Started (isOsn=False) ======
2026-05-30 09:15:32 [INFO]  [testuser] Power settings already applied — skipping.
2026-05-30 09:15:33 [INFO]  [testuser] AppData junction created → C:\Users\Public\bin\golden25-AppData
2026-05-30 09:15:33 [INFO]  [testuser] .vscode junction created → C:\Users\Public\bin\vscode
2026-05-30 09:15:33 [INFO]  [testuser] .gitconfig junction created → C:\Users\Public\bin\dotfiles\.gitconfig
2026-05-30 09:15:34 [INFO]  [testuser] File association set: .mp4 → Chrome
2026-05-30 09:15:35 [INFO]  [testuser] First logon flag set for testuser
2026-05-30 09:15:35 [INFO]  [testuser] ====== First Logon Setup Complete (isOsn=False) ======
```

### Check all logs

```powershell
Get-ChildItem "C:\Logs\FirstLogon_*.log" | Sort-Object LastWriteTime -Descending
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Script doesn't run on logon | Scheduled task not registered | Run `Register-FirstLogonTask.ps1` again |
| Script runs every login | Registry flag not set | Check `HKLM:\SOFTWARE\EdmondsCollege\FirstLogon` |
| AppData junction fails | User still logged in | Log out user first, retry |
| VS Code context menu missing | `Code.exe` path wrong | Verify `$CodePath` in config section |
| File associations not applied | Windows override | Use DISM XML method instead |
| Log file empty | SYSTEM has no write access to `C:\Logs` | Run `icacls C:\Logs /grant SYSTEM:F` |
| Git Bash menu missing | Wrong install path | Check `C:\Program Files\Git\git-bash.exe` exists |

### Reset first logon flag (re-run script for a user)

```powershell
# Force re-run for a specific user
Remove-ItemProperty "HKLM:\SOFTWARE\EdmondsCollege\FirstLogon" -Name "USERNAME" -ErrorAction SilentlyContinue
```

### Check scheduled task status

```powershell
Get-ScheduledTask -TaskName "EdmondsCollege-FirstLogonSetup" |
    Get-ScheduledTaskInfo |
    Select-Object LastRunTime, LastTaskResult, NextRunTime
```

> `LastTaskResult = 0` means success. Any other value — check `C:\Logs\`.

---

*Edmonds College CIS Department · Generated $(Get-Date -Format 'yyyy-MM-dd')*
