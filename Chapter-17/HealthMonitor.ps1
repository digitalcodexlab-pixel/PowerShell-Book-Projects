<#
.SYNOPSIS
    System Health Monitoring Dashboard
.DESCRIPTION
    Monitors event logs, system resources, services, and disk space.
    Generates HTML dashboard with health status and alerts.
.PARAMETER ComputerName
    Target computers to monitor
.PARAMETER CheckIntervalMinutes
    Interval between health checks (for continuous monitoring)
.PARAMETER ContinuousMode
    Run continuously with periodic checks
.PARAMETER OutputPath
    Directory for reports and logs
.NOTES
    REQUIRES: Administrator privileges (for Security log and some operations)
    REQUIRES: WinRM enabled for remote monitoring
    REQUIRES: Network connectivity to target computers
#>

param(
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    [int]$CheckIntervalMinutes = 5,
    [switch]$ContinuousMode,
    [string]$OutputPath = "C:\Monitoring"
)

# ⚠️ Check for administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "WARNING: Administrator privileges recommended for full monitoring capabilities" -ForegroundColor Yellow
    Write-Host "Security log monitoring and some operations will be unavailable" -ForegroundColor Yellow
    Start-Sleep -Seconds 3
}

# Configuration
$config = @{
    DiskSpaceThreshold = 20  # Percent free
    MemoryThreshold = 90     # Percent used
    CPUThreshold = 90        # Percent used
    ServiceCheckMinutes = 60 # Look back period for service failures
    EventCheckMinutes = 60   # Look back period for critical events
    CriticalServices = @("WinRM", "EventLog", "W32Time", "Dnscache")
}

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$logFile = Join-Path $OutputPath "HealthMonitor-$timestamp.log"

function Write-MonitorLog {
    param([string]$Message, [string]$Level = "INFO")
    
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" | Add-Content -Path $logFile
    
    $color = @{
        "ERROR" = "Red"
        "WARNING" = "Yellow"
        "SUCCESS" = "Green"
        "INFO" = "Cyan"
        "ALERT" = "Magenta"
    }[$Level]
    
    Write-Host $Message -ForegroundColor $color
}

