<#
.SYNOPSIS
    Advanced Email Notification System with Monitoring
.DESCRIPTION
    Monitors system health, generates formatted email notifications,
    supports templates, attachments, and multiple recipient groups.
    Uses .NET classes for robust email delivery.
.PARAMETER NotificationType
    Type of notification to send (Alert, Report, Summary, Custom)
.PARAMETER Recipients
    Email addresses to receive notifications
.PARAMETER SmtpServer
    SMTP server address
.PARAMETER SmtpPort
    SMTP server port (default 587)
.PARAMETER UseSSL
    Enable SSL for SMTP connection
.PARAMETER CredentialPath
    Path to encrypted credential file
.PARAMETER IncludeSystemReport
    Include detailed system report attachment
.PARAMETER Threshold
    Alert threshold for system metrics
.NOTES
    REQUIRES: SMTP server access
    REQUIRES: .NET Framework 4.5+
    REQUIRES: Credentials for authenticated SMTP
#>

param(
    [ValidateSet("Alert", "Report", "Summary", "Custom")]
    [string]$NotificationType = "Report",
    
    [Parameter(Mandatory=$true)]
    [string[]]$Recipients,
    
    [Parameter(Mandatory=$true)]
    [string]$SmtpServer,
    
    [int]$SmtpPort = 587,
    
    [switch]$UseSSL = $true,
    
    [string]$CredentialPath,
    
    [switch]$IncludeSystemReport,
    
    [hashtable]$Threshold = @{
        CPUPercent = 80
        MemoryPercent = 85
        DiskPercent = 90
    }
)

