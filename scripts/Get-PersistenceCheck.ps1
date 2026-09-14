<#
.SYNOPSIS
  Autostart inventory with a diff against the previous run.
.NOTES
  Read-only. The diff is the point — a new entry matters far more than
  the hundred that were already there.
#>
[CmdletBinding()]
param([string]$StatePath = "$env:ProgramData\Sentry\persistence-baseline.json", [string]$OutPath)

$ErrorActionPreference = 'SilentlyContinue'
$items = @()

$runKeys = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
  'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
  'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
  'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'
)
foreach ($k in $runKeys) {
  $p = Get-ItemProperty $k -EA SilentlyContinue
  if ($p) { foreach ($n in $p.PSObject.Properties.Name) {
    if ($n -notlike 'PS*') { $items += [ordered]@{ type='run-key'; location=$k; name=$n; value="$($p.$n)" } }
  }}
}

foreach ($t in (Get-ScheduledTask -EA SilentlyContinue | Where-Object State -ne 'Disabled')) {
  $act = ($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join '; '
  $items += [ordered]@{ type='scheduled-task'; location=$t.TaskPath; name=$t.TaskName; value=$act.Trim() }
}

foreach ($s in (Get-CimInstance Win32_Service | Where-Object { $_.StartMode -in 'Auto','Automatic' })) {
  $items += [ordered]@{ type='service'; location='services'; name=$s.Name; value=$s.PathName }
}

foreach ($f in @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
                 "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup")) {
  Get-ChildItem $f -EA SilentlyContinue | ForEach-Object {
    $items += [ordered]@{ type='startup-folder'; location=$f; name=$_.Name; value=$_.FullName }
  }
}

foreach ($i in $items) { $i.key = "$($i.type)|$($i.location)|$($i.name)" }

# diff
$new = @(); $removed = @(); $changed = @()
if (Test-Path $StatePath) {
  $prev = Get-Content $StatePath -Raw | ConvertFrom-Json
  $prevMap = @{}; foreach ($p in $prev) { $prevMap[$p.key] = $p.value }
  foreach ($i in $items) {
    if (-not $prevMap.ContainsKey($i.key)) { $new += $i }
    elseif ($prevMap[$i.key] -ne $i.value) { $changed += ([ordered]@{ item=$i; wasValue=$prevMap[$i.key] }) }
  }
  $curKeys = $items.key
  foreach ($k in $prevMap.Keys) { if ($k -notin $curKeys) { $removed += $k } }
  $baselineExisted = $true
} else { $baselineExisted = $false }

New-Item -ItemType Directory -Force -Path (Split-Path $StatePath) | Out-Null
$items | ConvertTo-Json -Depth 4 | Out-File $StatePath -Encoding utf8

$out = [ordered]@{
  collected=(Get-Date).ToString('o'); baselineExisted=$baselineExisted
  totalItems=$items.Count; newSinceLastRun=$new
  changedSinceLastRun=$changed; removedSinceLastRun=$removed
}
$json = $out | ConvertTo-Json -Depth 6
if ($OutPath) { $json | Out-File -FilePath $OutPath -Encoding utf8 } else { $json }
