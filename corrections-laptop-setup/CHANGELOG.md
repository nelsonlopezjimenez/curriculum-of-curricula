# New-UserSetup.ps1
# Run as Administrator AFTER user creation script has run
# Scans for unprovisioned users, generates profiles, creates junctions
# and configures registry settings via NTUSER.DAT hive

#Requires -RunAsAdministrator

# ---------------------------------------------------------------
# CONFIG
# ---------------------------------------------------------------
$AppDataTarget  = "C:\Users\Public\bin\golden25-AppData"
$VscodeTarget   = "C:\Users\Public\bin\vscode"
$DotfilesTarget = "C:\Users\Public\bin\dotfiles"
$PublicBin      = "C:\Users\Public\bin"
$RegFlagPath    = "HKLM:\SOFTWARE\EdmondsCollege\FirstLogon"
$LogPath        = "C:\Logs\NewUserSetup_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".log"
$GitBashPath    = "C:\Program Files\Git\git-bash.exe"

# Accounts to always skip
$SkipAccounts = @(
    "adm", "Administrator", "Guest", "DefaultAccount",
    "WDAGUtilityAccount", "Public", "All Users"
)

# File associations
$FileAssocExtensions = @(".mp4", ".avi", ".mkv", ".mov", ".webm", ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".pdf")
$FileAssocProgId     = "ChromeHTML"

# ---------------------------------------------------------------
# LOGGING
# ---------------------------------------------------------------
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
# HELPER -- Load/unload NTUSER.DAT hive
# ---------------------------------------------------------------
function Invoke-WithHive {
    param([string]$UserProfile, [string]$Username, [scriptblock]$Action)
    $hiveName = "TempHive_$Username"
    $hivePath = "HKU\$hiveName"
    $ntuser   = "$UserProfile\NTUSER.DAT"

    if (-not (Test-Path $ntuser)) {
        Write-Log "NTUSER.DAT not found for $Username -- skipping registry." "WARN"
        return
    }
    try {
        reg load $hivePath $ntuser 2>$null
        & $Action $hiveName
    } finally {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        reg unload $hivePath 2>$null
    }
}

# ---------------------------------------------------------------
# HELPER -- Create junction safely
# ---------------------------------------------------------------
function New-Junction {
    param([string]$LinkPath, [string]$Target, [string]$Label)

    if (-not (Test-Path $Target)) {
        Write-Log "$Label target not found: $Target" "WARN"
        return
    }
    if (Test-Path $LinkPath) {
        $isJunction = (Get-Item $LinkPath -Force).Attributes -match "ReparsePoint"
        if ($isJunction) {
            Write-Log "$Label junction already exists -- skipping."
            return
        }
        # Rename existing folder as backup
        $bak = $LinkPath + ".bak"
        if (Test-Path $bak) { Remove-Item $bak -Recurse -Force }
        Rename-Item $LinkPath $bak -Force
        Write-Log "$Label renamed to .bak"
    }
    cmd /c "mklink /J `"$LinkPath`" `"$Target`"" | Out-Null
    if ((Get-Item $LinkPath -Force -ErrorAction SilentlyContinue).Attributes -match "ReparsePoint") {
        Write-Log "$Label junction created -> $Target" "OK"
    } else {
        Write-Log "$Label junction creation failed." "ERROR"
    }
}

