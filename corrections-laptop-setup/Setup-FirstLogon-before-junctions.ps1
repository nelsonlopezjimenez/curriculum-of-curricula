# Setup-FirstLogon.ps1
# Runs as SYSTEM via Scheduled Task on first user logon
# Pre-baked into base image at C:\Users\Public\bin\Setup-FirstLogon.ps1

#Requires -RunAsAdministrator

# --- Config ---
$PublicBin      = "C:\Users\Public\bin"
$AppDataTarget  = "$PublicBin\golden25-AppData"
$VscodeTarget   = "$PublicBin\vscode"
$DotfilesTarget = "$PublicBin\dotfiles"
$LogPath        = "C:\Logs\FirstLogon_" + $env:USERNAME + "_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".log"
$RegFlagPath    = "HKLM:\SOFTWARE\EdmondsCollege\FirstLogon"
$ChromePath     = "$AppDataTarget\Local\Google\Chrome\Application\chrome.exe"
$EdgePath       = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
$CodePath       = $env:LOCALAPPDATA + "\Programs\Microsoft VS Code\Code.exe"

# ---------------------------------------------------------------
# isOsn FLAG
# $true  = OSN mode : Power settings + Edge file associations + First logon flag ONLY
# $false = Full mode : All sections run
# ---------------------------------------------------------------
$isOsn = $false

# --- Logging ---
New-Item -ItemType Directory "C:\Logs" -Force | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " [$Level] [" + $env:USERNAME + "] " + $Message
    Write-Host $entry
    $entry | Out-File -Append $LogPath
}

# --- Check first logon flag ---
$flagValue = (Get-ItemProperty -Path $RegFlagPath -Name $env:USERNAME -ErrorAction SilentlyContinue).$env:USERNAME
if ($flagValue -eq "done") {
    Write-Log "First logon already completed for $env:USERNAME -- exiting."
    exit 0
}

# Add right after the first logon flag check
if ($env:USERNAME -match '\$$') {
    Write-Log "Machine account detected -- skipping."
    exit 0
}

Write-Log ("====== First Logon Setup Started for " + $env:USERNAME + " (isOsn=" + $isOsn + ") ======")

# ---------------------------------------------------------------
# 1. POWER SETTINGS -- always runs regardless of isOsn
# ---------------------------------------------------------------
$powerFlag = (Get-ItemProperty -Path $RegFlagPath -Name "PowerSettings" -ErrorAction SilentlyContinue).PowerSettings
if ($powerFlag -ne "done") {
    Write-Log "Applying power settings..."
    powercfg /hibernate off
    powercfg /change standby-timeout-ac 0
    powercfg /change hibernate-timeout-ac 0
    powercfg /h off
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f | Out-Null
    New-Item -Path $RegFlagPath -Force | Out-Null
    Set-ItemProperty -Path $RegFlagPath -Name "PowerSettings" -Value "done"
    Write-Log "Power settings applied."
} else {
    Write-Log "Power settings already applied -- skipping."
}

# ---------------------------------------------------------------
# 2. JUNCTION -- AppData -> Public\bin\golden25-AppData
# ---------------------------------------------------------------
if (-not $isOsn) {
    Write-Log "Creating AppData junction..."
    $appDataPath = "C:\Users\" + $env:USERNAME + "\AppData"

    if (Test-Path $appDataPath) {
        $isJunction = (Get-Item $appDataPath -Force).Attributes -match "ReparsePoint"
        if (-not $isJunction) {
            try {
                Rename-Item $appDataPath ($appDataPath + ".bak") -Force
                Write-Log "Renamed existing AppData to AppData.bak"
                cmd /c "mklink /J `"$appDataPath`" `"$AppDataTarget`""
                Write-Log "AppData junction created"
            } catch {
                Write-Log ("Failed to create AppData junction: " + $_) "ERROR"
            }
        } else {
            Write-Log "AppData junction already exists -- skipping."
        }
    }
} else {
    Write-Log "isOsn=true -- skipping AppData junction."
}

