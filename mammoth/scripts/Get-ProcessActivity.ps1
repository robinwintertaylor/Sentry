<#
.SYNOPSIS
  Process creations in a window, with command lines, parents and signatures.
.NOTES
  Read-only. Prefers Sysmon Event 1; falls back to Security 4688.
#>
[CmdletBinding()]
param([int]$Hours = 1, [string]$OutPath)

$ErrorActionPreference = 'SilentlyContinue'
$since = (Get-Date).AddHours(-$Hours)
$events = @()

$sysmon = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Sysmon/Operational';Id=1;StartTime=$since} -EA SilentlyContinue
if ($sysmon) {
  foreach ($e in $sysmon) {
    $x = ([xml]$e.ToXml()).Event.EventData.Data
    $g = { param($n) ($x | Where-Object Name -eq $n).'#text' }
    $events += [ordered]@{
      time=$e.TimeCreated.ToString('o'); source='sysmon'
      image=(& $g 'Image'); cmdline=(& $g 'CommandLine')
      parent=(& $g 'ParentImage'); parentCmd=(& $g 'ParentCommandLine')
      user=(& $g 'User'); hash=(& $g 'Hashes'); signed=(& $g 'Signed'); signer=(& $g 'Signature')
    }
  }
} else {
  foreach ($e in (Get-WinEvent -FilterHashtable @{LogName='Security';Id=4688;StartTime=$since} -EA SilentlyContinue)) {
    $x = ([xml]$e.ToXml()).Event.EventData.Data
    $g = { param($n) ($x | Where-Object Name -eq $n).'#text' }
    $events += [ordered]@{
      time=$e.TimeCreated.ToString('o'); source='security-4688'
      image=(& $g 'NewProcessName'); cmdline=(& $g 'CommandLine')
      parent=(& $g 'ParentProcessName'); user=(& $g 'SubjectUserName')
    }
  }
}

# Signature + path risk annotation. Suspicion is contextual, so we flag
# rather than judge — the agent reasons about the combination.
$userWritable = @($env:TEMP, $env:APPDATA, "$env:USERPROFILE\Downloads", 'C:\Users\Public', $env:ProgramData)
$interpreters = 'powershell|pwsh|cmd\.exe|wscript|cscript|mshta|rundll32|regsvr32|certutil|bitsadmin|curl\.exe|wget\.exe'
$officeParents = 'winword|excel|powerpnt|outlook|acrord32|msaccess'

foreach ($e in $events) {
  $img = $e.image
  if ($img -and (Test-Path $img)) {
    if (-not $e.signed) {
      $sig = Get-AuthenticodeSignature $img -EA SilentlyContinue
      $e.signed = ($sig.Status -eq 'Valid'); $e.signer = $sig.SignerCertificate.Subject
    }
  }
  $e.flags = @(
    if ($userWritable | Where-Object { $img -like "$_*" }) { 'user-writable-path' }
    if ($img -match $interpreters) { 'interpreter' }
    if ($e.parent -match $officeParents -and $img -match $interpreters) { 'office-spawned-interpreter' }
    if ($e.cmdline -match '-enc|-EncodedCommand|FromBase64String') { 'encoded-command' }
    if ($e.cmdline -match 'DownloadString|DownloadFile|Invoke-WebRequest|iwr |curl |Invoke-Expression|iex ') { 'download-or-exec' }
    if ($e.cmdline -match '-w hidden|-WindowStyle Hidden|-nop|-NoProfile') { 'hidden-or-noprofile' }
    if ($e.cmdline -match 'vssadmin|wbadmin|bcdedit') { 'backup-or-boot-tampering' }
    if ($e.signed -eq $false) { 'unsigned' }
  )
}

$out = [ordered]@{
  collected=(Get-Date).ToString('o'); windowHours=$Hours
  source = if ($sysmon) {'sysmon'} else {'security-4688'}
  totalEvents=$events.Count
  flagged=@($events | Where-Object { $_.flags.Count -gt 0 })
  allEvents=$events
}
$json = $out | ConvertTo-Json -Depth 6
if ($OutPath) { $json | Out-File -FilePath $OutPath -Encoding utf8 } else { $json }
