<#
.SYNOPSIS
    Service Health Check and Monitoring System
.DESCRIPTION
    Monitors critical services, checks dependencies, tracks resource usage,
    and generates health reports with alerting
.PARAMETER CriticalServices
    Array of service names to monitor
.PARAMETER AlertEmail
    Email address for alert notifications
.PARAMETER ReportPath
    Path where reports are saved
#>

param(
    [string[]]$CriticalServices = @("Spooler", "BITS", "WinRM", "EventLog", "W32Time"),
    [string]$AlertEmail = $null,
    [string]$ReportPath = "C:\Reports\ServiceHealth"
)

# Ensure report directory exists
if (-not (Test-Path $ReportPath)) {
    New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$reportFile = Join-Path $ReportPath "ServiceHealth-$timestamp.html"
$logFile = Join-Path $ReportPath "ServiceHealth-$timestamp.log"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $logFile -Value $logEntry
    
    $color = switch($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    
    Write-Host $logEntry -ForegroundColor $color
}

# Statistics tracking
$stats = @{
    TotalServices = $CriticalServices.Count
    Running = 0
    Stopped = 0
    DependencyIssues = 0
    Alerts = @()
}

Write-Log "=== SERVICE HEALTH CHECK STARTED ===" "INFO"
Write-Log "Monitoring $($CriticalServices.Count) critical services"

# Collect service status information
$serviceResults = @()

foreach ($serviceName in $CriticalServices) {
    Write-Log "Checking service: $serviceName" "INFO"
    
    try {
        $service = Get-Service -Name $serviceName -ErrorAction Stop
        
        # Check service status
        $statusOK = $service.Status -eq 'Running'
        
        if ($statusOK) {
            $stats.Running++
            Write-Log "  $($service.DisplayName): Running" "SUCCESS"
        } else {
            $stats.Stopped++
            $alertMsg = "$($service.DisplayName) is $($service.Status)"
            $stats.Alerts += $alertMsg
            Write-Log "  $alertMsg" "ERROR"
        }
        
        # Check dependencies
        $dependencyIssues = @()
        foreach ($dep in $service.ServicesDependedOn) {
            if ($dep.Status -ne 'Running') {
                $depIssue = "Dependency $($dep.Name) is $($dep.Status)"
                $dependencyIssues += $depIssue
                $stats.DependencyIssues++
                $stats.Alerts += "$($service.DisplayName): $depIssue"
                Write-Log "  WARNING: $depIssue" "WARNING"
            }
        }
        
        # Get process information if service is running
        $processInfo = $null
        if ($service.Status -eq 'Running') {
            try {
                # Try to get process information
                $processId = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'").ProcessId
                if ($processId) {
                    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                    if ($process) {
                        $processInfo = [PSCustomObject]@{
                            CPU = [math]::Round($process.CPU, 2)
                            MemoryMB = [math]::Round($process.WorkingSet / 1MB, 2)
                            Threads = $process.Threads.Count
                        }
                    }
                }
            }
            catch {
                Write-Log "  Could not retrieve process info" "WARNING"
            }
        }
        
        # Create result object
        $result = [PSCustomObject]@{
            ServiceName = $service.Name
            DisplayName = $service.DisplayName
            Status = $service.Status
            StartType = $service.StartType
            StatusOK = $statusOK
            DependencyIssues = $dependencyIssues -join "; "
            DependencyCount = $service.ServicesDependedOn.Count
            DependentCount = $service.DependentServices.Count
            ProcessCPU = if ($processInfo) { $processInfo.CPU } else { "N/A" }
            ProcessMemoryMB = if ($processInfo) { $processInfo.MemoryMB } else { "N/A" }
            ProcessThreads = if ($processInfo) { $processInfo.Threads } else { "N/A" }
        }
        
        $serviceResults += $result
    }
    catch {
        Write-Log "  ERROR: Service not found or inaccessible: $($_.Exception.Message)" "ERROR"
        $stats.Alerts += "Failed to check service: $serviceName"
    }
}

# Get system resource information
Write-Log "`n=== COLLECTING SYSTEM RESOURCES ===" "INFO"

$os = Get-CimInstance -ClassName Win32_OperatingSystem
$cpu = Get-CimInstance -ClassName Win32_Processor
$computer = Get-CimInstance -ClassName Win32_ComputerSystem

$systemInfo = [PSCustomObject]@{
    ComputerName = $env:COMPUTERNAME
    OS = $os.Caption
    LastBoot = $os.LastBootUpTime
    UptimeDays = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 2)
    CPULoad = $cpu.LoadPercentage
    TotalMemoryGB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
    FreeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    MemoryUsedPercent = [math]::Round((1 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize)) * 100, 1)
}

