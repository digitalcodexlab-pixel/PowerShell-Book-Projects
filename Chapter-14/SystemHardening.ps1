<#
.SYNOPSIS
    System Hardening and Security Configuration Script.
.DESCRIPTION
    Applies security hardening measures including registry modifications,
    feature management, and system configuration enforcement.
.PARAMETER SkipWindowsUpdate
    Skip Windows Update configuration.
.PARAMETER SkipFirewall
    Skip firewall verification.
.PARAMETER ReportOnly
    Check settings without making changes
#>
param(
    [switch]$SkipWindowsUpdate,
    [switch]$SkipFirewall,
    [switch]$ReportOnly
)

# Configuration
$config = @{
    LogPath = "C:\Logs\Hardening"
    CompanyName = "YourCompany"
    RequireAdminApproval = $true
}

# Initialize logging
$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
if (-not (Test-Path $config.LogPath)) {
    New-Item -Path $config.LogPath -ItemType Directory | Out-Null
}
$logFile = Join-Path $config.LogPath "Hardening-$timestamp.log"

function Write-HardeningLog {
    param([string]$Message, [string]$Level = "INFO")
    
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" | Add-Content -Path $logFile
    
    $color = @{
        "ERROR"   = "Red"
        "WARNING" = "Yellow"
        "SUCCESS" = "Green"
        "INFO"    = "Cyan"
        "CHANGE"  = "Magenta"
    }[$Level]
    
    Write-Host $Message -ForegroundColor $color
}

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord",
        [string]$Description
    )
    
    if ($ReportOnly) {
        $current = $null
        try {
            $current = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
        }
        catch {}
        
        if ($current -eq $Value) {
            Write-HardeningLog "  ✓ $Description : Already configured" "SUCCESS"
        } else {
            Write-HardeningLog "  ✗ $Description : Needs configuration (Current: $current, Required: $Value)" "WARNING"
        }
        return
    }
    
    try {
        # Create key if doesn't exist
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        
        # Set value
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-HardeningLog "  ✓ $Description" "CHANGE"
    }
    catch {
        Write-HardeningLog "  ✗ Failed to set $Description : $($_.Exception.Message)" "ERROR"
    }
}

# Start hardening
Write-HardeningLog "=== SYSTEM HARDENING STARTED ===" "INFO"
if ($ReportOnly) {
    Write-HardeningLog "REPORT-ONLY MODE: No changes will be made" "WARNING"
}
Write-HardeningLog "Computer: $env:COMPUTERNAME" "INFO"

#region Disable Unnecessary Services
Write-HardeningLog "`n[1] Disabling Unnecessary Services" "INFO"
$servicesToDisable = @(
    @{Name="RemoteRegistry"; Desc="Remote Registry"},
    @{Name="TapiSrv"; Desc="Telephony"},
    @{Name="Fax"; Desc="Fax Service"}
)
foreach ($svc in $servicesToDisable) {
    try {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service) {
            if ($ReportOnly) {
                if ($service.StartType -eq "Disabled") {
                    Write-HardeningLog "  ✓ $($svc.Desc) : Already disabled" "SUCCESS"
                } else {
                    Write-HardeningLog "  ✗ $($svc.Desc) : Should be disabled (Current: $($service.StartType))" "WARNING"
                }
            } else {
                if ($service.StartType -ne "Disabled") {
                    Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                    Set-Service -Name $svc.Name -StartupType Disabled
                    Write-HardeningLog "  ✓ Disabled $($svc.Desc)" "CHANGE"
                }
            }
        }
    }
    catch {
        Write-HardeningLog "  ✗ Service $($svc.Name) not found or error" "WARNING"
    }
}
#endregion

#region Configure User Account Control (UAC)
Write-HardeningLog "`n[2] Configuring User Account Control" "INFO"
$uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

# Prompt for admin credentials
Set-RegistryValue -Path $uacPath -Name "ConsentPromptBehaviorAdmin" -Value 2 `
    -Description "Prompt for credentials on admin operations"

# Secure desktop for prompts
Set-RegistryValue -Path $uacPath -Name "PromptOnSecureDesktop" -Value 1 `
    -Description "Show UAC prompts on secure desktop"
#endregion

#region Disable AutoRun/AutoPlay
Write-HardeningLog "`n[3] Disabling AutoRun and AutoPlay" "INFO"
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
    -Name "NoDriveTypeAutoRun" -Value 255 `
    -Description "Disable AutoRun for all drive types"
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" `
    -Name "DisableAutoplay" -Value 1 `
    -Description "Disable AutoPlay"
#endregion

#region Configure Windows Defender
Write-HardeningLog "`n[4] Configuring Windows Defender" "INFO"
$defenderPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"

# Real-time protection
Set-RegistryValue -Path "$defenderPath\Real-Time Protection" `
    -Name "DisableRealtimeMonitoring" -Value 0 `
    -Description "Enable real-time protection"

