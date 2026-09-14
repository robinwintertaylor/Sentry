<#
.SYNOPSIS
  Read-only hardening posture assessment. Feeds Sentry's monthly report.
.DESCRIPTION
  Measures what is already in place so recommendations are about the gaps,
  not a generic checklist. Changes nothing.
#>
[CmdletBinding()]
param([string]$OutPath)

$ErrorActionPreference = 'SilentlyContinue'
function Reg($p,$n){ (Get-ItemProperty -Path $p -Name $n -EA SilentlyContinue).$n }
$r = [ordered]@{ collected=(Get-Date).ToString('o'); host=$env:COMPUTERNAME }

# --- Platform / firmware ----------------------------------------------------
$cs = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$r.platform = [ordered]@{
  os              = $os.Caption
  build           = "$($os.Version) ($((Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'DisplayVersion')))"
  installedOn     = $os.InstallDate
  lastBoot        = $os.LastBootUpTime
  domainJoined    = $cs.PartOfDomain
  secureBoot      = try { Confirm-SecureBootUEFI } catch { 'unsupported-or-legacy-bios' }
  tpmPresent      = [bool](Get-Tpm).TpmPresent
  tpmReady        = (Get-Tpm).TpmReady
  virtualisationBasedSecurity = (Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard).VirtualizationBasedSecurityStatus
}

# --- Disk encryption --------------------------------------------------------
$r.encryption = @(Get-BitLockerVolume -EA SilentlyContinue | ForEach-Object {
  [ordered]@{ mount=$_.MountPoint; status="$($_.ProtectionStatus)"; method="$($_.EncryptionMethod)"; percent=$_.EncryptionPercentage }})

# --- Patch state ------------------------------------------------------------
$hf = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
$r.patching = [ordered]@{
  lastHotfix     = $hf.HotFixID
  lastInstalled  = $hf.InstalledOn
  daysSincePatch = if ($hf.InstalledOn) { [int]((Get-Date) - $hf.InstalledOn).TotalDays } else { $null }
  auGroupPolicy  = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate'
}

# --- Account posture --------------------------------------------------------
$admins = @(Get-LocalGroupMember -Group 'Administrators' -EA SilentlyContinue |
            ForEach-Object { [ordered]@{ name=$_.Name; class="$($_.ObjectClass)"; source="$($_.PrincipalSource)" }})
$r.accounts = [ordered]@{
  localAdministrators = $admins
  adminCount          = $admins.Count
  guestEnabled        = (Get-LocalUser -Name 'Guest' -EA SilentlyContinue).Enabled
  currentUserIsAdmin  = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
  passwordNeverExpires= @(Get-LocalUser | Where-Object { $_.Enabled -and $_.PasswordNeverExpires } | Select-Object -Expand Name)
}

