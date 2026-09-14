<#
.SYNOPSIS
  PowerShell script-block and module events, with decoded -EncodedCommand.
.NOTES
  Read-only. Requires script block logging (see SETUP-SENTRY.md step 2).
#>
[CmdletBinding()]
param([int]$Hours = 1, [string]$OutPath)

$ErrorActionPreference = 'SilentlyContinue'
$since = (Get-Date).AddHours(-$Hours)
$blocks = @()

foreach ($e in (Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-PowerShell/Operational';Id=4104;StartTime=$since} -EA SilentlyContinue)) {
  $x = ([xml]$e.ToXml()).Event.EventData.Data
  $g = { param($n) ($x | Where-Object Name -eq $n).'#text' }
  $text = & $g 'ScriptBlockText'

  # Decode base64 payloads so the agent reads intent, not obfuscation.
  $decoded = $null
  if ($text -match '(?:-enc(?:odedcommand)?)\s+([A-Za-z0-9+/=]{40,})') {
    try { $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($matches[1])) } catch {}
  }

  # Crude obfuscation score — high ratio of non-alphanumerics, or heavy concat.
  $nonAlpha = ([regex]::Matches($text,'[^a-zA-Z0-9\s]')).Count
  $ratio = if ($text.Length) { [math]::Round($nonAlpha / $text.Length, 2) } else { 0 }

  $blocks += [ordered]@{
    time=$e.TimeCreated.ToString('o'); level="$($e.LevelDisplayName)"
    scriptPath=(& $g 'Path'); text=$text; decodedCommand=$decoded
    obfuscationRatio=$ratio
    flags=@(
      if ($decoded) { 'encoded-command' }
      if ($ratio -gt 0.35) { 'high-obfuscation' }
      if ($text -match 'DownloadString|DownloadFile|Invoke-WebRequest|Net\.WebClient') { 'network-fetch' }
      if ($text -match 'Invoke-Expression|iex\b|\.Invoke\(') { 'dynamic-execution' }
      if ($text -match 'Add-MpPreference|Set-MpPreference|DisableRealtimeMonitoring') { 'av-tampering' }
      if ($text -match 'New-ScheduledTask|Register-ScheduledTask|CurrentVersion\\Run') { 'persistence' }
      if ($text -match 'lsass|MiniDump|comsvcs\.dll') { 'credential-access' }
      if ($text -match 'Set-MpPreference.*Exclusion|Add-MpPreference.*Exclusion') { 'av-exclusion-added' }
    )
  }
}

# AMSI blocks are worth surfacing loudly — something was caught mid-flight.
$amsi = @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational';Id=1116,1117;StartTime=$since} -EA SilentlyContinue |
  ForEach-Object { [ordered]@{ time=$_.TimeCreated.ToString('o'); id=$_.Id; message=($_.Message -split "`n")[0] }})

$out = [ordered]@{
  collected=(Get-Date).ToString('o'); windowHours=$Hours
  scriptBlockLoggingEnabled=[bool]$blocks.Count
  flagged=@($blocks | Where-Object { $_.flags.Count -gt 0 })
  defenderDetections=$amsi
  totalBlocks=$blocks.Count
}
$json = $out | ConvertTo-Json -Depth 6
if ($OutPath) { $json | Out-File -FilePath $OutPath -Encoding utf8 } else { $json }