# Cloud-based protection
Set-RegistryValue -Path "$defenderPath\Spynet" `
    -Name "SpynetReporting" -Value 2 `
    -Description "Enable cloud-based protection"
#endregion

#region Disable Guest Account
Write-HardeningLog "`n[5] Securing User Accounts" "INFO"
try {
    $guest = Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
    if ($guest) {
        if ($ReportOnly) {
            if ($guest.Enabled) {
                Write-HardeningLog "  ✗ Guest account should be disabled" "WARNING"
            } else {
                Write-HardeningLog "  ✓ Guest account disabled" "SUCCESS"
            }
        } else {
            if ($guest.Enabled) {
                Disable-LocalUser -Name "Guest"
                Write-HardeningLog "  ✓ Disabled Guest account" "CHANGE"
            }
        }
    }
}
catch {
    Write-HardeningLog "  ! Could not check Guest account" "WARNING"
}
#endregion

#region Configure Password Policy
Write-HardeningLog "`n[6] Configuring Password Policy" "INFO"
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" `
    -Name "RequireStrongKey" -Value 1 `
    -Description "Require strong session key"
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "LimitBlankPasswordUse" -Value 1 `
    -Description "Limit blank password use"
#endregion

#region Configure Screen Lock
Write-HardeningLog "`n[7] Configuring Screen Lock Policy" "INFO"
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "InactivityTimeoutSecs" -Value 900 `
    -Description "Lock screen after 15 minutes of inactivity"
Set-RegistryValue -Path "HKCU:\Software\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -Name "ScreenSaveTimeOut" -Value "900" -Type "String" `
    -Description "Screen saver timeout 15 minutes"
Set-RegistryValue -Path "HKCU:\Software\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -Name "ScreenSaverIsSecure" -Value "1" -Type "String" `
    -Description "Password protect screen saver"
#endregion

#region Configure Windows Update
if (-not $SkipWindowsUpdate) {
    Write-HardeningLog "`n[8] Configuring Windows Update" "INFO"
    
    $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    Set-RegistryValue -Path $wuPath -Name "NoAutoUpdate" -Value 0 `
        -Description "Enable automatic updates"
    Set-RegistryValue -Path $wuPath -Name "AUOptions" -Value 4 `
        -Description "Auto download and install updates"
    Set-RegistryValue -Path $wuPath -Name "ScheduledInstallDay" -Value 0 `
        -Description "Install updates every day"
}
#endregion

#region Verify Firewall Status
if (-not $SkipFirewall) {
    Write-HardeningLog "`n[9] Verifying Windows Firewall" "INFO"
    
    $profiles = @("Domain", "Private", "Public")
    foreach ($profile in $profiles) {
        try {
            $fwProfile = Get-NetFirewallProfile -Name $profile
            
            if ($ReportOnly) {
                if ($fwProfile.Enabled) {
                    Write-HardeningLog "  ✓ $profile profile firewall enabled" "SUCCESS"
                } else {
                    Write-HardeningLog "  ✗ $profile profile firewall disabled" "WARNING"
                }
            } else {
                if (-not $fwProfile.Enabled) {
                    Set-NetFirewallProfile -Name $profile -Enabled True
                    Write-HardeningLog "  ✓ Enabled $profile profile firewall" "CHANGE"
                } else {
                    Write-HardeningLog "  ✓ $profile profile firewall already enabled" "SUCCESS"
                }
            }
        }
        catch {
            Write-HardeningLog "  ✗ Error checking $profile firewall" "ERROR"
        }
    }
}
#endregion

#region Disable SMBv1
Write-HardeningLog "`n[10] Disabling SMBv1 Protocol" "INFO"
try {
    $smbv1 = Get-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -ErrorAction SilentlyContinue
    
    if ($smbv1) {
        if ($ReportOnly) {
            if ($smbv1.State -eq "Disabled") {
                Write-HardeningLog "  ✓ SMBv1 already disabled" "SUCCESS"
            } else {
                Write-HardeningLog "  ✗ SMBv1 should be disabled (security risk)" "WARNING"
            }
        } else {
            if ($smbv1.State -ne "Disabled") {
                Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart | Out-Null
                Write-HardeningLog "  ✓ Disabled SMBv1" "CHANGE"
            }
        }
    }
}
catch {
    Write-HardeningLog "  ! Could not disable SMBv1: $($_.Exception.Message)" "WARNING"
}
#endregion

#region Configure Remote Desktop Security
Write-HardeningLog "`n[11] Configuring Remote Desktop Security" "INFO"
$rdpPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"

# Require NLA (Network Level Authentication)
Set-RegistryValue -Path "$rdpPath\WinStations\RDP-Tcp" `
    -Name "UserAuthentication" -Value 1 `
    -Description "Require Network Level Authentication for RDP"

