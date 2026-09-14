<#
.SYNOPSIS
  Read-only security posture snapshot. AV-agnostic.
.NOTES
  Reads only. Changes nothing. Safe to run hourly.
#>
[CmdletBinding()]
param([string]$OutPath)

$ErrorActionPreference = 'SilentlyContinue'
$r = [ordered]@{ collected = (Get-Date).ToString('o'); host = $env:COMPUTERNAME }

# --- Installed AV, whatever the vendor -------------------------------------
# SecurityCenter2 is the vendor-neutral registration point. productState is a
# bitfield: byte 2 = enabled, byte 3 = signature freshness.
$av = @()
foreach ($p in Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct) {
  $state = $p.productState
  $av += [ordered]@{
    name            = $p.displayName
    path            = $p.pathToSignedProductExe
    realtimeEnabled = (($state -band 0x1000) -ne 0)
    signaturesFresh = (($state -band 0x10) -eq 0)
    productState    = ('0x{0:X6}' -f $state)
  }
}
$r.antivirus = $av
$r.firewallProduct = @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName FirewallProduct |
                       Select-Object -ExpandProperty displayName)

# --- Defender specifics, only if Defender is actually present --------------
if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
  $mp = Get-MpComputerStatus
  if ($mp) {
    $r.defender = [ordered]@{
      realtime            = $mp.RealTimeProtectionEnabled
      tamperProtection    = $mp.IsTamperProtected
      signatureAgeDays    = $mp.AntivirusSignatureAge
      lastQuickScan       = $mp.QuickScanEndTime
      engineVersion       = $mp.AMEngineVersion
    }
    # Exclusions are a common attacker persistence trick — surface them.
    $pref = Get-MpPreference
    $r.defenderExclusions = [ordered]@{
      paths      = @($pref.ExclusionPath)
      processes  = @($pref.ExclusionProcess)
      extensions = @($pref.ExclusionExtension)
    }
    $r.recentThreats = @(Get-MpThreatDetection |
      Sort-Object InitialDetectionTime -Descending | Select-Object -First 20 |
      ForEach-Object { [ordered]@{
        threat   = $_.ThreatID
        detected = $_.InitialDetectionTime
        action   = $_.CleaningActionID
        resource = $_.Resources
      }})
  }
}

# --- Firewall profiles ------------------------------------------------------
$r.firewallProfiles = @(Get-NetFirewallProfile | ForEach-Object {
  [ordered]@{ profile = $_.Name; enabled = $_.Enabled; inbound = "$($_.DefaultInboundAction)" }})

# --- Logging health: if auditing is off, everything else is blind ----------
$r.auditing = [ordered]@{
  processCreationAudit = ((auditpol /get /subcategory:"Process Creation" 2>$null) -join ' ') -match 'Success'
  commandLineInAudit   = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit' -Name ProcessCreationIncludeCmdLine_Enabled -EA SilentlyContinue).ProcessCreationIncludeCmdLine_Enabled -eq 1
  scriptBlockLogging   = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Name EnableScriptBlockLogging -EA SilentlyContinue).EnableScriptBlockLogging -eq 1
  sysmonInstalled      = [bool](Get-Service -Name 'Sysmon*' -EA SilentlyContinue)
}

# --- Log clearing is a strong tampering signal -----------------------------
$r.logCleared = @(Get-WinEvent -FilterHashtable @{LogName='Security';Id=1102;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 10 -EA SilentlyContinue |
  ForEach-Object { [ordered]@{ time = $_.TimeCreated.ToString('o'); user = $_.Properties[1].Value }})

$json = $r | ConvertTo-Json -Depth 6
if ($OutPath) { $json | Out-File -FilePath $OutPath -Encoding utf8 } else { $json }
