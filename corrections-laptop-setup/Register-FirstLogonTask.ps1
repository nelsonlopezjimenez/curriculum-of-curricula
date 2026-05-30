# Register-FirstLogonTask.ps1
# Run once as Administrator during base image preparation
# Registers a Scheduled Task that fires Setup-FirstLogon.ps1 on every user logon
# Task is self-managing — script skips users who already ran it via registry flag

#Requires -RunAsAdministrator

$TaskName   = "EdmondsCollege-FirstLogonSetup"
$ScriptPath = "C:\Users\Public\bin\Setup-FirstLogon.ps1"

# Verify script exists
if (-not (Test-Path $ScriptPath)) {
    Write-Host "ERROR: Setup-FirstLogon.ps1 not found at $ScriptPath" -ForegroundColor Red
    exit 1
}

# Remove existing task if present
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Existing task removed." -ForegroundColor Yellow
}

# Define task components
$action   = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File `"$ScriptPath`""

$trigger  = New-ScheduledTaskTrigger -AtLogOn

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
    -MultipleInstances IgnoreNew

$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

# Register task
Register-ScheduledTask `
    -TaskName  $TaskName `
    -Action    $action `
    -Trigger   $trigger `
    -Settings  $settings `
    -Principal $principal `
    -Description "Edmonds College -- First logon profile setup. Self-skips after first run per user." `
    -Force

Write-Host "Scheduled Task registered: $TaskName" -ForegroundColor Green
Write-Host "Fires: At every user logon, runs as SYSTEM" -ForegroundColor Cyan
Write-Host "Script: $ScriptPath" -ForegroundColor Cyan
