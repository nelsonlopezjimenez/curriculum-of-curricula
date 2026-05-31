# 🖥️ Workstation Profile Automation — README

> **Edmonds College / Monroe Correctional Complex**  
> Windows 10 Domain-Joined Workstation Profile Automation  
> Updated: 2026-05-30

---

## 📋 Table of Contents

- [Overview](#overview)
- [Scripts](#scripts)
- [How It Works](#how-it-works)
- [File Structure](#file-structure)
- [Base Image Preparation](#base-image-preparation)
- [User Provisioning](#user-provisioning)
- [Testing](#testing)
- [Production Run](#production-run)
- [Logs](#logs)
- [Troubleshooting](#troubleshooting)

---

## Overview

Four scripts automate workstation setup for domain-joined Windows 10 machines.
All provisioning (junctions, registry, PATH, shortcuts) happens **before first
logon** via `New-UserSetup.ps1`. The logon script only handles Quick Access pins.

**Architecture — junction-based shared profile:**

```
C:\Users\Public\bin\golden25-AppData\   <- shared AppData target
C:\Users\Public\bin\vscode\             <- shared .vscode target
C:\Users\Public\bin\dotfiles\           <- shared dotfiles target
        |
        | junctions (per user, created by New-UserSetup.ps1)
        |
C:\Users\<user>\AppData    ->  golden25-AppData
C:\Users\<user>\.vscode    ->  vscode
C:\Users\<user>\.gitconfig ->  dotfiles\.gitconfig
        ...
```

> All junctioned accounts share the same physical data.
> Adding content to `golden25-AppData` is immediately visible to all users.
> One student per laptop -- no session conflict.

---

## Scripts

| Script | When | Who runs |
|--------|------|----------|
| `Prepare-BaseImage.ps1` | Once, during image prep | Admin |
| `New-UserSetup.ps1` | After each user creation | Admin |
| `Setup-FirstLogon.ps1` | Automatically at first logon | SYSTEM via Scheduled Task |
| `Register-FirstLogonTask.ps1` | Once, during image prep (called by Prepare-BaseImage) | Admin |

---

## How It Works

```
PHASE 1 -- BASE IMAGE PREPARATION (once)
================================================
Admin runs Prepare-BaseImage.ps1
  |-- Verifies scripts + folder structure
  |-- Power settings + hibernate disabled
  |-- Defender exclusions for Public\bin
  |-- nvs settings.json linkToSystem: false
  |-- Git Bash context menu (HKLM)
  |-- Registers Scheduled Task
  |-- Provisions Default profile
        |
        v
Machine is imaged -> deployed to 20 machines

PHASE 2 -- USER PROVISIONING (per new user)
================================================
Admin creates user (existing script)
        |
        v
Admin runs New-UserSetup.ps1
  |-- Scans for unprovisioned users
  |-- Non-interactive logon -> creates profile folder
  |-- Sleep 5s (wait for lock release)
  |-- Creates junctions:
  |     AppData  -> golden25-AppData
  |     .vscode  -> vscode
  |     dotfiles -> .gitconfig, .npmrc, .bash_profile, etc.
  |-- Copies desktop shortcuts
  |-- Writes NTUSER.DAT registry:
  |     VS Code context menu
  |     File associations -> Chrome
  |     Folder options (show hidden + protected)
  |     NVS_HOME env variable
  |     PATH additions (npm, nvs, nvs\default, bin, Ollama)
  |-- nvs link 24.16.0 (non-interactive)
  |-- Sets provisioned flag

PHASE 3 -- FIRST LOGON (per user, automatic)
================================================
User logs in for first time
        |
        v
Scheduled Task fires (as SYSTEM)
  |-- Detects actual logged-in user via WMI
  |-- Skips machine accounts (CIS0792$ etc.)
  |-- Pins Quick Access: Public, Home, AppData
  |-- Sets quickaccess flag (never runs again)
```

---

## File Structure

```
C:\Users\Public\bin\
|
|-- Prepare-BaseImage.ps1       <- run once during image prep
|-- New-UserSetup.ps1           <- run after each user creation
|-- Setup-FirstLogon.ps1        <- runs at first logon (SYSTEM)
|-- Register-FirstLogonTask.ps1 <- called by Prepare-BaseImage
|
|-- golden25-AppData\           <- AppData junction target
|   |-- Local\
|   |   |-- nvs\                <- Node version manager
|   |   |-- Programs\
|   |   |   |-- Microsoft VS Code\
|   |   |   +-- Ollama\
|   |   +-- Google\Chrome\
|   +-- Roaming\
|       |-- Code\               <- VS Code user data
|       +-- npm\
|
|-- vscode\                     <- .vscode junction target
|   +-- extensions\
|
+-- dotfiles\                   <- dotfiles junction targets
    |-- .gitconfig
    |-- .npmrc
    |-- .bash_profile           <- includes nvs.sh source for Git Bash
    |-- .bash_history
    +-- Desktop\
        +-- *.lnk               <- desktop shortcuts

C:\Logs\                        <- all log files
```

---

## Base Image Preparation

> Run **once** on reference machine before imaging.  
> All scripts must be in `C:\Users\Public\bin\` first.

```powershell
cd C:\Users\Public\bin
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Prepare-BaseImage.ps1
```

**What it does (8 steps):**

| Step | Task | Scope |
|------|------|-------|
| 1 | Verify scripts + folder structure | Pre-flight check |
| 2 | Create missing folders | One-time |
| 3 | Power settings, disable hibernate/Fast Startup | Machine-wide |
| 4 | Defender exclusions for `Public\bin` | Machine-wide |
| 5 | nvs `settings.json` -- `linkToSystem: false` | Shared profile |
| 6 | Git Bash context menu (HKLM) | Machine-wide |
| 7 | Register Scheduled Task | Machine-wide |
| 8 | Provision Default profile | Default profile |

**Safe to re-run?** No -- exits if already prepared. Force re-run:
```powershell
Remove-Item "HKLM:\SOFTWARE\EdmondsCollege\BaseImage" -Recurse -Force
```

---

## User Provisioning

> Run after user creation script, before student first logs in.

```powershell
cd C:\Users\Public\bin
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\New-UserSetup.ps1
```

**Scanner behavior:**
- Scans `Get-LocalUser` for unprovisioned accounts
- Skips: `adm`, `Administrator`, `Guest`, `DefaultAccount`, `WDAGUtilityAccount`, `Public`, `All Users`
- Processes `Default` profile automatically (no password needed)
- Prompts for password per unprovisioned user found
- Sets `HKLM:\SOFTWARE\EdmondsCollege\FirstLogon\<username> = done` when complete

**PATH entries written per user:**

| Entry | Purpose |
|-------|---------|
| `%APPDATA%\npm` | npm global binaries |
| `%LOCALAPPDATA%\nvs` | nvs executable |
| `%LOCALAPPDATA%\nvs\default` | active Node version |
| `%USERPROFILE%\bin` | user local binaries |
| `%LOCALAPPDATA%\Programs\Ollama` | Ollama executable |

**Environment variables written:**

| Variable | Value |
|----------|-------|
| `NVS_HOME` | `%LOCALAPPDATA%\nvs` |

**nvs in Git Bash** -- `.bash_profile` contains:
```bash
export NVS_HOME="$LOCALAPPDATA/nvs"
[ -s "$NVS_HOME/nvs.sh" ] && . "$NVS_HOME/nvs.sh"
```

**Reset and re-provision a user:**
```powershell
Remove-ItemProperty "HKLM:\SOFTWARE\EdmondsCollege\FirstLogon" -Name "USERNAME"
.\New-UserSetup.ps1
```

---

## Testing

> Always test on one machine before imaging 20.

### Step 1 -- Create test user
```powershell
net user testuser Password123! /add
net localgroup Users testuser /add
```

### Step 2 -- Run provisioning
```powershell
.\New-UserSetup.ps1
# Enter password: Password123! when prompted
```

### Step 3 -- Verify before logon
```powershell
# Junctions created?
(Get-Item "C:\Users\testuser\AppData" -Force).Attributes   # must show ReparsePoint
(Get-Item "C:\Users\testuser\.vscode" -Force).Attributes   # must show ReparsePoint

# Registry flag set?
Get-ItemProperty "HKLM:\SOFTWARE\EdmondsCollege\FirstLogon" -Name "testuser"

# Check provisioning log
Get-ChildItem "C:\Logs\NewUserSetup_*.log" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 | Get-Content
```

### Step 4 -- Log in as testuser
Log in physically or via RDP:
```
mstsc /v:192.168.50.2
# credentials: COMPUTERNAME\testuser
```

### Step 5 -- Verify Quick Access pins
Check File Explorer -- Public, Home, AppData should appear in Quick Access.

### Step 6 -- Check logon log
```powershell
Get-ChildItem "C:\Logs\FirstLogon_testuser_*.log" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 | Get-Content
```

### Step 7 -- Clean up
```powershell
net user testuser /delete
Remove-Item "C:\Users\testuser" -Recurse -Force -ErrorAction SilentlyContinue
Remove-ItemProperty "HKLM:\SOFTWARE\EdmondsCollege\FirstLogon" -Name "testuser" -ErrorAction SilentlyContinue
```

---

## Production Run

```
Prepare-BaseImage.ps1 run on reference machine
        |
        v
Machine imaged -> deployed to all 20 machines
        |
        v
Per machine -- when student account created:
  Admin runs New-UserSetup.ps1
        |
        v
Student logs in -> Quick Access pinned automatically
```

**Each machine has:**
- All scripts in `C:\Users\Public\bin\`
- Scheduled Task `EdmondsCollege-FirstLogonSetup` registered
- Default profile provisioned with junctions
- Defender exclusion for `Public\bin`

---

## Logs

```
C:\Logs\
|-- PrepareBaseImage_<timestamp>.log   <- image prep log
|-- NewUserSetup_<timestamp>.log       <- provisioning log
+-- FirstLogon_<user>_<timestamp>.log  <- logon task log
```

**Check latest log:**
```powershell
Get-ChildItem "C:\Logs\*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 5
```

**Scheduled Task status:**
```powershell
Get-ScheduledTask -TaskName "EdmondsCollege-FirstLogonSetup" |
    Get-ScheduledTaskInfo |
    Select-Object LastRunTime, LastTaskResult, NextRunTime
```
> `LastTaskResult = 0` = success. Any other value -- check logs.

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| AppData is DIR not JUNCTION | AppData locked during provisioning | Ensure user logged out, re-run `New-UserSetup.ps1` |
| AppData rename access denied | Process still holding lock | Increase `Start-Sleep` in `Invoke-ProvisionUser` |
| Script runs as CIS0792$ | Machine account triggering task | Fixed via WMI user detection -- physical logon preferred for testing |
| Quick Access not pinned | Task fired before shell ready | Log off and back in |
| nvs not found in Git Bash | nvs.sh not sourced | Check `.bash_profile` contains nvs.sh source line |
| nvs link fails | `linkToSystem` not set | Edit `golden25-AppData\Local\nvs\settings.json` -- add `"linkToSystem": false` |
| node not found | nvs\default missing | Run `nvs link 24.16.0` as user |
| VS Code context menu missing | Registry not written | Re-run `New-UserSetup.ps1` for user |
| File associations not applied | Windows override | Verify NTUSER.DAT hive write succeeded in log |
| Log file empty | SYSTEM write access | Run `icacls C:\Logs /grant SYSTEM:F` |
| Git Bash menu missing | Wrong install path | Verify `C:\Program Files\Git\git-bash.exe` exists |
| Defender slowing scans | No exclusion set | Run `Add-MpPreference -ExclusionPath "C:\Users\Public\bin"` |

### Registry flags reference

| Key | Name | Value | Meaning |
|-----|------|-------|---------|
| `EdmondsCollege\FirstLogon` | `<username>` | `done` | User fully provisioned |
| `EdmondsCollege\FirstLogon` | `<username>_quickaccess` | `done` | Quick Access pinned |
| `EdmondsCollege\FirstLogon` | `PowerSettings` | `done` | Power settings applied |
| `EdmondsCollege\FirstLogon` | `GitBash` | `done` | Git Bash menu written |
| `EdmondsCollege\BaseImage` | `Prepared` | `done` | Base image prep complete |

---

*Edmonds College CIS Department -- 2026-05-30*
