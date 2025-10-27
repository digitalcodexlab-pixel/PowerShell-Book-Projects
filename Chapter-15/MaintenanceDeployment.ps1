<#
.SYNOPSIS
    Automated System Maintenance and Application Deployment.

.DESCRIPTION
    Creates scheduled tasks for maintenance operations and deploys
    applications to remote computers with verification and reporting.

.PARAMETER ComputerName
    Target computers for deployment.

.PARAMETER InstallerPath
    Path to the application installer.

.PARAMETER CreateScheduledTasks
    A switch to create maintenance scheduled tasks.

.NOTES
    REQUIRES: Administrator privileges
    REQUIRES: WinRM enabled for remote deployment
    REQUIRES: Network access to target computers
#>
param(
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    [string]$InstallerPath,
    [switch]$CreateScheduledTasks
)

# ⚠️ Check for administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: Administrator privileges required" -ForegroundColor Red
    exit 1
}

# Configuration
$config = @{
    LogPath             = "C:\Logs\Maintenance"
    TempPath            = "C:\Temp"
    MaintenanceScriptPath = "C:\Scripts\Maintenance"
}

# Ensure directories exist
foreach ($path in $config.Values) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
}

$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$logFile = Join-Path $config.LogPath "Maintenance-$timestamp.log"

function Write-MaintenanceLog {
    param([string]$Message, [string]$Level = "INFO")

    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" | Add-Content -Path $logFile

    $color = @{
        "ERROR"   = "Red"
        "WARNING" = "Yellow"
        "SUCCESS" = "Green"
        "INFO"    = "Cyan"
    }[$Level]

    Write-Host $Message -ForegroundColor $color
}

Write-MaintenanceLog "=== MAINTENANCE AND DEPLOYMENT STARTED ===" "INFO"

#region Create Maintenance Scripts
if ($CreateScheduledTasks) {
    Write-MaintenanceLog "`n[1] Creating Maintenance Scripts" "INFO"

    # Disk Cleanup Script
    $diskCleanupScript = @'
# Automated Disk Cleanup Script
$logPath = "C:\Logs\Maintenance\DiskCleanup-$(Get-Date -Format 'yyyy-MM-dd').log"
"=== Disk Cleanup Started: $(Get-Date) ===" | Add-Content -Path $logPath

# Clean Windows Temp
$tempFiles = Get-ChildItem -Path $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue
$tempSize = ($tempFiles | Measure-Object Length -Sum).Sum / 1MB
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
"Cleaned temp files: $([math]::Round($tempSize, 2)) MB" | Add-Content -Path $logPath

# Clean old log files (older than 30 days)
$oldLogs = Get-ChildItem -Path "C:\Logs" -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object LastWriteTime -lt (Get-Date).AddDays(-30)
$logSize = ($oldLogs | Measure-Object Length -Sum).Sum / 1MB
$oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue
"Removed old logs: $([math]::Round($logSize, 2)) MB" | Add-Content -Path $logPath

"=== Disk Cleanup Completed: $(Get-Date) ===" | Add-Content -Path $logPath
'@
    $diskCleanupPath = Join-Path $config.MaintenanceScriptPath "DiskCleanup.ps1"
    $diskCleanupScript | Out-File -Path $diskCleanupPath -Force
    Write-MaintenanceLog "  Created: $diskCleanupPath" "SUCCESS"

    # System Health Check Script
    $healthCheckScript = @'
# Automated Health Check Script
$logPath = "C:\Logs\Maintenance\HealthCheck-$(Get-Date -Format 'yyyy-MM-dd').log"
"=== Health Check Started: $(Get-Date) ===" | Add-Content -Path $logPath

# Check disk space
$disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3"
foreach ($disk in $disks) {
    $percentFree = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
    $status = if ($percentFree -lt 10) { "CRITICAL" } elseif ($percentFree -lt 20) { "WARNING" } else { "OK" }
    "$($disk.DeviceID) - $percentFree% free - $status" | Add-Content -Path $logPath
}

# Check critical services
$services = @("wuauserv", "EventLog", "W32Time")
foreach ($svc in $services) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    $status = if ($service.Status -eq 'Running') { "OK" } else { "STOPPED" }
    "Service $svc - $status" | Add-Content -Path $logPath
}

# Check system uptime
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$uptime = (Get-Date) - $os.LastBootUpTime
"System Uptime: $($uptime.Days) days, $($uptime.Hours) hours" | Add-Content -Path $logPath