function Get-SystemHealth {
    param([string]$Computer)
    
    Write-MonitorLog "Checking health of $Computer..." "INFO"
    
    $health = @{
        ComputerName = $Computer
        CheckTime = Get-Date
        Alerts = @()
        Status = "Healthy"
    }
    
    try {
        # Collect system information
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $Computer -ErrorAction Stop
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $Computer -ErrorAction Stop
        $cpu = Get-CimInstance -ClassName Win32_Processor -ComputerName $Computer -ErrorAction Stop
        
        # Calculate metrics
        $health.OS = $os.Caption
        $health.Uptime = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 2)
        $health.TotalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        $health.FreeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $health.MemoryUsedPercent = [math]::Round((1 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize)) * 100, 1)
        $health.CPULoad = $cpu.LoadPercentage
        
        # Check memory
        if ($health.MemoryUsedPercent -gt $config.MemoryThreshold) {
            $health.Alerts += "Memory usage critical: $($health.MemoryUsedPercent)%"
            $health.Status = "Warning"
            Write-MonitorLog "  ALERT: High memory usage on $Computer" "ALERT"
        }
        
        # Check CPU
        if ($health.CPULoad -gt $config.CPUThreshold) {
            $health.Alerts += "CPU load high: $($health.CPULoad)%"
            $health.Status = "Warning"
            Write-MonitorLog "  ALERT: High CPU load on $Computer" "ALERT"
        }
        
        # Check disk space
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ComputerName $Computer
        $health.Disks = @()
        
        foreach ($disk in $disks) {
            $percentFree = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
            
            $diskInfo = [PSCustomObject]@{
                Drive = $disk.DeviceID
                SizeGB = [math]::Round($disk.Size / 1GB, 2)
                FreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
                PercentFree = $percentFree
                Status = if ($percentFree -lt $config.DiskSpaceThreshold) { "Critical" } else { "OK" }
            }
            
            $health.Disks += $diskInfo
            
            if ($percentFree -lt $config.DiskSpaceThreshold) {
                $health.Alerts += "Disk $($disk.DeviceID) low space: $percentFree% free"
                $health.Status = "Critical"
                Write-MonitorLog "  ALERT: Low disk space on $Computer $($disk.DeviceID)" "ALERT"
            }
        }
        
        # Check critical services
        $serviceIssues = @()
        foreach ($serviceName in $config.CriticalServices) {
            $service = Get-Service -Name $serviceName -ComputerName $Computer -ErrorAction SilentlyContinue
            
            if ($service) {
                if ($service.Status -ne 'Running') {
                    $serviceIssues += "$serviceName is $($service.Status)"
                    $health.Status = "Critical"
                    Write-MonitorLog "  ALERT: Service $serviceName not running on $Computer" "ALERT"
                }
            }
        }
        
        $health.ServiceIssues = $serviceIssues
        if ($serviceIssues.Count -gt 0) {
            $health.Alerts += "Critical services not running: $($serviceIssues.Count)"
        }
        
        # Check event logs for recent critical errors
        $criticalEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            Level = 1  # Critical
            StartTime = (Get-Date).AddMinutes(-$config.EventCheckMinutes)
        } -ComputerName $Computer -ErrorAction SilentlyContinue
        
        if ($criticalEvents) {
            $health.Alerts += "Critical system events: $($criticalEvents.Count)"
            $health.Status = "Warning"
            $health.CriticalEventCount = $criticalEvents.Count
            Write-MonitorLog "  ALERT: $($criticalEvents.Count) critical events on $Computer" "ALERT"
        }
        
        # Check for service failures
        $serviceFailures = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ProviderName = 'Service Control Manager'
            Level = 2
            StartTime = (Get-Date).AddMinutes(-$config.ServiceCheckMinutes)
        } -ComputerName $Computer -ErrorAction SilentlyContinue
        
        if ($serviceFailures) {
            $health.Alerts += "Service failures detected: $($serviceFailures.Count)"
            $health.ServiceFailureCount = $serviceFailures.Count
        }
        
        Write-MonitorLog "  Health check completed: $($health.Status)" $(if($health.Status -eq "Healthy"){"SUCCESS"}else{"WARNING"})
    }
    catch {
        $health.Status = "Error"
        $health.Alerts += "Failed to collect data: $($_.Exception.Message)"
        Write-MonitorLog "  ERROR: Failed to check $Computer - $($_.Exception.Message)" "ERROR"
    }
    
    return [PSCustomObject]$health
}

