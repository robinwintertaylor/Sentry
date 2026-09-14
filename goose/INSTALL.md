# Sentry Installation Guide

## Prerequisites
- Windows 10/11
- Goose CLI installed
- Node.js installed (for MCP filesystem server)
- Sysmon downloaded from [Microsoft Sysinternals](https://learn.microsoft.com/en-us/sysinternals/downloads/sysmon)

---

## Step 1: Clone the Repository
**👤 Normal user**
```powershell
git clone https://github.com/your-org/Sentry.git
cd Sentry\goose
```

---

## Step 2: Create Directory Structure
**🔑 Requires Admin**
```powershell
# Run PowerShell as Administrator
mkdir "C:\ProgramData\Sentry\scripts"
mkdir "C:\ProgramData\Sentry\collections"
mkdir "C:\ProgramData\Sentry\monthly"
mkdir "C:\ProgramData\Sentry\sysmon"
```

---

## Step 3: Copy Scripts
**🔑 Requires Admin**
```powershell
Copy-Item ".\scripts\*.ps1" "C:\ProgramData\Sentry\scripts\" -Force
```

---

## Step 4: Create sentry-svc Account
**🔑 Requires Admin**
```powershell
$password = Read-Host -AsSecureString "Enter password for sentry-svc"
$desc = "Sentry monitoring account"
New-LocalUser -Name "sentry-svc" -Password $password -Description $desc -PasswordNeverExpires
Add-LocalGroupMember -Group "Event Log Readers" -Member "sentry-svc"
Add-LocalGroupMember -Group "Performance Log Users" -Member "sentry-svc"
```
Save the password securely, then delete it.

---

## Step 5: Enable Logging
**🔑 Requires Admin**
```powershell
# Process creation auditing with command lines
auditpol /set /subcategory:"Process Creation" /success:enable
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" /v ProcessCreationIncludeCmdLine_Enabled /t REG_DWORD /d 1 /f

# PowerShell script block logging
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" /v EnableScriptBlockLogging /t REG_DWORD /d 1 /f

# Grow Security log to 1 GB
wevtutil sl Security /ms:1073741824
```

---

## Step 6: Install Sysmon
**🔑 Requires Admin**
```powershell
Copy-Item "C:\path\to\Sysmon\Sysmon64.exe" "C:\ProgramData\Sentry\sysmon\"
# Use the config from the repo or create your own
Sysmon64.exe -accepteula -i "C:\ProgramData\Sentry\sysmon\sysmon-config.xml"
```

---

## Step 7: Set Permissions
**🔑 Requires Admin**
```powershell
# Restrict Sentry folder to Admin/SYSTEM/sentry-svc only
$acl = Get-Acl "C:\ProgramData\Sentry"
$acl.SetAccessRuleProtection($true, $false)
$acl | Set-Acl "C:\ProgramData\Sentry"

# Grant sentry-svc read access
$rule = New-Object Security.AccessControl.FileSystemAccessRule("sentry-svc","ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")
$acl.AddAccessRule($rule)
$acl | Set-Acl "C:\ProgramData\Sentry"

# Grant your user read access (for Goose recipes)
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$rule2 = New-Object Security.AccessControl.FileSystemAccessRule($me,"ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")
$acl.AddAccessRule($rule2)
$acl | Set-Acl "C:\ProgramData\Sentry"
```

---

## Step 8: Register Scheduled Tasks
**🔑 Requires Admin**
```powershell
# Hourly collection (runs as sentry-svc)
$hourlyAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\ProgramData\Sentry\scripts\Invoke-SentryWithAlert.ps1`""
$hourlyTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 1)
$hourlyPrincipal = New-ScheduledTaskPrincipal -UserId "sentry-svc" -LogonType Password
Register-ScheduledTask -TaskName "Sentry-HourlyCollection" -Action $hourlyAction -Trigger $hourlyTrigger -Principal $hourlyPrincipal

# Monthly posture (runs as sentry-svc, weekly on Mondays)
$monthlyAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\ProgramData\Sentry\scripts\Invoke-SentryMonthly.ps1`""
$monthlyTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 9am
$monthlyPrincipal = New-ScheduledTaskPrincipal -UserId "sentry-svc" -LogonType Password
Register-ScheduledTask -TaskName "Sentry-MonthlyPosture" -Action $monthlyAction -Trigger $monthlyTrigger -Principal $monthlyPrincipal
```
You'll be prompted for the sentry-svc password when registering.

---

## Step 9: Disable Developer Extension in Goose
**👤 Normal user**
```powershell
# Edit your Goose config to disable the developer extension
# This prevents the security agent from having shell access
notepad "$env:APPDATA\goose\config.yaml"
```
Set `developer: false` in the extensions section.

---

## Step 10: Fix Recipe Config
**👤 Normal user**

Edit both recipe files (`sentry-hourly.recipe.yaml` and `sentry-monthly.recipe.yaml`) and ensure the extension has:
```yaml
extensions:
  - type: stdio
    name: sentry-fs
    cmd: npx
    args:
      - "-y"
      - "@modelcontextprotocol/server-filesystem"
      - "C:\\ProgramData\\Sentry"
    timeout: 120
    cwd: "C:\\ProgramData\\Sentry"   # ← This line is critical
```

---

## Step 11: Import Recipes into Goose Desktop
**👤 Normal user**

In Goose Desktop, import both recipes:
- `sentry-hourly.recipe.yaml`
- `sentry-monthly.recipe.yaml`

Set schedules:
- **Hourly**: Every hour on the hour
- **Monthly**: 30th of each month

---

## Step 12: Test
**👤 Normal user**
```powershell
# Run initial collection (needs admin)
# Then run the recipe
goose run --recipe sentry-hourly.recipe.yaml --no-session --max-turns 20
```

---

## Summary

| Step | What | Admin? |
|------|------|--------|
| 1 | Clone repo | ❌ |
| 2 | Create directories | ✅ |
| 3 | Copy scripts | ✅ |
| 4 | Create sentry-svc account | ✅ |
| 5 | Enable logging | ✅ |
| 6 | Install Sysmon | ✅ |
| 7 | Set permissions | ✅ |
| 8 | Register scheduled tasks | ✅ |
| 9 | Disable developer extension | ❌ |
| 10 | Fix recipe config | ❌ |
| 11 | Import to Goose Desktop | ❌ |
| 12 | Test | ❌ |

**Steps 2–8 must be done in order as Administrator. Steps 9–12 are done as your normal user.**