"=== Health Check Completed: $(Get-Date) ===" | Add-Content -Path $logPath
'@
    $healthCheckPath = Join-Path $config.MaintenanceScriptPath "HealthCheck.ps1"
    $healthCheckScript | Out-File -Path $healthCheckPath -Force
    Write-MaintenanceLog "  Created: $healthCheckPath" "SUCCESS"
}
#endregion

#region Create Scheduled Tasks
if ($CreateScheduledTasks) {
    Write-MaintenanceLog "`n[2] Creating Scheduled Tasks" "INFO"

    # Task 1: Daily Disk Cleanup
    try {
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$diskCleanupPath`""
        
        $trigger = New-ScheduledTaskTrigger -Daily -At "2:00AM"
        
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable
        
        Register-ScheduledTask -TaskName "DailyDiskCleanup" `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Description "Automated disk cleanup and log rotation" `
            -User "SYSTEM" `
            -Force | Out-Null
        
        Write-MaintenanceLog "  ✓ Created: DailyDiskCleanup task" "SUCCESS"
    }
    catch {
        Write-MaintenanceLog "  ✗ Failed to create DailyDiskCleanup: $($_.Exception.Message)" "ERROR"
    }

    # Task 2: Hourly Health Check
    try {
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$healthCheckPath`""
        
        $trigger = New-ScheduledTaskTrigger -Once -At "8:00AM" `
            -RepetitionInterval (New-TimeSpan -Hours 1) `
            -RepetitionDuration (New-TimeSpan -Hours 12)
        
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries
        
        Register-ScheduledTask -TaskName "HourlyHealthCheck" `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Description "Hourly system health verification" `
            -User "SYSTEM" `
            -Force | Out-Null
        
        Write-MaintenanceLog "  ✓ Created: HourlyHealthCheck task" "SUCCESS"
    }
    catch {
        Write-MaintenanceLog "  ✗ Failed to create HourlyHealthCheck: $($_.Exception.Message)" "ERROR"
    }

    # Task 3: Weekly Application Check
    try {
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-Command `"Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName, DisplayVersion | Export-Csv C:\Logs\Maintenance\InstalledApps-`$(Get-Date -Format 'yyyy-MM-dd').csv -NoTypeInformation`""
        
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "7:00AM"
        
        Register-ScheduledTask -TaskName "WeeklyAppInventory" `
            -Action $action `
            -Trigger $trigger `
            -Description "Weekly installed applications inventory" `
            -User "SYSTEM" `
            -Force | Out-Null
        
        Write-MaintenanceLog "  ✓ Created: WeeklyAppInventory task" "SUCCESS"
    }
    catch {
        Write-MaintenanceLog "  ✗ Failed to create WeeklyAppInventory: $($_.Exception.Message)" "ERROR"
    }
}
#endregion

#region Application Deployment
if ($InstallerPath) {
    Write-MaintenanceLog "`n[3] Deploying Application" "INFO"

    if (-not (Test-Path $InstallerPath)) {
        Write-MaintenanceLog "  Installer not found: $InstallerPath" "ERROR"
    }
    else {
        $deploymentResults = @()

        foreach ($computer in $ComputerName) {
            Write-MaintenanceLog "  Deploying to $computer..." "INFO"

            # Test connectivity
            if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet)) {
                Write-MaintenanceLog "    ✗ Unreachable" "ERROR"
                $deploymentResults += [PSCustomObject]@{Computer = $computer; Status = "Unreachable" }
                continue
            }

            try {
                # Copy installer
                $remotePath = "\\$computer\C$\Temp\$(Split-Path $InstallerPath -Leaf)"
                Copy-Item -Path $InstallerPath -Destination $remotePath -Force -ErrorAction Stop
                Write-MaintenanceLog "    ✓ Installer copied" "SUCCESS"

                # Install
                $installScript = {
                    param($Path)
                    $p = Start-Process "msiexec.exe" -ArgumentList "/i `"$Path`" /quiet /norestart" -Wait -PassThru
                    return $p.ExitCode
                }

                $exitCode = Invoke-Command -ComputerName $computer `
                    -ScriptBlock $installScript `
                    -ArgumentList "C:\Temp\$(Split-Path $InstallerPath -Leaf)" `
                    -ErrorAction Stop

                if ($exitCode -eq 0 -or $exitCode -eq 3010) {
                    Write-MaintenanceLog "    ✓ Installation successful" "SUCCESS"
                    $deploymentResults += [PSCustomObject]@{Computer = $computer; Status = "Success"; ExitCode = $exitCode }
                }
                else {
                    Write-MaintenanceLog "    ✗ Installation failed (Exit: $exitCode)" "ERROR"
                    $deploymentResults += [PSCustomObject]@{Computer = $computer; Status = "Failed"; ExitCode = $exitCode }
                }

                # Cleanup
                Remove-Item -Path $remotePath -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-MaintenanceLog "    ✗ Deployment error: $($_.Exception.Message)" "ERROR"
                $deploymentResults += [PSCustomObject]@{Computer = $computer; Status = "Error" }
            }
        }

        # Deployment summary
        Write-MaintenanceLog "`n  Deployment Summary:" "INFO"
        $deploymentResults | Format-Table -AutoSize | Out-String | Write-MaintenanceLog
    }
}
#endregion