Write-Log "CPU Load: $($systemInfo.CPULoad)%"
Write-Log "Memory Used: $($systemInfo.MemoryUsedPercent)%"
Write-Log "Uptime: $($systemInfo.UptimeDays) days"

# Check for resource alerts
if ($systemInfo.CPULoad -gt 90) {
    $stats.Alerts += "CPU load critical: $($systemInfo.CPULoad)%"
    Write-Log "ALERT: High CPU usage" "WARNING"
}

if ($systemInfo.MemoryUsedPercent -gt 90) {
    $stats.Alerts += "Memory usage critical: $($systemInfo.MemoryUsedPercent)%"
    Write-Log "ALERT: High memory usage" "WARNING"
}

# Generate HTML Report
Write-Log "`n=== GENERATING REPORT ===" "INFO"

$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Service Health Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2c3e50; }
        h2 { color: #34495e; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th { background-color: #3498db; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .running { color: green; font-weight: bold; }
        .stopped { color: red; font-weight: bold; }
        .alert { background-color: #fff3cd; padding: 10px; margin: 10px 0; border-left: 4px solid #ffc107; }
        .summary { background-color: #e8f4f8; padding: 15px; margin: 20px 0; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>Service Health Check Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    <p><strong>Computer:</strong> $($systemInfo.ComputerName)</p>
    
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Services Monitored:</strong> $($stats.TotalServices)</p>
        <p><strong>Running:</strong> <span style="color: green;">$($stats.Running)</span></p>
        <p><strong>Stopped:</strong> <span style="color: red;">$($stats.Stopped)</span></p>
        <p><strong>Dependency Issues:</strong> $($stats.DependencyIssues)</p>
        <p><strong>Alerts:</strong> $($stats.Alerts.Count)</p>
    </div>
    
    $(if ($stats.Alerts.Count -gt 0) {
        "<h2>Alerts</h2>"
        foreach ($alert in $stats.Alerts) {
            "<div class='alert'>⚠️ $alert</div>"
        }
    })
    
    <h2>System Resources</h2>
    <table>
        <tr><th>Metric</th><th>Value</th></tr>
        <tr><td>Operating System</td><td>$($systemInfo.OS)</td></tr>
        <tr><td>Last Boot</td><td>$($systemInfo.LastBoot)</td></tr>
        <tr><td>Uptime</td><td>$($systemInfo.UptimeDays) days</td></tr>
        <tr><td>CPU Load</td><td>$($systemInfo.CPULoad)%</td></tr>
        <tr><td>Total Memory</td><td>$($systemInfo.TotalMemoryGB) GB</td></tr>
        <tr><td>Free Memory</td><td>$($systemInfo.FreeMemoryGB) GB</td></tr>
        <tr><td>Memory Used</td><td>$($systemInfo.MemoryUsedPercent)%</td></tr>
    </table>
    
    <h2>Service Details</h2>
    <table>
        <tr>
            <th>Display Name</th>
            <th>Status</th>
            <th>Start Type</th>
            <th>CPU</th>
            <th>Memory (MB)</th>
            <th>Dependencies</th>
            <th>Issues</th>
        </tr>
        $(foreach ($svc in $serviceResults) {
            $statusClass = if ($svc.StatusOK) { "running" } else { "stopped" }
            "<tr>
                <td>$($svc.DisplayName)</td>
                <td class='$statusClass'>$($svc.Status)</td>
                <td>$($svc.StartType)</td>
                <td>$($svc.ProcessCPU)</td>
                <td>$($svc.ProcessMemoryMB)</td>
                <td>$($svc.DependencyCount)</td>
                <td>$($svc.DependencyIssues)</td>
            </tr>"
        })
    </table>
    
    <p style="margin-top: 40px; color: #7f8c8d; font-size: 0.9em;">
        Report generated by Service Health Check Script
    </p>
</body>
</html>
"@

# Save HTML report
$htmlReport | Out-File -Path $reportFile -Encoding UTF8

Write-Log "Report saved: $reportFile" "SUCCESS"

# Display summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SERVICE HEALTH CHECK COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Services Running: $($stats.Running)/$($stats.TotalServices)" -ForegroundColor $(if ($stats.Stopped -eq 0) {"Green"} else {"Yellow"})
Write-Host "Alerts: $($stats.Alerts.Count)" -ForegroundColor $(if ($stats.Alerts.Count -eq 0) {"Green"} else {"Red"})
Write-Host "Report: $reportFile"
Write-Host "Log: $logFile"

Write-Log "=== SERVICE HEALTH CHECK COMPLETED ===" "INFO"

# Return results for further processing
return [PSCustomObject]@{
    Timestamp = Get-Date
    Services = $serviceResults
    SystemInfo = $systemInfo
    Alerts = $stats.Alerts
    ReportPath = $reportFile
}