# Set encryption level
Set-RegistryValue -Path "$rdpPath\WinStations\RDP-Tcp" `
    -Name "MinEncryptionLevel" -Value 3 `
    -Description "Require high encryption for RDP"
#endregion

#region Audit and Event Log Configuration
Write-HardeningLog "`n[12] Configuring Audit Policies" "INFO"
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "SCENoApplyLegacyAuditPolicy" -Value 1 `
    -Description "Disable legacy audit policy"

# Increase Security event log size
$logPath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Security"
Set-RegistryValue -Path $logPath -Name "MaxSize" -Value 0x14000000 `
    -Description "Set Security log size to 320MB"
#endregion

#region Network Security
Write-HardeningLog "`n[13] Configuring Network Security" "INFO"
$netPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"

# Enable SYN attack protection
Set-RegistryValue -Path $netPath -Name "SynAttackProtect" -Value 1 `
    -Description "Enable SYN attack protection"

# Disable IP source routing
Set-RegistryValue -Path $netPath -Name "DisableIPSourceRouting" -Value 2 `
    -Description "Disable IP source routing"

# Ignore NetBIOS name release requests
Set-RegistryValue -Path $netPath -Name "NoNameReleaseOnDemand" -Value 1 `
    -Description "Ignore NetBIOS name release"
#endregion

#region Generate Hardening Report
Write-HardeningLog "`n=== GENERATING HARDENING REPORT ===" "INFO"
$reportPath = Join-Path $config.LogPath "HardeningReport-$timestamp.html"
$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>System Hardening Report - $env:COMPUTERNAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2c3e50; }
        h2 { color: #34495e; margin-top: 30px; }
        .summary { background-color: #e8f4f8; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .success { color: green; font-weight: bold; }
        .warning { color: orange; font-weight: bold; }
        .error { color: red; font-weight: bold; }
        .change { color: purple; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th { background-color: #3498db; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
    </style>
</head>
<body>
    <h1>System Hardening Report</h1>
    <div class="summary">
        <p><strong>Computer:</strong> $env:COMPUTERNAME</p>
        <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Mode:</strong> $(if ($ReportOnly) {'Report Only'} else {'Configuration Applied'})</p>
        <p><strong>User:</strong> $env:USERNAME</p>
    </div>

    <h2>Configuration Summary</h2>
    <p>Review the detailed log file for complete information: <code>$logFile</code></p>
    
    <h2>Applied Hardening Measures</h2>
    <ul>
        <li>Disabled unnecessary services (RemoteRegistry, Telephony, Fax)</li>
        <li>Configured User Account Control (UAC) for enhanced security</li>
        <li>Disabled AutoRun and AutoPlay</li>
        <li>Configured Windows Defender real-time and cloud protection</li>
        <li>Disabled Guest account</li>
        <li>Enforced password policy requirements</li>
        <li>Configured automatic screen lock (15 minutes)</li>
        $(if (-not $SkipWindowsUpdate) {"<li>Configured automatic Windows Updates</li>"})
        $(if (-not $SkipFirewall) {"<li>Verified Windows Firewall enabled on all profiles</li>"})
        <li>Disabled SMBv1 protocol</li>
        <li>Enhanced Remote Desktop security (NLA, encryption)</li>
        <li>Configured audit policies and event log sizes</li>
        <li>Applied network security hardening</li>
    </ul>

    <h2>Recommendations</h2>
    <ul>
        <li>Restart the computer to ensure all changes take effect</li>
        <li>Test critical applications to ensure compatibility</li>
        <li>Review audit logs regularly for security events</li>
        <li>Keep Windows and all applications updated</li>
        <li>Implement additional security tools (antivirus, EDR) as needed</li>
    </ul>

    <p style="margin-top: 40px; color: #7f8c8d; font-size: 0.9em;">
        Report generated by System Hardening Script v1.0
    </p>
</body>
</html>
"@
$htmlReport | Out-File -Path $reportPath -Encoding UTF8
Write-HardeningLog "HTML report generated: $reportPath" "SUCCESS"
#endregion

# Summary
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "SYSTEM HARDENING COMPLETE" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "Computer:     $env:COMPUTERNAME"
Write-Host "Mode:         $(if ($ReportOnly) {'Report Only - No Changes Made'} else {'Configuration Applied'})"
Write-Host "Log File:     $logFile"
Write-Host "Report:       $reportPath"
Write-Host "`n⚠️  RESTART REQUIRED to apply all changes" -ForegroundColor Yellow
Write-Host ("=" * 70) -ForegroundColor Cyan

Write-HardeningLog "=== SYSTEM HARDENING COMPLETED ===" "SUCCESS"

# Return summary
return [PSCustomObject]@{
    ComputerName   = $env:COMPUTERNAME
    Timestamp      = Get-Date
    ReportOnlyMode = $ReportOnly
    LogFile        = $logFile
    HtmlReport     = $reportPath
}

