# Prepare-BaseImage.ps1
# Run ONCE as Administrator during base image preparation
# Must be run from C:\Users\Public\bin\ where all scripts are located

#Requires -RunAsAdministrator

# ---------------------------------------------------------------
# CONFIG
# ---------------------------------------------------------------
$PublicBin   = "C:\Users\Public\bin"
$LogPath     = "C:\Logs\PrepareBaseImage_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".log"
$RegFlagPath = "HKLM:\SOFTWARE\EdmondsCollege\BaseImage"

New-Item -ItemType Directory "C:\Logs" -Force | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " [$Level] " + $Message
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "OK"    { "Green" }
        default { "Cyan" }
    }
    Write-Host $entry -ForegroundColor $color
    $entry | Out-File -Append $LogPath
}

# ---------------------------------------------------------------
# CHECK -- Already prepared?
# ---------------------------------------------------------------
$prepared = (Get-ItemProperty -Path $RegFlagPath -Name "Prepared" -ErrorAction SilentlyContinue).Prepared
if ($prepared -eq "done") {
    Write-Log "Base image already prepared -- exiting." "WARN"
    Write-Log "To re-run, delete registry key: $RegFlagPath"
    exit 0
}

Write-Log "====== Base Image Preparation Started ======"

# ---------------------------------------------------------------
# STEP 1 -- Verify required scripts exist
# ---------------------------------------------------------------
Write-Log "Step 1 -- Verifying required scripts..."
$requiredScripts = @(
    "$PublicBin\Setup-FirstLogon.ps1",
    "$PublicBin\Register-FirstLogonTask.ps1",
    "$PublicBin\New-UserSetup.ps1"
)

$missing = $false
foreach ($script in $requiredScripts) {
    if (Test-Path $script) {
        Write-Log ("Found: " + $script) "OK"
    } else {
        Write-Log ("Missing: " + $script) "ERROR"
        $missing = $true
    }
}

if ($missing) {
    Write-Log "Missing scripts -- copy all scripts to $PublicBin first." "ERROR"
    exit 1
}

# ---------------------------------------------------------------
# STEP 2 -- Verify Public\bin folder structure
# ---------------------------------------------------------------
Write-Log "Step 2 -- Verifying folder structure..."
$requiredFolders = @(
    "$PublicBin\golden25-AppData",
    "$PublicBin\vscode",
    "$PublicBin\dotfiles"
)

foreach ($folder in $requiredFolders) {
    if (Test-Path $folder) {
        Write-Log ("Found: " + $folder) "OK"
    } else {
        Write-Log ("Missing: " + $folder) "WARN"
        New-Item -ItemType Directory $folder -Force | Out-Null
        Write-Log ("Created: " + $folder) "OK"
    }
}

# ---------------------------------------------------------------
# STEP 3 -- Power settings
# ---------------------------------------------------------------
Write-Log "Step 3 -- Applying power settings..."
powercfg /hibernate off
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /h off
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f | Out-Null
Write-Log "Power settings applied." "OK"

# ---------------------------------------------------------------
# STEP 4 -- Windows Defender exclusions
# ---------------------------------------------------------------
Write-Log "Step 4 -- Adding Defender exclusions..."
$exclusions = @(
    "C:\Users\Public\bin",
    "C:\Users\Public\bin\golden25-AppData",
    "C:\Logs"
)
foreach ($path in $exclusions) {
    Add-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
    Write-Log ("Exclusion added: " + $path) "OK"
}

# ---------------------------------------------------------------
# STEP 5 -- nvs settings.json linkToSystem
# ---------------------------------------------------------------
Write-Log "Step 5 -- Configuring nvs settings.json..."
$nvsSettings = "$PublicBin\golden25-AppData\Local\nvs\settings.json"

if (Test-Path $nvsSettings) {
    $settings = Get-Content $nvsSettings -Raw | ConvertFrom-Json
    $settings | Add-Member -NotePropertyName "linkToSystem" -NotePropertyValue $false -Force
    $settings | ConvertTo-Json -Depth 10 | Set-Content $nvsSettings
    Write-Log "nvs settings.json updated -- linkToSystem: false" "OK"
} else {
    Write-Log "nvs settings.json not found -- skipping." "WARN"
}

# ---------------------------------------------------------------
# STEP 6 -- Git Bash context menu (HKLM machine-wide)
# ---------------------------------------------------------------
Write-Log "Step 6 -- Writing Git Bash context menu..."
$gitBashPath = "C:\Program Files\Git\git-bash.exe"

if (Test-Path $gitBashPath) {
    cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\shell\git_bash`" /ve /d `"Open Git Bash here`" /f" | Out-Null
    cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\shell\git_bash`" /v Icon /d `"$gitBashPath`" /f" | Out-Null
    cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\shell\git_bash\command`" /ve /d `"$gitBashPath --cd=%1`" /f" | Out-Null
    cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\Background\shell\git_bash`" /ve /d `"Open Git Bash here`" /f" | Out-Null
    cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\Background\shell\git_bash`" /v Icon /d `"$gitBashPath`" /f" | Out-Null
    cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\Background\shell\git_bash\command`" /ve /d `"$gitBashPath --cd=%V`" /f" | Out-Null
    Write-Log "Git Bash context menu written." "OK"
} else {
    Write-Log "Git Bash not found -- skipping." "WARN"
}

# ---------------------------------------------------------------
# STEP 7 -- Register Scheduled Task
# ---------------------------------------------------------------
Write-Log "Step 7 -- Registering Scheduled Task..."
try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    & "$PublicBin\Register-FirstLogonTask.ps1"
    Write-Log "Scheduled Task registered." "OK"
} catch {
    Write-Log ("Failed to register Scheduled Task: " + $_) "ERROR"
}

# ---------------------------------------------------------------
# STEP 8 -- Provision Default profile
# ---------------------------------------------------------------
Write-Log "Step 8 -- Provisioning Default profile..."
try {
    & "$PublicBin\New-UserSetup.ps1"
    Write-Log "Default profile provisioned." "OK"
} catch {
    Write-Log ("Failed to provision Default profile: " + $_) "ERROR"
}

# ---------------------------------------------------------------
# DONE -- Set flag
# ---------------------------------------------------------------
New-Item -Path $RegFlagPath -Force | Out-Null
Set-ItemProperty -Path $RegFlagPath -Name "Prepared" -Value "done"
Set-ItemProperty -Path $RegFlagPath -Name "PreparedDate" -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Write-Log "====== Base Image Preparation Complete ======"
Write-Log "Log saved to: $LogPath"
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Green
Write-Host "  1. Verify all junctions in C:\Users\Default" -ForegroundColor Cyan
Write-Host "  2. Test with a new user account" -ForegroundColor Cyan
Write-Host "  3. Image the machine" -ForegroundColor Cyan
