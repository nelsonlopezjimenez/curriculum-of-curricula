# Setup-FirstLogon.ps1 — Annotated Source

> **Canvas Reference Copy** — plain text, not executable.  
> File location on machine: `C:\Users\Public\bin\Setup-FirstLogon.ps1`

---

## Script Source — Line by Line

| Line | Code |
|-----:|------|
| 1 | # Setup-FirstLogon.ps1 |
| 2 | # Runs as SYSTEM via Scheduled Task on first user logon |
| 3 | # Pre-baked into base image at C:\Users\Public\bin\Setup-FirstLogon.ps1 |
| 4 | &nbsp; |
| 5 | #Requires -RunAsAdministrator |
| 6 | &nbsp; |
| 7 | # --- Config --- |
| 8 | $PublicBin      = "C:\Users\Public\bin" |
| 9 | $AppDataTarget  = "$PublicBin\golden25-AppData" |
| 10 | $VscodeTarget   = "$PublicBin\vscode" |
| 11 | $DotfilesTarget = "$PublicBin\dotfiles" |
| 12 | $LogPath        = "C:\Logs\FirstLogon_${env:USERNAME}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log" |
| 13 | $RegFlagPath    = "HKLM:\SOFTWARE\EdmondsCollege\FirstLogon" |
| 14 | $ChromePath     = "$AppDataTarget\Local\Google\Chrome\Application\chrome.exe" |
| 15 | $EdgePath       = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" |
| 16 | $CodePath       = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" |
| 17 | &nbsp; |
| 18 | # --------------------------------------------------------------- |
| 19 | # isOsn FLAG |
| 20 | # $true  → OSN mode : Power settings + Edge file associations + First logon flag ONLY |
| 21 | # $false → Full mode : All sections run |
| 22 | # --------------------------------------------------------------- |
| 23 | $isOsn = $false |
| 24 | &nbsp; |
| 25 | # --- Logging --- |
| 26 | New-Item -ItemType Directory "C:\Logs" -Force \| Out-Null |
| 27 | &nbsp; |
| 28 | function Write-Log { |
| 29 | &nbsp;&nbsp;&nbsp;&nbsp;param([string]$Message, [string]$Level = "INFO") |
| 30 | &nbsp;&nbsp;&nbsp;&nbsp;$entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] [$env:USERNAME] $Message" |
| 31 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Host $entry |
| 32 | &nbsp;&nbsp;&nbsp;&nbsp;$entry \| Out-File -Append $LogPath |
| 33 | } |
| 34 | &nbsp; |
| 35 | # --- Check first logon flag --- |
| 36 | $flagValue = (Get-ItemProperty -Path $RegFlagPath -Name $env:USERNAME -ErrorAction SilentlyContinue).$env:USERNAME |
| 37 | if ($flagValue -eq "done") { |
| 38 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "First logon already completed for $env:USERNAME — exiting." |
| 39 | &nbsp;&nbsp;&nbsp;&nbsp;exit 0 |
| 40 | } |
| 41 | &nbsp; |
| 42 | Write-Log "====== First Logon Setup Started for $env:USERNAME (isOsn=$isOsn) ======" |
| 43 | &nbsp; |
| 44 | # --------------------------------------------------------------- |
| 45 | # 1. POWER SETTINGS — always runs regardless of isOsn |
| 46 | # --------------------------------------------------------------- |
| 47 | $powerFlag = (Get-ItemProperty -Path $RegFlagPath -Name "PowerSettings" -ErrorAction SilentlyContinue).PowerSettings |
| 48 | if ($powerFlag -ne "done") { |
| 49 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Applying power settings..." |
| 50 | &nbsp;&nbsp;&nbsp;&nbsp;powercfg /hibernate off |
| 51 | &nbsp;&nbsp;&nbsp;&nbsp;powercfg /change standby-timeout-ac 0 |
| 52 | &nbsp;&nbsp;&nbsp;&nbsp;powercfg /change hibernate-timeout-ac 0 |
| 53 | &nbsp;&nbsp;&nbsp;&nbsp;powercfg /h off |
| 54 | &nbsp;&nbsp;&nbsp;&nbsp;reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f \| Out-Null |
| 55 | &nbsp;&nbsp;&nbsp;&nbsp;New-Item -Path $RegFlagPath -Force \| Out-Null |
| 56 | &nbsp;&nbsp;&nbsp;&nbsp;Set-ItemProperty -Path $RegFlagPath -Name "PowerSettings" -Value "done" |
| 57 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Power settings applied." |
| 58 | } else { |
| 59 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Power settings already applied — skipping." |
| 60 | } |
| 61 | &nbsp; |
| 62 | # --------------------------------------------------------------- |
| 63 | # 2. JUNCTION — AppData → Public\bin\golden25-AppData |
| 64 | # --------------------------------------------------------------- |
| 65 | if (-not $isOsn) { |
| 66 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Creating AppData junction..." |
| 67 | &nbsp;&nbsp;&nbsp;&nbsp;$appDataPath = "C:\Users\$env:USERNAME\AppData" |
| 68 | &nbsp; |
| 69 | &nbsp;&nbsp;&nbsp;&nbsp;if (Test-Path $appDataPath) { |
| 70 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;$isJunction = (Get-Item $appDataPath -Force).Attributes -match "ReparsePoint" |
| 71 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;if (-not $isJunction) { |
| 72 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;try { |
| 73 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Rename-Item $appDataPath "${appDataPath}.bak" -Force |
| 74 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Renamed existing AppData to AppData.bak" |
| 75 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cmd /c "mklink /J &#96;"$appDataPath&#96;" &#96;"$AppDataTarget&#96;"" \| Out-Null |
| 76 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "AppData junction created → $AppDataTarget" |
| 77 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} catch { |
| 78 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Failed to create AppData junction: $_" "ERROR" |
| 79 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} |
| 80 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} else { |
| 81 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "AppData junction already exists — skipping." |
| 82 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} |
| 83 | &nbsp;&nbsp;&nbsp;&nbsp;} |
| 84 | } else { |
| 85 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "isOsn=true — skipping AppData junction." |
| 86 | } |
| 87 | &nbsp; |
| 88 | # --------------------------------------------------------------- |
| 89 | # 3. JUNCTION — .vscode → Public\bin\vscode |
| 90 | # --------------------------------------------------------------- |
| 91 | if (-not $isOsn) { |
| 92 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Creating .vscode junction..." |
| 93 | &nbsp;&nbsp;&nbsp;&nbsp;$vscodePath = "C:\Users\$env:USERNAME\.vscode" |
| 94 | &nbsp; |
| 95 | &nbsp;&nbsp;&nbsp;&nbsp;if (-not (Test-Path $vscodePath)) { |
| 96 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;try { |
| 97 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cmd /c "mklink /J &#96;"$vscodePath&#96;" &#96;"$VscodeTarget&#96;"" \| Out-Null |
| 98 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log ".vscode junction created → $VscodeTarget" |
| 99 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} catch { |
| 100 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Failed to create .vscode junction: $_" "ERROR" |
| 101 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} |
| 102 | &nbsp;&nbsp;&nbsp;&nbsp;} else { |
| 103 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log ".vscode already exists — skipping." |
| 104 | &nbsp;&nbsp;&nbsp;&nbsp;} |
| 105 | } else { |
| 106 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "isOsn=true — skipping .vscode junction." |
| 107 | } |
| 108 | &nbsp; |
| 109 | # --------------------------------------------------------------- |
| 110 | # 4. JUNCTION — dotfiles → Public\bin\dotfiles |
| 111 | # --------------------------------------------------------------- |
| 112 | if (-not $isOsn) { |
| 113 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Creating dotfiles junctions..." |
| 114 | &nbsp;&nbsp;&nbsp;&nbsp;$dotfiles = @(".gitconfig", ".npmrc", ".bash_profile", ".bash_history", ".nvs") |
| 115 | &nbsp; |
| 116 | &nbsp;&nbsp;&nbsp;&nbsp;foreach ($dot in $dotfiles) { |
| 117 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;$userPath   = "C:\Users\$env:USERNAME\$dot" |
| 118 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;$sourcePath = "$DotfilesTarget\$dot" |
| 119 | &nbsp; |
| 120 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;if (-not (Test-Path $sourcePath)) { |
| 121 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "$dot not found in dotfiles source — skipping." "WARN" |
| 122 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;continue |
| 123 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} |
| 124 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;if (Test-Path $userPath) { |
| 125 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "$dot already exists — skipping." |
| 126 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;continue |
| 127 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} |
| 128 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;try { |
| 129 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cmd /c "mklink /J &#96;"$userPath&#96;" &#96;"$sourcePath&#96;"" \| Out-Null |
| 130 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "$dot junction created → $sourcePath" |
| 131 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} catch { |
| 132 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Failed to create $dot junction: $_" "ERROR" |
| 133 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} |
| 134 | &nbsp;&nbsp;&nbsp;&nbsp;} |
| 135 | } else { |
| 136 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "isOsn=true — skipping dotfiles junctions." |
| 137 | } |
| 138 | &nbsp; |
| 139 | # --------------------------------------------------------------- |
| 140 | # 5. VS CODE REGISTRY — context menu |
| 141 | # --------------------------------------------------------------- |
| 142 | if (-not $isOsn) { |
| 143 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Writing VS Code registry entries..." |
| 144 | &nbsp; |
| 145 | &nbsp;&nbsp;&nbsp;&nbsp;$regEntries = @( |
| 146 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;@{ Path = "HKCU\Software\Classes\*\shell\VSCode";                            Name = "";     Value = "Open with Code" }, |
| 147 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;@{ Path = "HKCU\Software\Classes\*\shell\VSCode";                            Name = "Icon"; Value = $CodePath }, |
| 148 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;@{ Path = "HKCU\Software\Classes\*\shell\VSCode\command";                    Name = "";     Value = "&#96;"$CodePath&#96;" &#96;"%1&#96;"" }, |
| 149 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;@{ Path = "HKCU\Software\Classes\Directory\shell\VSCode";                    Name = "";     Value = "Open with Code" }, |
| 150 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;@{ Path = "HKCU\Software\Classes\Directory\shell\VSCode";                    Name = "Icon"; Value = $CodePath }, |
| 151 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;@{ Path = "HKCU\Software\Classes\Directory\shell\VSCode\command";            Name = "";     Value = "&#96;"$CodePath&#96;" &#96;"%1&#96;"" }, |
| 152 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;@{ Path = "HKCU\Software\Classes\Directory\Background\shell\VSCode";         Name = "";     Value = "Open with Code" }, |
| 153 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;@{ Path = "HKCU\Software\Classes\Directory\Background\shell\VSCode";         Name = "Icon"; Value = $CodePath }, |
| 154 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;@{ Path = "HKCU\Software\Classes\Directory\Background\shell\VSCode\command"; Name = "";     Value = "&#96;"$CodePath&#96;" &#96;"%V&#96;"" } |
| 155 | &nbsp;&nbsp;&nbsp;&nbsp;) |
| 156 | &nbsp; |
| 157 | &nbsp;&nbsp;&nbsp;&nbsp;foreach ($entry in $regEntries) { |
| 158 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;try { |
| 159 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;if ($entry.Name -eq "") { |
| 160 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cmd /c "reg add &#96;"$($entry.Path)&#96;" /ve /d &#96;"$($entry.Value)&#96;" /f" \| Out-Null |
| 161 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} else { |
| 162 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cmd /c "reg add &#96;"$($entry.Path)&#96;" /v &#96;"$($entry.Name)&#96;" /d &#96;"$($entry.Value)&#96;" /f" \| Out-Null |
| 163 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} |
| 164 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Registry set: $($entry.Path) $($entry.Name)" |
| 165 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} catch { |
| 166 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Registry failed: $($entry.Path) — $_" "ERROR" |
| 167 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} |
| 168 | &nbsp;&nbsp;&nbsp;&nbsp;} |
| 169 | } else { |
| 170 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "isOsn=true — skipping VS Code registry." |
| 171 | } |
| 172 | &nbsp; |
| 173 | # --------------------------------------------------------------- |
| 174 | # 6. GIT BASH CONTEXT MENU |
| 175 | # --------------------------------------------------------------- |
| 176 | if (-not $isOsn) { |
| 177 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Writing Git Bash registry entries..." |
| 178 | &nbsp;&nbsp;&nbsp;&nbsp;$gitBashPath = "C:\Program Files\Git\git-bash.exe" |
| 179 | &nbsp; |
| 180 | &nbsp;&nbsp;&nbsp;&nbsp;if (Test-Path $gitBashPath) { |
| 181 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cmd /c "reg add &#96;"HKLM\SOFTWARE\Classes\Directory\shell\git_bash&#96;" /ve /d &#96;"Open Git Bash here&#96;" /f" \| Out-Null |
| 182 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cmd /c "reg add &#96;"HKLM\SOFTWARE\Classes\Directory\shell\git_bash&#96;" /v Icon /d &#96;"$gitBashPath&#96;" /f" \| Out-Null |
| 183 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cmd /c "reg add &#96;"HKLM\SOFTWARE\Classes\Directory\shell\git_bash\command&#96;" /ve /d &#96;"$gitBashPath --cd=%1&#96;" /f" \| Out-Null |
| 184 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cmd /c "reg add &#96;"HKLM\SOFTWARE\Classes\Directory\Background\shell\git_bash&#96;" /ve /d &#96;"Open Git Bash here&#96;" /f" \| Out-Null |
| 185 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cmd /c "reg add &#96;"HKLM\SOFTWARE\Classes\Directory\Background\shell\git_bash&#96;" /v Icon /d &#96;"$gitBashPath&#96;" /f" \| Out-Null |
| 186 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cmd /c "reg add &#96;"HKLM\SOFTWARE\Classes\Directory\Background\shell\git_bash\command&#96;" /ve /d &#96;"$gitBashPath --cd=%V&#96;" /f" \| Out-Null |
| 187 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Git Bash context menu entries written." |
| 188 | &nbsp;&nbsp;&nbsp;&nbsp;} else { |
| 189 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Git Bash not found at $gitBashPath — skipping." "WARN" |
| 190 | &nbsp;&nbsp;&nbsp;&nbsp;} |
| 191 | } else { |
| 192 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "isOsn=true — skipping Git Bash context menu." |
| 193 | } |
| 194 | &nbsp; |
| 195 | # --------------------------------------------------------------- |
| 196 | # 7. DEFAULT FILE ASSOCIATIONS |
| 197 | # isOsn=false → Chrome |
| 198 | # isOsn=true  → Edge |
| 199 | # --------------------------------------------------------------- |
| 200 | Write-Log "Writing file associations..." |
| 201 | $extensions = @(".mp4", ".avi", ".mkv", ".mov", ".webm", ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".pdf") |
| 202 | &nbsp; |
| 203 | if ($isOsn) { |
| 204 | &nbsp;&nbsp;&nbsp;&nbsp;$progId  = "MSEdgeHTM" |
| 205 | &nbsp;&nbsp;&nbsp;&nbsp;$browser = "Edge" |
| 206 | } else { |
| 207 | &nbsp;&nbsp;&nbsp;&nbsp;$progId  = "ChromeHTML" |
| 208 | &nbsp;&nbsp;&nbsp;&nbsp;$browser = "Chrome" |
| 209 | } |
| 210 | &nbsp; |
| 211 | foreach ($ext in $extensions) { |
| 212 | &nbsp;&nbsp;&nbsp;&nbsp;try { |
| 213 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;cmd /c "reg add &#96;"HKCU\Software\Classes\$ext&#96;" /ve /d &#96;"$progId&#96;" /f" \| Out-Null |
| 214 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "File association set: $ext → $browser" |
| 215 | &nbsp;&nbsp;&nbsp;&nbsp;} catch { |
| 216 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Failed to set association for $ext — $_" "ERROR" |
| 217 | &nbsp;&nbsp;&nbsp;&nbsp;} |
| 218 | } |
| 219 | &nbsp; |
| 220 | # --------------------------------------------------------------- |
| 221 | # 8. DESKTOP SHORTCUTS |
| 222 | # --------------------------------------------------------------- |
| 223 | if (-not $isOsn) { |
| 224 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Creating desktop shortcuts..." |
| 225 | &nbsp;&nbsp;&nbsp;&nbsp;$desktopSource = "$PublicBin\dotfiles\Desktop" |
| 226 | &nbsp;&nbsp;&nbsp;&nbsp;$desktopDest   = "C:\Users\$env:USERNAME\Desktop" |
| 227 | &nbsp; |
| 228 | &nbsp;&nbsp;&nbsp;&nbsp;if (Test-Path $desktopSource) { |
| 229 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Get-ChildItem "$desktopSource\*.lnk" \| ForEach-Object { |
| 230 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;$dest = "$desktopDest\$($_.Name)" |
| 231 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;if (-not (Test-Path $dest)) { |
| 232 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Copy-Item $_.FullName $dest -Force |
| 233 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Shortcut copied: $($_.Name)" |
| 234 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} else { |
| 235 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Shortcut already exists: $($_.Name) — skipping." |
| 236 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} |
| 237 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} |
| 238 | &nbsp;&nbsp;&nbsp;&nbsp;} else { |
| 239 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Write-Log "Desktop shortcuts source not found: $desktopSource" "WARN" |
| 240 | &nbsp;&nbsp;&nbsp;&nbsp;} |
| 241 | } else { |
| 242 | &nbsp;&nbsp;&nbsp;&nbsp;Write-Log "isOsn=true — skipping desktop shortcuts." |
| 243 | } |
| 244 | &nbsp; |
| 245 | # --------------------------------------------------------------- |
| 246 | # 9. SET FIRST LOGON FLAG — always runs regardless of isOsn |
| 247 | # --------------------------------------------------------------- |
| 248 | New-Item -Path $RegFlagPath -Force \| Out-Null |
| 249 | Set-ItemProperty -Path $RegFlagPath -Name $env:USERNAME -Value "done" |
| 250 | Write-Log "First logon flag set for $env:USERNAME" |
| 251 | &nbsp; |
| 252 | Write-Log "====== First Logon Setup Complete for $env:USERNAME (isOsn=$isOsn) ======" |

---

## Section Index

| Line | Section |
|-----:|---------|
| 1 | File header / comments |
| 7 | Configuration variables |
| 18 | isOsn flag definition |
| 25 | Logging setup |
| 35 | First logon flag check |
| 44 | Section 1 — Power settings |
| 62 | Section 2 — AppData junction |
| 88 | Section 3 — .vscode junction |
| 109 | Section 4 — Dotfiles junctions |
| 139 | Section 5 — VS Code registry |
| 173 | Section 6 — Git Bash context menu |
| 195 | Section 7 — File associations |
| 220 | Section 8 — Desktop shortcuts |
| 245 | Section 9 — First logon flag |

---

## isOsn Flag Behavior

| Section | isOsn = false (Full) | isOsn = true (OSN) |
|---------|---------------------|--------------------|
| Power settings | ✅ runs | ✅ runs |
| AppData junction | ✅ runs | ❌ skipped |
| .vscode junction | ✅ runs | ❌ skipped |
| Dotfiles junctions | ✅ runs | ❌ skipped |
| VS Code registry | ✅ runs | ❌ skipped |
| Git Bash context menu | ✅ runs | ❌ skipped |
| File associations | ✅ Chrome | ✅ Edge |
| Desktop shortcuts | ✅ runs | ❌ skipped |
| First logon flag | ✅ runs | ✅ runs |
