<#
.SYNOPSIS
  Hourly wrapper: runs all five collectors, writes JSON, prunes old output.
.DESCRIPTION
  Register as a Scheduled Task under the low-privilege sentry account.
  This is the ONLY script the scheduler runs. Read-only throughout.
#>
[CmdletBinding()]
param(
  [string]$OutDir = "$env:ProgramData\Sentry\collections",
  [int]$Hours = 1,
  [int]$RetentionDays = 30
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$dir = Join-Path $OutDir $stamp
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$jobs = @(
  @{ n='security-snapshot'; s='Get-SecuritySnapshot.ps1';  a=@{} }
  @{ n='process-activity';  s='Get-ProcessActivity.ps1';   a=@{Hours=$Hours} }
  @{ n='script-activity';   s='Get-ScriptActivity.ps1';    a=@{Hours=$Hours} }
  @{ n='persistence';       s='Get-PersistenceCheck.ps1';  a=@{} }
  @{ n='network-activity';  s='Get-NetworkActivity.ps1';   a=@{Hours=$Hours} }
)

$status = @()
foreach ($j in $jobs) {
  $out = Join-Path $dir "$($j.n).json"
  try {
    & (Join-Path $here $j.s) @($j.a) -OutPath $out
    $status += [ordered]@{ collector=$j.n; ok=(Test-Path $out); error=$null }
  } catch {
    # A failed collector must be visible. Silence from a broken script
    # looks exactly like silence from a clean machine.
    $status += [ordered]@{ collector=$j.n; ok=$false; error="$_" }
  }
}

[ordered]@{
  collected=(Get-Date).ToString('o'); host=$env:COMPUTERNAME
  windowHours=$Hours; collectors=$status
} | ConvertTo-Json -Depth 5 | Out-File (Join-Path $dir 'manifest.json') -Encoding utf8

# prune
Get-ChildItem $OutDir -Directory -EA SilentlyContinue |
  Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-$RetentionDays) } |
  Remove-Item -Recurse -Force -EA SilentlyContinue

Write-Output "collection complete: $dir"