# ---------------------------------------------------------------
# 3. JUNCTION -- .vscode -> Public\bin\vscode
# ---------------------------------------------------------------
if (-not $isOsn) {
    Write-Log "Creating .vscode junction..."
    $vscodePath = "C:\Users\" + $env:USERNAME + "\.vscode"

    if (-not (Test-Path $vscodePath)) {
        try {
            cmd /c "mklink /J `"$vscodePath`" `"$VscodeTarget`""
            Write-Log ".vscode junction created"
        } catch {
            Write-Log ("Failed to create .vscode junction: " + $_) "ERROR"
        }
    } else {
        Write-Log ".vscode already exists -- skipping."
    }
} else {
    Write-Log "isOsn=true -- skipping .vscode junction."
}

# ---------------------------------------------------------------
# 4. JUNCTION -- dotfiles -> Public\bin\dotfiles
# ---------------------------------------------------------------
if (-not $isOsn) {
    Write-Log "Creating dotfiles junctions..."
    $dotfiles = @(".gitconfig", ".npmrc", ".bash_profile", ".bash_history", ".nvs")

    foreach ($dot in $dotfiles) {
        $userPath   = "C:\Users\" + $env:USERNAME + "\" + $dot
        $sourcePath = $DotfilesTarget + "\" + $dot

        if (-not (Test-Path $sourcePath)) {
            Write-Log ("$dot not found in dotfiles source -- skipping.") "WARN"
            continue
        }
        if (Test-Path $userPath) {
            Write-Log "$dot already exists -- skipping."
            continue
        }
        try {
            cmd /c "mklink /J `"$userPath`" `"$sourcePath`""
            Write-Log "$dot junction created"
        } catch {
            Write-Log ("Failed to create $dot junction: " + $_) "ERROR"
        }
    }
} else {
    Write-Log "isOsn=true -- skipping dotfiles junctions."
}