$script:LogPath = "C:\Logs\EmailNotifications"
if (-not (Test-Path $script:LogPath)) {
    [System.IO.Directory]::CreateDirectory($script:LogPath) | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$logFile = [System.IO.Path]::Combine($script:LogPath, "EmailLog-$timestamp.log")

function Write-NotificationLog {
    param([string]$Message, [string]$Level = "INFO")
    
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    [System.IO.File]::AppendAllText($logFile, "$logEntry`n")
    
    $color = @{
        "ERROR" = "Red"
        "WARNING" = "Yellow"
        "SUCCESS" = "Green"
        "INFO" = "Cyan"
    }[$Level]
    
    Write-Host $Message -ForegroundColor $color
}

function Get-SystemHealthData {
    Write-NotificationLog "Collecting system health data..." "INFO"
    
    try {
        # Collect system information using .NET and CIM
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        $cpu = Get-CimInstance -ClassName Win32_Processor
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3"
        
        # Calculate metrics
        $memoryUsedPercent = [math]::Round((1 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize)) * 100, 1)
        $cpuLoad = $cpu.LoadPercentage
        
        # Disk information
        $diskInfo = @()
        foreach ($disk in $disks) {
            $percentFree = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
            $percentUsed = 100 - $percentFree
            
            $diskInfo += [PSCustomObject]@{
                Drive = $disk.DeviceID
                TotalGB = [math]::Round($disk.Size / 1GB, 2)
                FreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
                PercentUsed = $percentUsed
                Status = if ($percentUsed -gt $Threshold.DiskPercent) { "Critical" } else { "OK" }
            }
        }
        
        # Determine overall health status
        $alerts = @()
        $status = "Healthy"
        
        if ($memoryUsedPercent -gt $Threshold.MemoryPercent) {
            $alerts += "Memory usage critical: $memoryUsedPercent%"
            $status = "Warning"
        }
        
        if ($cpuLoad -gt $Threshold.CPUPercent) {
            $alerts += "CPU load high: $cpuLoad%"
            $status = "Warning"
        }
        
        $criticalDisks = $diskInfo | Where-Object Status -eq "Critical"
        if ($criticalDisks) {
            $alerts += "Disk space critical on: $(($criticalDisks.Drive) -join ', ')"
            $status = "Critical"
        }
        
        $healthData = [PSCustomObject]@{
            ComputerName = $cs.Name
            CollectionTime = Get-Date
            OS = $os.Caption
            OSVersion = $os.Version
            Uptime = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
            TotalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
            MemoryUsedPercent = $memoryUsedPercent
            CPULoad = $cpuLoad
            Disks = $diskInfo
            Status = $status
            Alerts = $alerts
        }
        
        Write-NotificationLog "Health data collected: Status=$status" "SUCCESS"
        return $healthData
    }
    catch {
        Write-NotificationLog "Failed to collect health data: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function New-HTMLEmailBody {
    param(
        [PSCustomObject]$HealthData,
        [string]$NotificationType
    )
    
    $statusColor = switch ($HealthData.Status) {
        "Healthy" { "#27ae60" }
        "Warning" { "#f39c12" }
        "Critical" { "#e74c3c" }
        default { "#95a5a6" }
    }
    
    $diskRows = ($HealthData.Disks | ForEach-Object {
        $rowColor = if ($_.Status -eq "Critical") { "background-color: #fadbd8;" } else { "" }
        "<tr style='$rowColor'>
            <td>$($_.Drive)</td>
            <td>$($_.TotalGB) GB</td>
            <td>$($_.FreeGB) GB</td>
            <td>$($_.PercentUsed)%</td>
            <td style='color: $(if($_.Status -eq "Critical"){"#e74c3c"}else{"#27ae60"})'>$($_.Status)</td>
        </tr>"
    }) -join "`n"
    
    $alertSection = if ($HealthData.Alerts.Count -gt 0) {
        @"
        <div class="alert-section">
            <h3>⚠️ Active Alerts</h3>
            <ul>
                $(($HealthData.Alerts | ForEach-Object { "<li>$_</li>" }) -join "`n")
            </ul>
        </div>
"@
    } else {
        "<div class='success-section'><p>✅ No alerts - All systems operating normally</p></div>"
    }
    
    $htmlBody = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid $statusColor; padding-bottom: 15px; }
        .status-badge { display: inline-block; padding: 8px 16px; border-radius: 4px; color: white; background-color: $statusColor; font-weight: bold; margin: 15px 0; }
        .metric-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; margin: 25px 0; }
        .metric-card { background-color: #ecf0f1; padding: 20px; border-radius: 6px; text-align: center; }
        .metric-card h3 { margin: 0; font-size: 28px; color: #3498db; }
        .metric-card p { margin: 10px 0 0 0; color: #7f8c8d; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background-color: #3498db; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f8f9fa; }
        .alert-section { background-color: #fadbd8; padding: 15px; border-left: 4px solid #e74c3c; margin: 20px 0; border-radius: 4px; }
        .success-section { background-color: #d5f4e6; padding: 15px; border-left: 4px solid #27ae60; margin: 20px 0; border-radius: 4px; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #7f8c8d; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🖥️ System Health Notification</h1>
        
        <div class="status-badge">Status: $($HealthData.Status)</div>
        
        <p><strong>Computer:</strong> $($HealthData.ComputerName)</p>
        <p><strong>Report Time:</strong> $($HealthData.CollectionTime.ToString('yyyy-MM-dd HH:mm:ss'))</p>
        <p><strong>Operating System:</strong> $($HealthData.OS)</p>
        <p><strong>Uptime:</strong> $($HealthData.Uptime) hours</p>
        
        $alertSection
        
        <h2>System Metrics</h2>
        <div class="metric-grid">
            <div class="metric-card">
                <h3>$($HealthData.MemoryUsedPercent)%</h3>
                <p>Memory Used</p>
            </div>
            <div class="metric-card">
                <h3>$($HealthData.CPULoad)%</h3>
                <p>CPU Load</p>
            </div>
            <div class="metric-card">
                <h3>$($HealthData.TotalMemoryGB) GB</h3>
                <p>Total Memory</p>
            </div>
        </div>
        
        <h2>Disk Information</h2>
        <table>
            <tr>
                <th>Drive</th>
                <th>Total Size</th>
                <th>Free Space</th>
                <th>Used %</th>
                <th>Status</th>
            </tr>
            $diskRows
        </table>
        
        <div class="footer">
            <p>This is an automated notification from the System Monitoring Service.</p>
            <p>Notification Type: $NotificationType | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
            <p>Log file: $logFile</p>
        </div>
    </div>
</body>
</html>
"@
    
    return $htmlBody
}

function New-SystemReportAttachment {
    param([PSCustomObject]$HealthData)
    
    Write-NotificationLog "Generating report attachment..." "INFO"
    
    $reportPath = [System.IO.Path]::Combine($script:LogPath, "SystemReport-$timestamp.txt")
    
    $reportContent = @"
SYSTEM HEALTH REPORT
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
================================================================================

SYSTEM INFORMATION
------------------
Computer Name: $($HealthData.ComputerName)
Operating System: $($HealthData.OS)
OS Version: $($HealthData.OSVersion)
System Uptime: $($HealthData.Uptime) hours
Overall Status: $($HealthData.Status)

RESOURCE UTILIZATION
--------------------
Total Memory: $($HealthData.TotalMemoryGB) GB
Memory Used: $($HealthData.MemoryUsedPercent)%
CPU Load: $($HealthData.CPULoad)%

DISK INFORMATION
----------------
$($HealthData.Disks | ForEach-Object {
"Drive: $($_.Drive) | Total: $($_.TotalGB) GB | Free: $($_.FreeGB) GB | Used: $($_.PercentUsed)% | Status: $($_.Status)"
} | Out-String)

ACTIVE ALERTS
-------------
$(if ($HealthData.Alerts.Count -gt 0) {
    $HealthData.Alerts -join "`n"
} else {
    "No alerts - All systems normal"
})

================================================================================
End of Report
"@
    
    [System.IO.File]::WriteAllText($reportPath, $reportContent)
    Write-NotificationLog "Report attachment created: $reportPath" "SUCCESS"
    
    return $reportPath
}

function Send-EmailNotification {
    param(
        [string[]]$To,
        [string]$Subject,
        [string]$HtmlBody,
        [string[]]$AttachmentPaths,
        [PSCredential]$Credential
    )
    
    Write-NotificationLog "Preparing email notification..." "INFO"
    
    $message = $null
    $smtp = $null
    $attachments = @()
    
    try {
        # Create message
        $message = New-Object System.Net.Mail.MailMessage
        $message.From = "system-monitoring@company.com"
        
        foreach ($recipient in $To) {
            $message.To.Add($recipient)
        }
        
        $message.Subject = $Subject
        $message.Body = $HtmlBody
        $message.IsBodyHtml = $true
        $message.Priority = [System.Net.Mail.MailPriority]::Normal
        
        # Add attachments if provided
        if ($AttachmentPaths) {
            foreach ($path in $AttachmentPaths) {
                if ([System.IO.File]::Exists($path)) {
                    $attachment = New-Object System.Net.Mail.Attachment($path)
                    $message.Attachments.Add($attachment)
                    $attachments += $attachment
                    Write-NotificationLog "  Added attachment: $path" "INFO"
                }
            }
        }
        
        # Configure SMTP client
        $smtp = New-Object System.Net.Mail.SmtpClient($SmtpServer, $SmtpPort)
        $smtp.EnableSsl = $UseSSL
        
        if ($Credential) {
            $smtp.Credentials = $Credential
        }
        
        # Send email
        Write-NotificationLog "Sending email to: $($To -join ', ')" "INFO"
        $smtp.Send($message)
        
        Write-NotificationLog "Email sent successfully" "SUCCESS"
        return $true
    }
    catch {
        Write-NotificationLog "Failed to send email: $($_.Exception.Message)" "ERROR"
        return $false
    }
    finally {
        # Cleanup
        if ($attachments) {
            foreach ($attachment in $attachments) {
                $attachment.Dispose()
            }
        }
        
        if ($message) {
            $message.Dispose()
        }
        
        if ($smtp) {
            $smtp.Dispose()
        }
    }
}

# Main execution
Write-NotificationLog "=== EMAIL NOTIFICATION SYSTEM STARTED ===" "INFO"
Write-NotificationLog "Notification Type: $NotificationType" "INFO"
Write-NotificationLog "Recipients: $($Recipients -join ', ')" "INFO"

# Get credentials
$credential = $null
if ($CredentialPath -and [System.IO.File]::Exists($CredentialPath)) {
    try {
        $credential = Import-Clixml -Path $CredentialPath
        Write-NotificationLog "Loaded credentials from file" "SUCCESS"
    }
    catch {
        Write-NotificationLog "Failed to load credentials: $($_.Exception.Message)" "WARNING"
    }
}

if (-not $credential) {
    Write-Host "`nSMTP credentials required" -ForegroundColor Yellow
    $credential = Get-Credential -Message "Enter SMTP credentials"
}

# Collect system health data
$healthData = Get-SystemHealthData

if (-not $healthData) {
    Write-NotificationLog "Cannot proceed without health data" "ERROR"
    exit 1
}

# Generate email body
$emailBody = New-HTMLEmailBody -HealthData $healthData -NotificationType $NotificationType

# Generate subject line based on status
$subject = switch ($healthData.Status) {
    "Critical" { "🔴 CRITICAL: System Health Alert - $($healthData.ComputerName)" }
    "Warning" { "⚠️ WARNING: System Health Notice - $($healthData.ComputerName)" }
    default { "✅ System Health Report - $($healthData.ComputerName)" }
}

# Prepare attachments
$attachmentPaths = @()
if ($IncludeSystemReport) {
    $reportPath = New-SystemReportAttachment -HealthData $healthData
    $attachmentPaths += $reportPath
}

# Send notification
$success = Send-EmailNotification -To $Recipients -Subject $subject -HtmlBody $emailBody -AttachmentPaths $attachmentPaths -Credential $credential

# Summary
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "EMAIL NOTIFICATION SYSTEM COMPLETE" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "System Status: $($healthData.Status)"
Write-Host "Alerts: $($healthData.Alerts.Count)"
Write-Host "Email Sent: $(if($success){'Yes'}else{'No'})"
Write-Host "Recipients: $($Recipients.Count)"
Write-Host "`nLog File: $logFile"
Write-Host ("=" * 70) -ForegroundColor Cyan

Write-NotificationLog "=== EMAIL NOTIFICATION SYSTEM COMPLETED ===" "SUCCESS"

# Return health data for further processing if needed
return $healthData
