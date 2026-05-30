# Setup-FirstLogon.ps1
# Runs as SYSTEM via Scheduled Task on first user logon
# Only handles Quick Access pins -- everything else done by New-UserSetup.ps1
# Pre-baked into base image at C:\Users\Public\bin\Setup-FirstLogon.ps1

#Requires -RunAsAdministrator

# ---------------------------------------------------------------
# CONFIG
# ---------------------------------------------------------------
$RegFlagPath = "HKLM:\SOFTWARE\EdmondsCollege\FirstLogon"

# ---------------------------------------------------------------
# GET ACTUAL LOGGED-IN USER (not SYSTEM/machine account)
# ---------------------------------------------------------------
$actualUser = $null
try {
    $loggedInUser = (Get-WmiObject -Class Win32_ComputerSystem).UserName
    if ($loggedInUser -match '\\') {
        $actualUser = $loggedInUser.Split('\')[1]
    } else {
        $actualUser = $loggedInUser
    }
} catch {
    $actualUser = $null
}

# Skip if no interactive user found
if ([string]::IsNullOrEmpty($actualUser)) {
    Write-Host "No interactive user detected -- skipping."
    exit 0
}

# Skip machine accounts (end with $)
if ($actualUser -match '\$$') {
    Write-Host "Machine account detected ($actualUser) -- skipping."
    exit 0
}

# ---------------------------------------------------------------
# LOGGING
# ---------------------------------------------------------------
$LogPath = "C:\Logs\FirstLogon_" + $actualUser + "_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".log"
New-Item -ItemType Directory "C:\Logs" -Force | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " [$Level] [" + $actualUser + "] " + $Message
    Write-Host $entry
    $entry | Out-File -Append $LogPath
}

# ---------------------------------------------------------------
# CHECK FLAG
# ---------------------------------------------------------------
$flagValue = (Get-ItemProperty -Path $RegFlagPath -Name ($actualUser + "_quickaccess") -ErrorAction SilentlyContinue).($actualUser + "_quickaccess")
if ($flagValue -eq "done") {
    Write-Log "Quick Access already configured -- exiting."
    exit 0
}

Write-Log ("====== First Logon Setup Started for " + $actualUser + " ======")

# ---------------------------------------------------------------
# QUICK ACCESS PINS
# ---------------------------------------------------------------
Write-Log "Pinning folders to Quick Access..."
$UserProfile  = "C:\Users\" + $actualUser
$foldersToPin = @(
    "C:\Users\Public",
    $UserProfile,
    ($UserProfile + "\AppData")
)

$shell = New-Object -ComObject Shell.Application
foreach ($folder in $foldersToPin) {
    try {
        if (Test-Path $folder) {
            $shell.Namespace($folder).Self.InvokeVerb("pintohome")
            Write-Log ("Pinned: " + $folder)
        } else {
            Write-Log ("Folder not found, skipping: " + $folder) "WARN"
        }
    } catch {
        Write-Log ("Failed to pin " + $folder + " -- " + $_) "ERROR"
    }
}

# ---------------------------------------------------------------
# SET FLAG
# ---------------------------------------------------------------
New-Item -Path $RegFlagPath -Force | Out-Null
Set-ItemProperty -Path $RegFlagPath -Name ($actualUser + "_quickaccess") -Value "done"
Write-Log "Quick Access flag set."

Write-Log ("====== First Logon Setup Complete for " + $actualUser + " ======")
