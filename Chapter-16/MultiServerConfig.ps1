<#
.SYNOPSIS
    Multi-Server Configuration and Management System
.DESCRIPTION
    Configures multiple servers with standardized settings, verifies
    configurations, and generates compliance reports using PowerShell remoting
.PARAMETER ComputerName
    Target servers for configuration
.PARAMETER ConfigurationType
    Type of configuration to apply (Security, Services, Network, All)
.PARAMETER ReportOnly
    Check configurations without making changes
.NOTES
    REQUIRES: Administrator privileges
    REQUIRES: WinRM enabled on all target servers
    REQUIRES: Network connectivity to target servers
    REQUIRES: Administrator credentials on remote computers
#>

param(
    [Parameter(Mandatory=$true)]
    [string[]]$ComputerName,
    
    [ValidateSet("Security", "Services", "Network", "All")]
    [string]$ConfigurationType = "All",
    
    [switch]$ReportOnly
)

# ⚠️ Check for administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: Administrator privileges required" -ForegroundColor Red
    exit 1
}

# Configuration settings
$config = @{
    LogPath = "C:\Logs\ServerConfiguration"
    RequiredServices = @("WinRM", "EventLog", "W32Time")
    DisabledServices = @("RemoteRegistry", "TapiSrv")
    SecuritySettings = @{
        ScreenSaverTimeout = 900
        RequirePasswordOnResume = 1
    }
}