# ---------------------------------------------------------------
# HELPER -- Provision a single user profile
# ---------------------------------------------------------------
function Invoke-ProvisionUser {
    param([string]$Username, [string]$Password, [bool]$IsDefault = $false)

    Write-Log "--- Provisioning: $Username ---"
    $UserProfile = "C:\Users\$Username"

    # --- Generate profile if not Default and not exists ---
    if (-not $IsDefault -and -not (Test-Path $UserProfile)) {
        Write-Log "Generating profile for $Username via non-interactive logon..."
        try {
            $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
            $cred    = New-Object System.Management.Automation.PSCredential($Username, $secPass)
            $proc    = Start-Process "cmd.exe" `
                -ArgumentList "/c echo profile" `
                -Credential $cred `
                -LoadUserProfile `
                -WindowStyle Hidden `
                -PassThru
            # Wait for profile folder (max 30s)
            $elapsed = 0
            while (-not (Test-Path $UserProfile) -and $elapsed -lt 30) {
                Start-Sleep -Seconds 1
                $elapsed++
            }
            $proc | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
            if (Test-Path $UserProfile) {
                Write-Log "Profile folder created." "OK"
            } else {
                Write-Log "Profile folder not created -- skipping $Username." "ERROR"
                return
            }
        } catch {
            Write-Log ("Failed to generate profile: " + $_) "ERROR"
            return
        }
    } elseif (-not (Test-Path $UserProfile)) {
        Write-Log "Profile not found for $Username -- skipping." "WARN"
        return
    }

    # Wait for AppData
    $appDataPath = "$UserProfile\AppData"
    $elapsed = 0
    while (-not (Test-Path $appDataPath) -and $elapsed -lt 15) {
        Start-Sleep -Seconds 1
        $elapsed++
    }

    # --- Junctions ---
    New-Junction -LinkPath $appDataPath               -Target $AppDataTarget  -Label "AppData"
    New-Junction -LinkPath "$UserProfile\.vscode"     -Target $VscodeTarget   -Label ".vscode"

    $dotfiles = @(".gitconfig", ".npmrc", ".bash_profile", ".bash_history", ".nvs")
    foreach ($dot in $dotfiles) {
        $src = "$DotfilesTarget\$dot"
        if (Test-Path $src) {
            New-Junction -LinkPath "$UserProfile\$dot" -Target $src -Label $dot
        } else {
            Write-Log "$dot not in dotfiles source -- skipping." "WARN"
        }
    }

    # --- Desktop shortcuts ---
    $desktopSrc  = "$PublicBin\dotfiles\Desktop"
    $desktopDest = "$UserProfile\Desktop"
    if (Test-Path $desktopSrc) {
        Get-ChildItem "$desktopSrc\*.lnk" | ForEach-Object {
            $dest = "$desktopDest\$($_.Name)"
            if (-not (Test-Path $dest)) {
                Copy-Item $_.FullName $dest -Force
                Write-Log "Shortcut copied: $($_.Name)"
            }
        }
    } else {
        Write-Log "Desktop shortcuts source not found -- skipping." "WARN"
    }

    # --- Registry via NTUSER.DAT hive ---
    Invoke-WithHive -UserProfile $UserProfile -Username $Username -Action {
        param($hiveName)

        $hive = "HKU\$hiveName"

        # VS Code context menu
        $CodePath = "$UserProfile\AppData\Local\Programs\Microsoft VS Code\Code.exe"
        $vsEntries = @(
            @{ Path = "$hive\Software\Classes\*\shell\VSCode";                            Name = "";     Value = "Open with Code" },
            @{ Path = "$hive\Software\Classes\*\shell\VSCode";                            Name = "Icon"; Value = "`"$CodePath`"" },
            @{ Path = "$hive\Software\Classes\*\shell\VSCode\command";                    Name = "";     Value = "`"$CodePath`" `"%1`"" },
            @{ Path = "$hive\Software\Classes\Directory\shell\VSCode";                    Name = "";     Value = "Open with Code" },
            @{ Path = "$hive\Software\Classes\Directory\shell\VSCode";                    Name = "Icon"; Value = "`"$CodePath`"" },
            @{ Path = "$hive\Software\Classes\Directory\shell\VSCode\command";            Name = "";     Value = "`"$CodePath`" `"%1`"" },
            @{ Path = "$hive\Software\Classes\Directory\Background\shell\VSCode";         Name = "";     Value = "Open with Code" },
            @{ Path = "$hive\Software\Classes\Directory\Background\shell\VSCode";         Name = "Icon"; Value = "`"$CodePath`"" },
            @{ Path = "$hive\Software\Classes\Directory\Background\shell\VSCode\command"; Name = "";     Value = "`"$CodePath`" `"%V`"" }
        )
        foreach ($e in $vsEntries) {
            if ($e.Name -eq "") {
                cmd /c "reg add `"$($e.Path)`" /ve /d `"$($e.Value)`" /f" | Out-Null
            } else {
                cmd /c "reg add `"$($e.Path)`" /v `"$($e.Name)`" /d `"$($e.Value)`" /f" | Out-Null
            }
        }
        Write-Log "VS Code registry entries written." "OK"

        # File associations
        foreach ($ext in $FileAssocExtensions) {
            cmd /c "reg add `"$hive\Software\Classes\$ext`" /ve /d `"$FileAssocProgId`" /f" | Out-Null
        }
        Write-Log "File associations written." "OK"

        # Folder options -- show hidden + protected + extensions
        $advPath = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        reg add $advPath /v Hidden          /t REG_DWORD /d 1 /f | Out-Null
        reg add $advPath /v ShowSuperHidden /t REG_DWORD /d 1 /f | Out-Null
        reg add $advPath /v HideFileExt     /t REG_DWORD /d 0 /f | Out-Null
        Write-Log "Folder options written." "OK"

        # Environment variables
        $envPath = "$hive\Environment"

        # NVS_HOME
        reg add $envPath /v NVS_HOME /t REG_EXPAND_SZ /d "%LOCALAPPDATA%\nvs" /f | Out-Null

        # PATH -- append to existing user PATH
        $existingPath = (reg query $envPath /v PATH 2>$null) -join ""
        if ($existingPath -match "PATH\s+REG\w+\s+(.+)") {
            $currentPath = $matches[1].Trim()
        } else {
            $currentPath = ""
        }
        $pathAdditions = @(
            "%APPDATA%\npm",
            "%LOCALAPPDATA%\nvs",
            "%LOCALAPPDATA%\nvs\default",
            "%USERPROFILE%\bin",
            "%LOCALAPPDATA%\Programs\Ollama"
        )
        foreach ($p in $pathAdditions) {
            if ($currentPath -notlike "*$p*") {
                $currentPath = $currentPath.TrimEnd(";") + ";$p"
            }
        }
        reg add $envPath /v PATH /t REG_EXPAND_SZ /d $currentPath /f | Out-Null
        Write-Log "Environment variables and PATH written." "OK"
    }

    # --- nvs link default version (non-interactive, skip for Default profile) ---
    if (-not $IsDefault -and -not [string]::IsNullOrEmpty($Password)) {
        Write-Log "Setting nvs default node version..."
        try {
            $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
            $cred    = New-Object System.Management.Automation.PSCredential($Username, $secPass)
            Start-Process "cmd.exe" `
                -ArgumentList "/c nvs link 24.16.0" `
                -Credential $cred `
                -LoadUserProfile `
                -WindowStyle Hidden `
                -Wait
            Write-Log "nvs link 24.16.0 completed." "OK"
        } catch {
            Write-Log ("nvs link failed: " + $_) "WARN"
        }
    }

    # --- Set provisioned flag ---
    New-Item -Path $RegFlagPath -Force | Out-Null
    Set-ItemProperty -Path $RegFlagPath -Name $Username -Value "done"
    Set-ItemProperty -Path $RegFlagPath -Name ($Username + "_stage") -Value "2"
    Write-Log "$Username provisioning complete." "OK"
}

# ---------------------------------------------------------------
# MAIN -- Power settings (machine-wide, once)
# ---------------------------------------------------------------
Write-Log "====== New-UserSetup Started ======"

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
    Write-Log "Power settings applied." "OK"
} else {
    Write-Log "Power settings already applied -- skipping."
}

# Git Bash context menu (HKLM, machine-wide, once)
$gitFlag = (Get-ItemProperty -Path $RegFlagPath -Name "GitBash" -ErrorAction SilentlyContinue).GitBash
if ($gitFlag -ne "done" -and (Test-Path $GitBashPath)) {
    Write-Log "Writing Git Bash context menu..."
    cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\shell\git_bash`" /ve /d `"Open Git Bash here`" /f" | Out-Null
    cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\shell\git_bash`" /v Icon /d `"$GitBashPath`" /f" | Out-Null
    cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\shell\git_bash\command`" /ve /d `"$GitBashPath --cd=%1`" /f" | Out-Null
    cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\Background\shell\git_bash`" /ve /d `"Open Git Bash here`" /f" | Out-Null
    cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\Background\shell\git_bash`" /v Icon /d `"$GitBashPath`" /f" | Out-Null
    cmd /c "reg add `"HKLM\SOFTWARE\Classes\Directory\Background\shell\git_bash\command`" /ve /d `"$GitBashPath --cd=%V`" /f" | Out-Null
    Set-ItemProperty -Path $RegFlagPath -Name "GitBash" -Value "done"
    Write-Log "Git Bash context menu written." "OK"
} else {
    Write-Log "Git Bash context menu already set or not installed -- skipping."
}

# ---------------------------------------------------------------
# SCAN -- Find unprovisioned users
# ---------------------------------------------------------------
Write-Log "Scanning for unprovisioned users..."

# Get all local users
$allUsers = Get-LocalUser | Where-Object { $SkipAccounts -notcontains $_.Name }

# Also include Default profile
$usersToProcess = @()

foreach ($user in $allUsers) {
    $profilePath = "C:\Users\" + $user.Name
    $flag        = (Get-ItemProperty -Path $RegFlagPath -Name $user.Name -ErrorAction SilentlyContinue).($user.Name)

    if ($flag -eq "done") {
        Write-Log "$($user.Name) -- already provisioned, skipping."
        continue
    }
    $usersToProcess += [PSCustomObject]@{ Name = $user.Name; IsDefault = $false }
    Write-Log "$($user.Name) -- needs provisioning."
}

# Check Default profile
$defaultFlag = (Get-ItemProperty -Path $RegFlagPath -Name "Default" -ErrorAction SilentlyContinue).Default
if ($defaultFlag -ne "done") {
    $usersToProcess += [PSCustomObject]@{ Name = "Default"; IsDefault = $true }
    Write-Log "Default -- needs provisioning."
}

if ($usersToProcess.Count -eq 0) {
    Write-Log "No users need provisioning -- all done." "OK"
    exit 0
}

Write-Log ("Found " + $usersToProcess.Count + " user(s) to provision.")

# ---------------------------------------------------------------
# PROVISION each user
# ---------------------------------------------------------------
foreach ($u in $usersToProcess) {
    if ($u.IsDefault) {
        Invoke-ProvisionUser -Username "Default" -Password "" -IsDefault $true
    } else {
        $pw = Read-Host ("Enter password for " + $u.Name)
        Invoke-ProvisionUser -Username $u.Name -Password $pw -IsDefault $false
    }
}

Write-Log "====== New-UserSetup Complete ======"
Write-Log "Log saved to: $LogPath"


 C:\Users\gator> Get-ChildItem "C:\Users\Public\bin" -Directory | ForEach-Object {
>>     $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
>>         Measure-Object -Property Length -Sum).Sum
>>     [PSCustomObject]@{Folder=$_.Name; Size_GB=[math]::Round($size/1GB,2)}
>> } | Sort-Object Size_GB -Descending

Folder           Size_GB
------           -------
golden25-AppData   14.43
dotfiles            1.95
vscode              1.37
Desktop                0

C:\Users\gator> Get-ChildItem "C:\Users\Public\bin" -Directory | ForEach-Object {
>>     $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
>>         Measure-Object -Property Length -Sum).Sum
>>     [PSCustomObject]@{
>>         Folder   = $_.Name
>>         Size_GB  = [math]::Round($size/1GB, 2)
>>         Size_MB  = [math]::Round($size/1MB, 0)
>>         Files    = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
>>     }
>> } | Sort-Object Size_GB -Descending | Format-Table -AutoSize

Folder           Size_GB Size_MB  Files
------           ------- -------  -----
golden25-AppData   14.43   14772 258733
dotfiles            1.95    2002  53714
vscode              1.37    1403  67263
Desktop                0       0     10


PS C:\Users\gator> # First level -- top 10 largest subfolders in golden25-AppData\Local
PS C:\Users\gator> $localAppData = "C:\Users\Public\bin\golden25-AppData\Local"
PS C:\Users\gator>
PS C:\Users\gator> Write-Host "`n=== TOP 10 -- First Level ===" -ForegroundColor Green

=== TOP 10 -- First Level ===
PS C:\Users\gator> $firstLevel = Get-ChildItem $localAppData -Directory | ForEach-Object {
>>     $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
>>         Measure-Object -Property Length -Sum).Sum
>>     [PSCustomObject]@{
>>         Folder  = $_.Name
>>         Size_GB = [math]::Round($size/1GB, 2)
>>         Size_MB = [math]::Round($size/1MB, 0)
>>         Files   = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
>>     }
>> } | Sort-Object Size_GB -Descending | Select-Object -First 10
PS C:\Users\gator>
PS C:\Users\gator> $firstLevel | Format-Table -AutoSize

