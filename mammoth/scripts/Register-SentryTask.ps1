<#
.SYNOPSIS
  One-time setup, run as Administrator. Enables the logging Sentry depends on
  and registers the hourly collection task under a low-privilege account.
.PARAMETER SentryUser
  Existing local account the agent runs as. Create it first (see SETUP-SENTRY.md).
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$SentryUser,
      [string]$InstallDir = "$env:ProgramData\Sentry")

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

Write-Host "1. Enabling process-creation auditing with command lines"
auditpol /set /subcategory:"Process Creation" /success:enable | Out-Null
$k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
New-Item -Path $k -Force | Out-Null
Set-ItemProperty -Path $k -Name 'ProcessCreationIncludeCmdLine_Enabled' -Value 1 -Type DWord

Write-Host "2. Enabling PowerShell script block logging"
$k2 = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
New-Item -Path $k2 -Force | Out-Null
Set-ItemProperty -Path $k2 -Name 'EnableScriptBlockLogging' -Value 1 -Type DWord

Write-Host "3. Growing the Security log so an hour of history survives"
wevtutil sl Security /ms:1073741824          # 1 GB
wevtutil sl "Microsoft-Windows-PowerShell/Operational" /ms:268435456

Write-Host "4. Granting $SentryUser read access to the event logs"
# Event Log Readers is the least-privilege way to read the Security log.
Add-LocalGroupMember -Group 'Event Log Readers' -Member $SentryUser -EA SilentlyContinue
# Performance Log Users allows Get-NetTCPConnection process mapping.
Add-LocalGroupMember -Group 'Performance Log Users' -Member $SentryUser -EA SilentlyContinue

Write-Host "5. Creating $InstallDir with restrictive ACLs"
New-Item -ItemType Directory -Force -Path "$InstallDir\collections" | Out-Null
$acl = Get-Acl $InstallDir
$acl.SetAccessRuleProtection($true, $false)
foreach ($id in @('BUILTIN\Administrators','NT AUTHORITY\SYSTEM')) {
  $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($id,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
}
# The agent account may write collections but must NOT be able to delete
# history — evidence integrity matters more than tidiness here.
$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($SentryUser,'CreateFiles,CreateDirectories,ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')))
Set-Acl $InstallDir $acl

Write-Host "6. Registering the hourly task"
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\scripts\Invoke-SentryCollection.ps1`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date `
  -RepetitionInterval (New-TimeSpan -Hours 1)
$set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
Register-ScheduledTask -TaskName 'Sentry-HourlyCollection' -Action $action `
  -Trigger $trigger -Settings $set -User $SentryUser -RunLevel Limited -Force | Out-Null

Write-Host "7. Registering the monthly posture task"
$mAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\scripts\Invoke-SentryMonthly.ps1`""
# First of the month, 09:00. StartWhenAvailable covers a laptop that was off.
$mTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 9am
$mSet = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
Register-ScheduledTask -TaskName 'Sentry-MonthlyPosture' -Action $mAction `
  -Trigger $mTrigger -Settings $mSet -User $SentryUser -RunLevel Limited -Force | Out-Null
New-Item -ItemType Directory -Force -Path "$InstallDir\monthly" | Out-Null

Write-Host ""
Write-Host "Done. Verify with:  Get-ScheduledTask Sentry-*"
Write-Host "Sysmon is strongly recommended but installed separately - see SETUP-SENTRY.md step 3."