# Ensure log directory exists
if (-not (Test-Path $config.LogPath)) {
    New-Item -Path $config.LogPath -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$logFile = Join-Path $config.LogPath "ServerConfig-$timestamp.log"

function Write-ConfigLog {
    param([string]$Message, [string]$Level = "INFO")
    
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" | Add-Content -Path $logFile
    
    $color = @{
        "ERROR" = "Red"
        "WARNING" = "Yellow"
        "SUCCESS" = "Green"
        "INFO" = "Cyan"
    }[$Level]
    
    Write-Host $Message -ForegroundColor $color
}

Write-ConfigLog "=== MULTI-SERVER CONFIGURATION STARTED ===" "INFO"
Write-ConfigLog "Target Servers: $($ComputerName -join ', ')" "INFO"
Write-ConfigLog "Configuration Type: $ConfigurationType" "INFO"
if ($ReportOnly) {
    Write-ConfigLog "MODE: Report Only (No Changes)" "WARNING"
}

#region Test Connectivity

Write-ConfigLog "`n[1] Testing Server Connectivity" "INFO"

$onlineServers = @()
$offlineServers = @()

foreach ($computer in $ComputerName) {
    Write-ConfigLog "  Testing $computer..." "INFO"
    
    # Test basic connectivity
    if (Test-Connection -ComputerName $computer -Count 1 -Quiet) {
        # Test WinRM
        try {
            Test-WSMan -ComputerName $computer -ErrorAction Stop | Out-Null
            $onlineServers += $computer
            Write-ConfigLog "    ✓ Online and WinRM accessible" "SUCCESS"
        }
        catch {
            $offlineServers += $computer
            Write-ConfigLog "    ✗ WinRM not accessible" "ERROR"
        }
    }
    else {
        $offlineServers += $computer
        Write-ConfigLog "    ✗ Server unreachable" "ERROR"
    }
}

if ($onlineServers.Count -eq 0) {
    Write-ConfigLog "`nNo servers accessible. Exiting." "ERROR"
    exit 1
}

Write-ConfigLog "`nAccessible: $($onlineServers.Count) | Inaccessible: $($offlineServers.Count)" "INFO"

#endregion

#region Service Configuration

if ($ConfigurationType -in "Services", "All") {
    Write-ConfigLog "`n[2] Configuring Services" "INFO"
    
    $serviceResults = Invoke-Command -ComputerName $onlineServers -ScriptBlock {
        param($RequiredServices, $DisabledServices, $ReportOnly)
        
        $results = @{
            ComputerName = $env:COMPUTERNAME
            RequiredServicesOK = $true
            DisabledServicesOK = $true
            Changes = @()
        }
        
        # Check required services
        foreach ($svcName in $RequiredServices) {
            $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            
            if ($service) {
                if ($service.Status -ne 'Running' -or $service.StartType -ne 'Automatic') {
                    $results.RequiredServicesOK = $false
                    
                    if (-not $ReportOnly) {
                        Start-Service -Name $svcName -ErrorAction SilentlyContinue
                        Set-Service -Name $svcName -StartupType Automatic
                        $results.Changes += "Started and set $svcName to Automatic"
                    }
                    else {
                        $results.Changes += "NEEDS: $svcName should be Running/Automatic"
                    }
                }
            }
        }
        
        # Check services to disable
        foreach ($svcName in $DisabledServices) {
            $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            
            if ($service -and $service.StartType -ne 'Disabled') {
                $results.DisabledServicesOK = $false
                
                if (-not $ReportOnly) {
                    Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                    Set-Service -Name $svcName -StartupType Disabled
                    $results.Changes += "Stopped and disabled $svcName"
                }
                else {
                    $results.Changes += "NEEDS: $svcName should be Disabled"
                }
            }
        }
        
        return $results
    } -ArgumentList $config.RequiredServices, $config.DisabledServices, $ReportOnly
    
    foreach ($result in $serviceResults) {
        Write-ConfigLog "  $($result.ComputerName):" "INFO"
        
        if ($result.RequiredServicesOK -and $result.DisabledServicesOK) {
            Write-ConfigLog "    ✓ All services configured correctly" "SUCCESS"
        }
        else {
            foreach ($change in $result.Changes) {
                $level = if ($change -like "NEEDS:*") { "WARNING" } else { "SUCCESS" }
                Write-ConfigLog "    - $change" $level
            }
        }
    }
}

#endregion

#region Security Configuration

if ($ConfigurationType -in "Security", "All") {
    Write-ConfigLog "`n[3] Configuring Security Settings" "INFO"
    
    $securityResults = Invoke-Command -ComputerName $onlineServers -ScriptBlock {
        param($Settings, $ReportOnly)
        
        $results = @{
            ComputerName = $env:COMPUTERNAME
            Changes = @()
        }
        
        # Screen saver timeout
        $regPath = "HKCU:\Control Panel\Desktop"
        $currentTimeout = (Get-ItemProperty -Path $regPath -Name "ScreenSaveTimeOut" -ErrorAction SilentlyContinue).ScreenSaveTimeOut
        
        if ($currentTimeout -ne $Settings.ScreenSaverTimeout.ToString()) {
            if (-not $ReportOnly) {
                Set-ItemProperty -Path $regPath -Name "ScreenSaveTimeOut" -Value $Settings.ScreenSaverTimeout.ToString()
                Set-ItemProperty -Path $regPath -Name "ScreenSaverIsSecure" -Value $Settings.RequirePasswordOnResume.ToString()
                $results.Changes += "Configured screen saver timeout: $($Settings.ScreenSaverTimeout) seconds"
            }
            else {
                $results.Changes += "NEEDS: Screen saver timeout should be $($Settings.ScreenSaverTimeout) seconds"
            }
        }
        
        # Additional security settings could be added here
        
        if ($results.Changes.Count -eq 0) {
            $results.Changes += "All security settings already configured"
        }
        
        return $results
    } -ArgumentList $config.SecuritySettings, $ReportOnly
    
    foreach ($result in $securityResults) {
        Write-ConfigLog "  $($result.ComputerName):" "INFO"
        foreach ($change in $result.Changes) {
            $level = if ($change -like "NEEDS:*") { "WARNING" } elseif ($change -like "All*") { "SUCCESS" } else { "SUCCESS" }
            Write-ConfigLog "    - $change" $level
        }
    }
}

#endregion

#region System Information Collection

Write-ConfigLog "`n[4] Collecting System Information" "INFO"

$systemInfo = Invoke-Command -ComputerName $onlineServers -ScriptBlock {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    
    [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        OS = $os.Caption
        OSVersion = $os.Version
        LastBoot = $os.LastBootUpTime
        TotalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        Domain = $cs.Domain
    }
}

Write-ConfigLog "  System information collected from $($systemInfo.Count) servers" "SUCCESS"

#endregion

#region Generate Report

Write-ConfigLog "`n[5] Generating Configuration Report" "INFO"

$reportPath = Join-Path $config.LogPath "ConfigReport-$timestamp.html"

$serverRows = foreach ($server in $systemInfo) {
    $status = if ($server.ComputerName -in $onlineServers) { 
        "<span style='color: green;'>✓ Configured</span>" 
    } else { 
        "<span style='color: red;'>✗ Offline</span>" 
    }
    
    "<tr>
        <td>$($server.ComputerName)</td>
        <td>$($server.OS)</td>
        <td>$($server.OSVersion)</td>
        <td>$([math]::Round(((Get-Date) - $server.LastBoot).TotalDays, 1)) days</td>
        <td>$($server.TotalMemoryGB) GB</td>
        <td>$status</td>
    </tr>"
}

$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Multi-Server Configuration Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2c3e50; }
        .summary { background-color: #e8f4f8; padding: 15px; margin: 20px 0; border-radius: 5px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th { background-color: #3498db; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .success { color: green; font-weight: bold; }
        .error { color: red; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Multi-Server Configuration Report</h1>
    
    <div class="summary">
        <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Configuration Type:</strong> $ConfigurationType</p>
        <p><strong>Mode:</strong> $(if($ReportOnly){'Report Only'}else{'Configuration Applied'})</p>
        <p><strong>Total Servers:</strong> $($ComputerName.Count)</p>
        <p class="success"><strong>Accessible:</strong> $($onlineServers.Count)</p>
        $(if($offlineServers.Count -gt 0){"<p class='error'><strong>Inaccessible:</strong> $($offlineServers.Count)</p>"})
    </div>
    
    <h2>Server Status</h2>
    <table>
        <tr>
            <th>Computer Name</th>
            <th>Operating System</th>
            <th>Version</th>
            <th>Uptime</th>
            <th>Memory</th>
            <th>Status</th>
        </tr>
        $($serverRows -join "`n")
    </table>
    
    $(if($offlineServers.Count -gt 0){
        "<h2>Inaccessible Servers</h2><ul>$(($offlineServers | ForEach-Object {"<li>$_</li>"}) -join '')</ul>"
    })
    
    <p style="margin-top: 40px; color: #7f8c8d; font-size: 0.9em;">
        Detailed logs: $logFile
    </p>
</body>
</html>
"@

$htmlReport | Out-File -Path $reportPath -Encoding UTF8

Write-ConfigLog "  HTML report generated: $reportPath" "SUCCESS"

#endregion

# Summary
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "MULTI-SERVER CONFIGURATION COMPLETE" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "Configuration Type: $ConfigurationType"
Write-Host "Servers Configured: $($onlineServers.Count) / $($ComputerName.Count)"
if ($offlineServers.Count -gt 0) {
    Write-Host "Inaccessible Servers: $($offlineServers -join ', ')" -ForegroundColor Yellow
}
Write-Host "`nLog File: $logFile"
Write-Host "Report: $reportPath"
Write-Host ("=" * 70) -ForegroundColor Cyan

Write-ConfigLog "=== MULTI-SERVER CONFIGURATION COMPLETED ===" "SUCCESS"

# Return results
return [PSCustomObject]@{
    Timestamp = Get-Date
    ConfigurationType = $ConfigurationType
    TotalServers = $ComputerName.Count
    AccessibleServers = $onlineServers.Count
    InaccessibleServers = $offlineServers.Count
    OnlineServers = $onlineServers
    OfflineServers = $offlineServers
    LogFile = $logFile
    ReportPath = $reportPath
}