Folder        Size_GB Size_MB  Files
------        ------- -------  -----
Google           1.98    2022  11228
Programs         1.86    1907   8369
nvs              1.44    1471  64271
pnpm             1.35    1378 131369
Vivaldi          1.15    1177   1797
ms-playwright    0.88     898   1481
360Chrome        0.87     888   3297
PowerToys        0.68     695   2473
Postman          0.54     557     78
Packages         0.46     469   2980


PS C:\Users\gator>
PS C:\Users\gator> # Second level -- top 5 subfolders inside each of top 5 first-level folders
PS C:\Users\gator> Write-Host "`n=== TOP 5 SUBFOLDERS inside top 5 folders ===" -ForegroundColor Green

=== TOP 5 SUBFOLDERS inside top 5 folders ===
PS C:\Users\gator> $firstLevel | Select-Object -First 5 | ForEach-Object {
>>     $parentName = $_.Folder
>>     $parentPath = "$localAppData\$parentName"
>>     Write-Host "`n-- $parentName --" -ForegroundColor Yellow
>>
>>     Get-ChildItem $parentPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
>>         $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
>>             Measure-Object -Property Length -Sum).Sum
>>         [PSCustomObject]@{
>>             Subfolder = $_.Name
>>             Size_GB   = [math]::Round($size/1GB, 2)
>>             Size_MB   = [math]::Round($size/1MB, 0)
>>             Files     = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
>>         }
>>     } | Sort-Object Size_GB -Descending | Select-Object -First 5 | Format-Table -AutoSize
>> }

-- Google --

Subfolder     Size_GB Size_MB Files
---------     ------- ------- -----
Chrome           1.51    1544 11215
GoogleUpdater    0.46     472    12
Update           0.01       6     1



-- Programs --

Subfolder         Size_GB Size_MB Files
---------         ------- ------- -----
Opera                0.78     800   379
Microsoft VS Code    0.75     772  6585
Scratch 3            0.33     335  1405
Common                  0       0     0



-- nvs --

Subfolder Size_GB Size_MB Files
--------- ------- ------- -----
node         1.18    1211 64156
cache        0.25     259    28
default       0.1     100  1943
tools           0       0     2
lib             0       0    19



-- pnpm --

Subfolder Size_GB Size_MB  Files
--------- ------- -------  -----
store        1.35    1378 131369



-- Vivaldi --

Subfolder   Size_GB Size_MB Files
---------   ------- ------- -----
Application    0.99    1017  1316
User Data      0.12     127   478
Temp           0.03      33     3


PS C:\Users\gator>