# --- UAC / SmartScreen / attack surface ------------------------------------
$r.uac = [ordered]@{
  enabled             = (Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA') -eq 1
  consentPromptAdmin  = Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin'
  secureDesktop       = (Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'PromptOnSecureDesktop') -eq 1
}
$r.smartScreen = [ordered]@{
  explorer = Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'SmartScreenEnabled'
  edge     = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'SmartScreenEnabled'
}

# --- Legacy protocols: the usual easy wins ---------------------------------
$r.legacyProtocols = [ordered]@{
  smb1Enabled        = (Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -EA SilentlyContinue).State
  smbSigningRequired = (Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' 'RequireSecuritySignature') -eq 1
  powerShellV2       = (Get-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2 -EA SilentlyContinue).State
  llmnrDisabled      = (Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast') -eq 0
  netbiosOverTcpip   = @(Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object IPEnabled |
                          ForEach-Object { [ordered]@{ adapter=$_.Description; tcpipNetbios=$_.TcpipNetbiosOptions }})
  wdigestUseLogonCred= Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential'
  autorun            = Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun'
}

# --- Credential protection --------------------------------------------------
$r.credentialProtection = [ordered]@{
  lsaProtection     = Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RunAsPPL'
  credentialGuard   = (Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard).SecurityServicesRunning
  cachedLogonCount  = Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' 'CachedLogonsCount'
}

# --- Remote access surface --------------------------------------------------
$r.remoteAccess = [ordered]@{
  rdpEnabled      = (Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections') -eq 0
  rdpNlaRequired  = (Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication') -eq 1
  winrmRunning    = (Get-Service WinRM -EA SilentlyContinue).Status -eq 'Running'
  remoteRegistry  = (Get-Service RemoteRegistry -EA SilentlyContinue).StartType
  openInboundRules= @(Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled True -EA SilentlyContinue |
                       Where-Object { $_.Profile -match 'Public|Any' } | Measure-Object).Count
}

# --- Defender ASR rules: high value, sometimes breaks things ---------------
if (Get-Command Get-MpPreference -EA SilentlyContinue) {
  $pref = Get-MpPreference
  $asrNames = @{
    'd4f940ab-401b-4efc-aadc-ad5f3c50688a'='Office child processes'
    '3b576869-a4ec-4529-8536-b80a7769e899'='Office executable content'
    '5beb7efe-fd9a-4556-801d-275e5ffc04cc'='Obfuscated scripts'
    'd3e037e1-3eb8-44c8-a917-57927947596d'='JS/VBS launching downloads'
    '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b'='Office child process creation'
    '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2'='Credential stealing from lsass'
    'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4'='Untrusted USB processes'
    'c1db55ab-c21a-4637-bb3f-a12568109d35'='Advanced ransomware protection'
  }
  $active = @{}
  for ($i=0; $i -lt $pref.AttackSurfaceReductionRules_Ids.Count; $i++) {
    $active[$pref.AttackSurfaceReductionRules_Ids[$i]] = $pref.AttackSurfaceReductionRules_Actions[$i]
  }
  $r.asrRules = @($asrNames.GetEnumerator() | ForEach-Object {
    [ordered]@{ id=$_.Key; name=$_.Value
      state = if ($active.ContainsKey($_.Key)) { switch ($active[$_.Key]) {1{'block'} 2{'audit'} 6{'warn'} default{'off'}} } else {'not-configured'} }})
  $r.controlledFolderAccess = "$($pref.EnableControlledFolderAccess)"
  $r.networkProtection      = "$($pref.EnableNetworkProtection)"
  $r.puaProtection          = "$($pref.PUAProtection)"
}

# --- Logging maturity: gaps here weaken everything else --------------------
$r.logging = [ordered]@{
  processCreationAudit = ((auditpol /get /subcategory:"Process Creation" 2>$null) -join ' ') -match 'Success'
  commandLineInAudit   = (Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit' 'ProcessCreationIncludeCmdLine_Enabled') -eq 1
  scriptBlockLogging   = (Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' 'EnableScriptBlockLogging') -eq 1
  moduleLogging        = (Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging' 'EnableModuleLogging') -eq 1
  sysmon               = [bool](Get-Service -Name 'Sysmon*' -EA SilentlyContinue)
  securityLogMaxMB     = [int]((Get-WinEvent -ListLog Security).MaximumSizeInBytes / 1MB)
  securityLogRetention = "$((Get-WinEvent -ListLog Security).LogMode)"
}

# --- Software inventory: unpatched third-party is the usual entry point ----
$r.software = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA SilentlyContinue |
  Where-Object DisplayName | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
  Sort-Object DisplayName | ForEach-Object {
    [ordered]@{ name=$_.DisplayName; version=$_.DisplayVersion; publisher=$_.Publisher; installed=$_.InstallDate }})

# --- Usage signal so recommendations respect how the machine is used ------
# A hardening step that breaks a daily tool is a bad recommendation.
$r.usageSignals = [ordered]@{
  runningApps      = @(Get-Process | Where-Object MainWindowTitle | Select-Object -Expand ProcessName -Unique)
  devToolsPresent  = @('git','code','docker','python','node','pwsh','wsl' | Where-Object { Get-Command $_ -EA SilentlyContinue })
  wslInstalled     = [bool](Get-Command wsl -EA SilentlyContinue)
  hyperVEnabled    = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -EA SilentlyContinue).State
  officeInstalled  = [bool](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -EA SilentlyContinue)
  vpnAdapters      = @(Get-NetAdapter -EA SilentlyContinue | Where-Object InterfaceDescription -match 'VPN|TAP|WireGuard|Tailscale' | Select-Object -Expand Name)
}

$json = $r | ConvertTo-Json -Depth 7
if ($OutPath) { $json | Out-File -FilePath $OutPath -Encoding utf8 } else { $json }
