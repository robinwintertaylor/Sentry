<#
.SYNOPSIS
  Monthly posture collection for Sentry's hardening report.
.NOTES
  Read-only. Register as a separate monthly Scheduled Task.
#>
[CmdletBinding()]
param([string]$OutDir = "$env:ProgramData\Sentry\monthly", [int]$RetentionMonths = 24)

$ErrorActionPreference='Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$stamp = Get-Date -Format 'yyyyMM'
$dir = Join-Path $OutDir $stamp
New-Item -ItemType Directory -Force -Path $dir | Out-Null

& (Join-Path $here 'Get-HardeningPosture.ps1')  -OutPath (Join-Path $dir 'hardening-posture.json')
& (Join-Path $here 'Get-SecuritySnapshot.ps1')  -OutPath (Join-Path $dir 'security-snapshot.json')
& (Join-Path $here 'Get-PersistenceCheck.ps1')  -OutPath (Join-Path $dir 'persistence.json')

# 30-day rollup so the report reflects the month, not the last hour
$since = (Get-Date).AddDays(-30)
$hourly = Get-ChildItem "$env:ProgramData\Sentry\collections" -Directory -EA SilentlyContinue |
          Where-Object CreationTime -gt $since
[ordered]@{
  generated=(Get-Date).ToString('o'); period=$stamp
  hourlyRunsInPeriod=$hourly.Count
  expectedRuns=720
  coveragePercent=[math]::Round(($hourly.Count/720)*100,1)
} | ConvertTo-Json | Out-File (Join-Path $dir 'coverage.json') -Encoding utf8

Get-ChildItem $OutDir -Directory -EA SilentlyContinue |
  Where-Object { $_.CreationTime -lt (Get-Date).AddMonths(-$RetentionMonths) } |
  Remove-Item -Recurse -Force -EA SilentlyContinue

Write-Output "monthly posture written: $dir"