#region Generate HTML Report
Write-MaintenanceLog "`n[4] Generating Report" "INFO"
$reportPath = Join-Path $config.LogPath "MaintenanceReport-$timestamp.html"
$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Maintenance and Deployment Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2c3e50; }
        .summary { background-color: #e8f4f8; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .success { color: green; font-weight: bold; }
        .error { color: red; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th { background-color: #3498db; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
    </style>
</head>
<body>
    <h1>Maintenance and Deployment Report</h1>
    <div class="summary">
        <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Computer:</strong> $env:COMPUTERNAME</p>
    </div>

    <h2>Operations Performed</h2>
    <ul>
        $(if ($CreateScheduledTasks) {"<li class='success'>Scheduled tasks created</li>"} else {"<li>Scheduled tasks: Skipped</li>"})
        $(if ($InstallerPath) {"<li class='success'>Application deployment executed</li>"} else {"<li>Application deployment: Skipped</li>"})
    </ul>

    <h2>Scheduled Tasks</h2>
    <p>The following automated maintenance tasks have been configured:</p>
    <ul>
        <li><strong>DailyDiskCleanup:</strong> Runs daily at 2:00 AM - Cleans temporary files and old logs</li>
        <li><strong>HourlyHealthCheck:</strong> Runs hourly from 8 AM to 8 PM - Monitors disk space and critical services</li>
        <li><strong>WeeklyAppInventory:</strong> Runs Monday at 7:00 AM - Exports installed applications list</li>
    </ul>

    <h2>Log Files</h2>
    <p>Detailed logs available at: <code>$logFile</code></p>
    
    <p style="margin-top: 40px; color: #7f8c8d; font-size: 0.9em;">
        Report generated by Automated Maintenance System
    </p>
</body>
</html>
"@
$htmlReport | Out-File -Path $reportPath -Encoding UTF8
Write-MaintenanceLog "  Report saved: $reportPath" "SUCCESS"
#endregion

# Final Summary
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "MAINTENANCE AND DEPLOYMENT COMPLETE" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
if ($CreateScheduledTasks) {
    Write-Host "Scheduled Tasks Created:" -ForegroundColor Green
    Get-ScheduledTask -TaskName "DailyDiskCleanup", "HourlyHealthCheck", "WeeklyAppInventory" -ErrorAction SilentlyContinue |
        Format-Table TaskName, State, @{Label = "NextRun"; Expression = { (Get-ScheduledTaskInfo $_).NextRunTime } } -AutoSize
}
if ($InstallerPath) {
    $successCount = ($deploymentResults | Where-Object Status -eq "Success").Count
    $foregroundColor = if ($successCount -eq $ComputerName.Count) { "Green" } else { "Yellow" }
    Write-Host "`nDeployment Results: $successCount / $($ComputerName.Count) successful" -ForegroundColor $foregroundColor
}
Write-Host "`nLog File: $logFile"
Write-Host "Report: $reportPath"
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-MaintenanceLog "=== MAINTENANCE AND DEPLOYMENT COMPLETED ===" "SUCCESS"

# Return summary object
return [PSCustomObject]@{
    Timestamp             = Get-Date
    ScheduledTasksCreated = $CreateScheduledTasks.IsPresent
    DeploymentExecuted    = [bool]$InstallerPath
    LogFile               = $logFile
    ReportPath            = $reportPath
    DeploymentResults     = $deploymentResults
}
