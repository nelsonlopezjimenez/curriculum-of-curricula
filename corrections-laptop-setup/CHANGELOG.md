# CHANGELOG — Windows User Provisioning Scripts
**Project:** Edmonds College / MCC Domain-Joined Workstation Automation  
**Date:** 2026-05-30

---

## Summary of Scripts

| Script | Purpose |
|--------|---------|
| `New-UserSetup.ps1` | Admin runs after user creation -- provisions profile, junctions, registry |
| `Setup-FirstLogon.ps1` | Fires at first logon via Scheduled Task -- Quick Access pins only |
| `Register-FirstLogonTask.ps1` | Registers Scheduled Task once during image prep |
| `Create-AppDataJunction.ps1` | Standalone manual junction creation (admin utility) |

---

## [2026-05-30] — Session Changes

---

### FIX 1 — AppData rename timing issue
**File:** `New-UserSetup.ps1`  
**Function:** `Invoke-ProvisionUser`

**Problem:**  
Non-interactive logon via `Start-Process` creates the user profile folder but
Windows briefly retains locks on `AppData` even after the process exits.
Attempting to rename `AppData` → `AppData.bak` immediately after process
completion throws:
```
Rename-Item: Access to the path 'C:\Users\<user>\AppData' is denied
IOException at New-UserSetup.ps1:89
```

**Fix:**  
Add `Start-Sleep` delays after profile creation and after `Wait-Process`
to allow Windows to fully release file locks before rename attempt.

```powershell
# After Wait-Process
$proc | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3    # ← ADDED

# After profile folder confirmed created
if (Test-Path $UserProfile) {
    Write-Log "Profile folder created." "OK"
    Start-Sleep -Seconds 5    # ← ADDED
}
```

**Location:** `Invoke-ProvisionUser` function, two places.

---

### FIX 2 — mklink silent failure after rename
**File:** `New-UserSetup.ps1`  
**Function:** `New-Junction`

**Problem:**  
`mklink /J` output was suppressed with `| Out-Null`, making it impossible
to diagnose failures. In some cases the rename completed but the junction
still failed silently, leaving `AppData` as a regular directory instead
of a junction.

**Fix:**  
- Added `Start-Sleep -Seconds 2` between rename and `mklink` call
- Capture and log `mklink` output instead of suppressing it

```powershell
# Before fix
Rename-Item $LinkPath $bak -Force
Write-Log "$Label renamed to .bak"
cmd /c "mklink /J `"$LinkPath`" `"$Target`"" | Out-Null

# After fix
Rename-Item $LinkPath $bak -Force
Write-Log "$Label renamed to .bak"
Start-Sleep -Seconds 2
$result = cmd /c "mklink /J `"$LinkPath`" `"$Target`""
Write-Log ("mklink result: " + $result)
```

**Location:** `New-Junction` function, between closing `}` of rename block
and verification `if` statement.

---

### CHANGE 1 — Setup-FirstLogon.ps1 simplified
**File:** `Setup-FirstLogon.ps1`

**Reason:**  
Original script handled all provisioning at logon time (junctions, registry,
shortcuts, file associations). This caused failures because Windows locks
`AppData` immediately when a user session starts, making junction creation
impossible during an active session.

**Solution:**  
All provisioning moved to `New-UserSetup.ps1` which runs as admin BEFORE
first logon, when AppData is not locked. `Setup-FirstLogon.ps1` now only
handles **Quick Access pins** which require an active shell session.

| Task | Before | After |
|------|--------|-------|
| AppData junction | Setup-FirstLogon | New-UserSetup |
| .vscode junction | Setup-FirstLogon | New-UserSetup |
| Dotfiles junctions | Setup-FirstLogon | New-UserSetup |
| VS Code registry | Setup-FirstLogon | New-UserSetup |
| File associations | Setup-FirstLogon | New-UserSetup |
| Folder options | Setup-FirstLogon | New-UserSetup |
| Desktop shortcuts | Setup-FirstLogon | New-UserSetup |
| Power settings | Setup-FirstLogon | New-UserSetup |
| Git Bash menu | Setup-FirstLogon | New-UserSetup |
| Quick Access pins | Setup-FirstLogon | Setup-FirstLogon ✅ |

---

### CHANGE 2 — New-UserSetup.ps1 architecture
**File:** `New-UserSetup.ps1`

**Reason:**  
Original approach assumed user creation script would call provisioning directly.
Replaced with a **scanner pattern** -- script scans `C:\Users\` and local user
accounts, identifies unprovisioned users, and provisions them in batch.

**Key behaviors:**
- Skips built-in accounts automatically (`Administrator`, `Guest`, `DefaultAccount`, `WDAGUtilityAccount`, `adm`, `Public`, `All Users`)
- Processes `Default` profile (no password needed)
- Prompts for password per unprovisioned user found
- Non-interactive profile generation via `Start-Process` with `-LoadUserProfile`
- Registry written via NTUSER.DAT hive load (no active session needed)
- Provisioned flag per user in `HKLM:\SOFTWARE\EdmondsCollege\FirstLogon`

---

### CHANGE 3 — $actualUser replaces $env:USERNAME
**File:** `Setup-FirstLogon.ps1`

**Problem:**  
Scheduled Task runs as SYSTEM. `$env:USERNAME` returns `CIS0792$`
(machine account) instead of the logged-in user, causing the machine
account skip check to always exit the script.

**Fix:**  
```powershell
# Before -- always returned machine account
$env:USERNAME

# After -- returns actual interactive user
$actualUser = (Get-WmiObject -Class Win32_ComputerSystem).UserName.Split('\')[1]
```

---

### CHANGE 4 — Scheduled Task MultipleInstances Queue
**File:** `Register-FirstLogonTask.ps1`

**Problem:**  
`-MultipleInstances IgnoreNew` caused baobab's logon trigger to be
silently dropped when machine account `CIS0792$` triggered the task
first at the same time.

**Fix:**
```powershell
# Before
-MultipleInstances IgnoreNew

# After
-MultipleInstances Queue
```

**Applied via:** `Set-ScheduledTask` on the running machine (no re-registration needed).

---

## Current Workflow

```
Admin creates user (existing script)
        |
        v
Admin runs New-UserSetup.ps1
  - scans for unprovisioned users
  - generates profile (non-interactive)
  - creates all junctions
  - writes registry via NTUSER.DAT
  - copies shortcuts
        |
        v
User logs in for first time
        |
        v
Setup-FirstLogon.ps1 fires (SYSTEM, Scheduled Task)
  - pins Quick Access folders
  - sets flag, never runs again
        |
        v
User environment fully configured
```

---

## Known Issues / Watch Points

| Issue | Status | Notes |
|-------|--------|-------|
| AppData lock after non-interactive logon | Fixed with Sleep | Monitor timing on slower machines |
| mklink silent failure | Fixed with logging | Check logs if junction missing |
| Machine account triggering task | Fixed with WMI user detection | |
| RDP triggering machine account logon | Mitigated | Physical logon preferred for testing |
| Multiple accounts sharing AppData | By design | One student per laptop -- no conflict |