function New-HealthDashboard {
    param($HealthData)
    
    $dashboardPath = Join-Path $OutputPath "HealthDashboard-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').html"
    
    # Build server rows
    $serverRows = foreach ($server in $HealthData) {
        $statusColor = switch ($server.Status) {
            "Healthy" { "green" }
            "Warning" { "orange" }
            "Critical" { "red" }
            "Error" { "darkred" }
        }
        
        $alertsList = if ($server.Alerts.Count -gt 0) {
            "<ul>" + (($server.Alerts | ForEach-Object { "<li>$_</li>" }) -join "") + "</ul>"
        } else {
            "<span style='color: green;'>No alerts</span>"
        }
        
        $diskRows = if ($server.Disks) {
            ($server.Disks | ForEach-Object {
                $diskColor = if ($_.Status -eq "Critical") { "red" } else { "green" }
                "<tr style='background-color: #f9f9f9;'>
                    <td>$($_.Drive)</td>
                    <td>$($_.SizeGB) GB</td>
                    <td>$($_.FreeGB) GB</td>
                    <td style='color: $diskColor; font-weight: bold;'>$($_.PercentFree)%</td>
                </tr>"
            }) -join ""
        } else {
            ""
        }
        
        "<tr>
            <td><strong>$($server.ComputerName)</strong></td>
            <td style='color: $statusColor; font-weight: bold;'>$($server.Status)</td>
            <td>$($server.OS)</td>
            <td>$($server.Uptime) days</td>
            <td>$($server.MemoryUsedPercent)%</td>
            <td>$($server.CPULoad)%</td>
            <td>$alertsList</td>
        </tr>
        $(if($diskRows){"<tr><td colspan='7'><table style='width: 100%; margin: 10px 0;'>
            <tr style='background-color: #e0e0e0;'>
                <th>Drive</th><th>Size</th><th>Free</th><th>% Free</th>
            </tr>
            $diskRows
        </table></td></tr>"})"
    }
    
    $healthyCount = ($HealthData | Where-Object Status -eq "Healthy").Count
    $warningCount = ($HealthData | Where-Object Status -eq "Warning").Count
    $criticalCount = ($HealthData | Where-Object Status -eq "Critical").Count
    $errorCount = ($HealthData | Where-Object Status -eq "Error").Count
    
    $htmlDashboard = @"
<!DOCTYPE html>
<html>
<head>
    <title>System Health Monitoring Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #2c3e50; }
        .summary { background-color: #fff; padding: 20px; margin: 20px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .summary-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin: 20px 0; }
        .summary-card { background-color: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center; }
        .summary-card h3 { margin: 0; font-size: 36px; }
        .summary-card p { margin: 10px 0 0 0; color: #666; }
        .healthy { color: green; }
        .warning { color: orange; }
        .critical { color: red; }
        .error { color: darkred; }
        table { border-collapse: collapse; width: 100%; background-color: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #3498db; color: white; padding: 15px; text-align: left; }
        td { padding: 12px 15px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .timestamp { color: #7f8c8d; font-size: 0.9em; margin-top: 30px; }
    </style>
</head>
<body>
    <h1>🖥️ System Health Monitoring Dashboard</h1>
    
    <div class="summary">
        <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Monitoring:</strong> $($HealthData.Count) system(s)</p>
    </div>
    
    <div class="summary-grid">
        <div class="summary-card">
            <h3 class="healthy">$healthyCount</h3>
            <p>Healthy</p>
        </div>
        <div class="summary-card">
            <h3 class="warning">$warningCount</h3>
            <p>Warning</p>
        </div>
        <div class="summary-card">
            <h3 class="critical">$criticalCount</h3>
            <p>Critical</p>
        </div>
        <div class="summary-card">
            <h3 class="error">$errorCount</h3>
            <p>Error</p>
        </div>
    </div>
    
    <h2>System Status</h2>
    <table>
        <tr>
            <th>Computer</th>
            <th>Status</th>
            <th>OS</th>
            <th>Uptime</th>
            <th>Memory Used</th>
            <th>CPU Load</th>
            <th>Alerts</th>
        </tr>
        $($serverRows -join "`n")
    </table>
    
    <p class="timestamp">Dashboard auto-refreshes every $CheckIntervalMinutes minutes in continuous mode</p>
</body>
</html>
"@
    
    $htmlDashboard | Out-File -Path $dashboardPath -Encoding UTF8
    
    return $dashboardPath
}

# Main monitoring loop
Write-MonitorLog "=== SYSTEM HEALTH MONITORING STARTED ===" "INFO"
Write-MonitorLog "Monitoring: $($ComputerName -join ', ')" "INFO"

do {
    $healthData = @()
    
    foreach ($computer in $ComputerName) {
        $healthData += Get-SystemHealth -Computer $computer
    }
    
    # Generate dashboard
    $dashboardPath = New-HealthDashboard -HealthData $healthData
    Write-MonitorLog "Dashboard generated: $dashboardPath" "SUCCESS"
    
    # Summary
    $criticalSystems = $healthData | Where-Object Status -eq "Critical"
    $warningSystems = $healthData | Where-Object Status -eq "Warning"
    
    if ($criticalSystems) {
        Write-MonitorLog "CRITICAL SYSTEMS: $($criticalSystems.ComputerName -join ', ')" "ALERT"
    }
    
    if ($warningSystems) {
        Write-MonitorLog "WARNING SYSTEMS: $($warningSystems.ComputerName -join ', ')" "WARNING"
    }
    
    if (-not $criticalSystems -and -not $warningSystems) {
        Write-MonitorLog "All systems healthy" "SUCCESS"
    }
    
    if ($ContinuousMode) {
        Write-Host "`nNext check in $CheckIntervalMinutes minutes. Press Ctrl+C to stop." -ForegroundColor Cyan
        Start-Sleep -Seconds ($CheckIntervalMinutes * 60)
    }
    
} while ($ContinuousMode)

Write-MonitorLog "=== SYSTEM HEALTH MONITORING COMPLETED ===" "INFO"

# Return final health data
return $healthData
