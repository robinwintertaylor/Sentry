<#
.SYNOPSIS
  Outbound connections by process, listening ports, and Sysmon DNS if present.
.NOTES
  Read-only.
#>
[CmdletBinding()]
param([int]$Hours = 1, [string]$OutPath)

$ErrorActionPreference = 'SilentlyContinue'
$procs = @{}; foreach ($p in Get-Process) { $procs[$p.Id] = $p }

$conns = @(Get-NetTCPConnection -State Established -EA SilentlyContinue | ForEach-Object {
  $pr = $procs[[int]$_.OwningProcess]
  [ordered]@{
    localPort=$_.LocalPort; remote=$_.RemoteAddress; remotePort=$_.RemotePort
    process=$pr.ProcessName; path=$pr.Path; pid=$_.OwningProcess
  }} | Where-Object { $_.remote -notmatch '^(127\.|::1|0\.0\.0\.0)' })

$listening = @(Get-NetTCPConnection -State Listen -EA SilentlyContinue | ForEach-Object {
  $pr = $procs[[int]$_.OwningProcess]
  [ordered]@{ port=$_.LocalPort; address=$_.LocalAddress; process=$pr.ProcessName; path=$pr.Path }} |
  Where-Object { $_.address -notmatch '^(127\.|::1)' })

$dns = @()
if (Get-Service -Name 'Sysmon*' -EA SilentlyContinue) {
  $since = (Get-Date).AddHours(-$Hours)
  $dns = @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Sysmon/Operational';Id=22;StartTime=$since} -EA SilentlyContinue |
    ForEach-Object {
      $x=([xml]$_.ToXml()).Event.EventData.Data; $g={param($n)($x|Where-Object Name -eq $n).'#text'}
      [ordered]@{ time=$_.TimeCreated.ToString('o'); query=(& $g 'QueryName'); image=(& $g 'Image') }})
}

# Flag interpreters holding network connections — rarely legitimate.
$interpreters = 'powershell|pwsh|cmd|wscript|cscript|mshta|rundll32|regsvr32|certutil'
$out = [ordered]@{
  collected=(Get-Date).ToString('o')
  interpreterConnections=@($conns | Where-Object { $_.process -match $interpreters })
  unusualListeners=@($listening | Where-Object { $_.process -match $interpreters })
  establishedConnections=$conns; listeningPorts=$listening; dnsQueries=$dns
}
$json = $out | ConvertTo-Json -Depth 6
if ($OutPath) { $json | Out-File -FilePath $OutPath -Encoding utf8 } else { $json }