# ---------------------------------------------------------------
# 5. VS CODE REGISTRY -- context menu
# ---------------------------------------------------------------
if (-not $isOsn) {
    Write-Log "Writing VS Code registry entries..."

    $regEntries = @(
        @{ Path = "HKCU\Software\Classes\*\shell\VSCode";                            Name = "";     Value = "Open with Code" },
        @{ Path = "HKCU\Software\Classes\*\shell\VSCode";                            Name = "Icon"; Value = $CodePath },
        @{ Path = "HKCU\Software\Classes\*\shell\VSCode\command";                    Name = "";     Value = "`"" + $CodePath + "`" `"%1`"" },
        @{ Path = "HKCU\Software\Classes\Directory\shell\VSCode";                    Name = "";     Value = "Open with Code" },
        @{ Path = "HKCU\Software\Classes\Directory\shell\VSCode";                    Name = "Icon"; Value = $CodePath },
        @{ Path = "HKCU\Software\Classes\Directory\shell\VSCode\command";            Name = "";     Value = "`"" + $CodePath + "`" `"%1`"" },
        @{ Path = "HKCU\Software\Classes\Directory\Background\shell\VSCode";         Name = "";     Value = "Open with Code" },
        @{ Path = "HKCU\Software\Classes\Directory\Background\shell\VSCode";         Name = "Icon"; Value = $CodePath },
        @{ Path = "HKCU\Software\Classes\Directory\Background\shell\VSCode\command"; Name = "";     Value = "`"" + $CodePath + "`" `"%V`"" }
    )

    foreach ($entry in $regEntries) {
        try {
            if ($entry.Name -eq "") {
                cmd /c "reg add `"$($entry.Path)`" /ve /d `"$($entry.Value)`" /f"
            } else {
                cmd /c "reg add `"$($entry.Path)`" /v `"$($entry.Name)`" /d `"$($entry.Value)`" /f"
            }
            Write-Log ("Registry set: " + $entry.Path + " " + $entry.Name)
        } catch {
            Write-Log ("Registry failed: " + $entry.Path + " -- " + $_) "ERROR"
        }
    }
} else {
    Write-Log "isOsn=true -- skipping VS Code registry."
}

# ---------------------------------------------------------------
# 6. GIT BASH CONTEXT MENU
# ---------------------------------------------------------------
if (-not $isOsn) {
    Write-Log "Writing Git Bash registry entries..."
    $gitBashPath = "C:\Program Files\Git\git-bash.exe"

    if (Test-Path $gitBashPath) {
        cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\shell\git_bash`" /ve /d `"Open Git Bash here`" /f"
        cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\shell\git_bash`" /v Icon /d `"$gitBashPath`" /f"
        cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\shell\git_bash\command`" /ve /d `"$gitBashPath --cd=%1`" /f"
        cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\Background\shell\git_bash`" /ve /d `"Open Git Bash here`" /f"
        cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\Background\shell\git_bash`" /v Icon /d `"$gitBashPath`" /f"
        cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\Background\shell\git_bash\command`" /ve /d `"$gitBashPath --cd=%V`" /f"
        Write-Log "Git Bash context menu entries written."
    } else {
        Write-Log ("Git Bash not found at " + $gitBashPath + " -- skipping.") "WARN"
    }
} else {
    Write-Log "isOsn=true -- skipping Git Bash context menu."
}

# ---------------------------------------------------------------
# 7. DEFAULT FILE ASSOCIATIONS
# isOsn=false = Chrome
# isOsn=true  = Edge
# ---------------------------------------------------------------
Write-Log "Writing file associations..."
$extensions = @(".mp4", ".avi", ".mkv", ".mov", ".webm", ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".pdf")

if ($isOsn) {
    $progId  = "MSEdgeHTM"
    $browser = "Edge"
} else {
    $progId  = "ChromeHTML"
    $browser = "Chrome"
}

foreach ($ext in $extensions) {
    try {
        cmd /c "reg add `"HKCU\Software\Classes\$ext`" /ve /d `"$progId`" /f"
        Write-Log ("File association set: " + $ext + " -> " + $browser)
    } catch {
        Write-Log ("Failed to set association for " + $ext + " -- " + $_) "ERROR"
    }
}

# ---------------------------------------------------------------
# 8. DESKTOP SHORTCUTS
# ---------------------------------------------------------------
if (-not $isOsn) {
    Write-Log "Creating desktop shortcuts..."
    $desktopSource = $PublicBin + "\dotfiles\Desktop"
    $desktopDest   = "C:\Users\" + $env:USERNAME + "\Desktop"

    if (Test-Path $desktopSource) {
        Get-ChildItem ($desktopSource + "\*.lnk") | ForEach-Object {
            $dest = $desktopDest + "\" + $_.Name
            if (-not (Test-Path $dest)) {
                Copy-Item $_.FullName $dest -Force
                Write-Log ("Shortcut copied: " + $_.Name)
            } else {
                Write-Log ("Shortcut already exists: " + $_.Name + " -- skipping.")
            }
        }
    } else {
        Write-Log ("Desktop shortcuts source not found: " + $desktopSource) "WARN"
    }
} else {
    Write-Log "isOsn=true -- skipping desktop shortcuts."
}

# ---------------------------------------------------------------
# 9. SET FIRST LOGON FLAG -- always runs regardless of isOsn
# ---------------------------------------------------------------
New-Item -Path $RegFlagPath -Force | Out-Null
Set-ItemProperty -Path $RegFlagPath -Name $env:USERNAME -Value "done"
Write-Log ("First logon flag set for " + $env:USERNAME)

Write-Log ("====== First Logon Setup Complete for " + $env:USERNAME + " (isOsn=" + $isOsn + ") ======")
