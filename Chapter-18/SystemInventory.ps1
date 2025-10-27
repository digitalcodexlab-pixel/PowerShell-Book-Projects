<#
.SYNOPSIS
    Advanced Log Analysis and Reporting Tool
.DESCRIPTION
    Parses application and system logs using regex patterns,
    extracts structured data, identifies errors and security events,
    detects anomalies, and generates comprehensive reports
.PARAMETER LogPath
    Path to log file or directory containing logs
.PARAMETER LogType
    Type of log format (Application, IIS, Apache, Security, Custom)
.PARAMETER StartDate
    Filter logs from this date forward
.PARAMETER EndDate
    Filter logs up to this date
.PARAMETER OutputPath
    Directory for generated reports
.PARAMETER IncludeStatistics
    Generate statistical analysis of log data
.NOTES
    REQUIRES: Read access to log files
    REQUIRES: Write access to output directory
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$LogPath,
    
    [ValidateSet("Application", "IIS", "Apache", "Security", "Custom")]
    [string]$LogType = "Application",
    
    [datetime]$StartDate,
    [datetime]$EndDate = (Get-Date),
    
    [string]$OutputPath = "C:\Reports\LogAnalysis",
    
    [switch]$IncludeStatistics
)

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$reportLog = Join-Path $OutputPath "Analysis-$timestamp.log"

function Write-AnalysisLog {
    param([string]$Message, [string]$Level = "INFO")
    
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" | Add-Content -Path $reportLog
    
    $color = @{
        "ERROR" = "Red"
        "WARNING" = "Yellow"
        "SUCCESS" = "Green"
        "INFO" = "Cyan"
    }[$Level]
    
    Write-Host $Message -ForegroundColor $color
}

# Define regex patterns for different log types
$LogPatterns = @{
    Application = @{
        Pattern = '(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(?<level>INFO|WARNING|ERROR|CRITICAL|DEBUG)\s*:\s*(?<message>.+)'
        Fields = @('timestamp', 'level', 'message')
    }
    IIS = @{
        Pattern = '(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(?<method>\w+)\s+(?<uri>[^\s]+)\s+-\s+(?<port>\d+)\s+-\s+(?<ip>[\d.]+)\s+.*?\s+(?<status>\d{3})\s+\d+\s+(?<timetaken>\d+)'
        Fields = @('timestamp', 'method', 'uri', 'ip', 'status', 'timetaken')
    }
    Apache = @{
        Pattern = '(?<ip>[\d.]+)\s+-\s+-\s+\[(?<timestamp>[^\]]+)\]\s+"(?<method>\w+)\s+(?<uri>[^\s]+)\s+[^"]+"\s+(?<status>\d{3})\s+(?<bytes>\d+)'
        Fields = @('ip', 'timestamp', 'method', 'uri', 'status', 'bytes')
    }
    Security = @{
        Pattern = '(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(?<eventtype>Logon|Logoff|Failed)\s+.*?user\s+(?<user>\w+)\s+.*?from\s+(?<ip>[\d.]+)'
        Fields = @('timestamp', 'eventtype', 'user', 'ip')
    }
    Custom = @{
        Pattern = '\[(?<timestamp>[^\]]+)\]\s+(?<level>\w+)\s+\[(?<component>[^\]]+)\]\s+(?<message>.+)'
        Fields = @('timestamp', 'level', 'component', 'message')
    }
}

# Additional extraction patterns
$ExtractionPatterns = @{
    IPAddress = '\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b'
    Email = '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'
    ErrorCode = 'ERR\d{3,5}|0x[0-9A-Fa-f]{8}|\b[1-5]\d{2}\b'
    URL = 'https?://[^\s<>"]+'
    FilePath = '[A-Z]:\\(?:[^\\/:*?"<>|\r\n]+\\)*[^\\/:*?"<>|\r\n]*'
}

function Get-LogEntries {
    param(
        [string]$Path,
        [hashtable]$Pattern
    )
    
    Write-AnalysisLog "Reading log file: $Path" "INFO"
    
    if (-not (Test-Path $Path)) {
        Write-AnalysisLog "Log file not found: $Path" "ERROR"
        return @()
    }
    
    $logContent = Get-Content -Path $Path -ErrorAction SilentlyContinue
    
    if (-not $logContent) {
        Write-AnalysisLog "Log file is empty or unreadable" "WARNING"
        return @()
    }
    
    Write-AnalysisLog "Parsing $($logContent.Count) log lines..." "INFO"
    
    $entries = @()
    $parseErrors = 0
    
    foreach ($line in $logContent) {
        if ($line -match $Pattern.Pattern) {
            $entry = @{
                RawLine = $line
            }
            
            foreach ($field in $Pattern.Fields) {
                $entry[$field] = $Matches[$field]
            }
            
            # Parse timestamp if present
            if ($entry.ContainsKey('timestamp')) {
                try {
                    $entry['TimestampParsed'] = [datetime]::Parse($entry['timestamp'])
                }
                catch {
                    $entry['TimestampParsed'] = $null
                }
            }
            
            $entries += [PSCustomObject]$entry
        }
        else {
            $parseErrors++
        }
    }
    
    Write-AnalysisLog "Successfully parsed: $($entries.Count) entries" "SUCCESS"
    if ($parseErrors -gt 0) {
        Write-AnalysisLog "Failed to parse: $parseErrors lines" "WARNING"
    }
    
    return $entries
}

function Get-ExtractedData {
    param(
        [array]$Entries,
        [string]$PatternName,
        [string]$Pattern
    )
    
    $extracted = @()
    
    foreach ($entry in $Entries) {
        $matches = [regex]::Matches($entry.RawLine, $Pattern)
        foreach ($match in $matches) {
            $extracted += [PSCustomObject]@{
                Type = $PatternName
                Value = $match.Value
                Timestamp = $entry.TimestampParsed
                Context = $entry.RawLine.Substring(0, [Math]::Min(100, $entry.RawLine.Length))
            }
        }
    }
    
    return $extracted
}

function Get-ErrorAnalysis {
    param([array]$Entries)
    
    $errors = $Entries | Where-Object { 
        $_.level -match 'ERROR|CRITICAL|FATAL' -or 
        $_.status -ge 400 -or
        $_.eventtype -eq 'Failed'
    }
    
    $analysis = @{
        TotalErrors = $errors.Count
        ErrorsByType = $errors | Group-Object level | Select-Object Name, Count
        ErrorsByHour = $errors | Where-Object TimestampParsed | Group-Object { $_.TimestampParsed.Hour } | Select-Object @{Name="Hour";Expression={$_.Name}}, Count
        TopErrors = $errors | Group-Object message | Sort-Object Count -Descending | Select-Object -First 10 Name, Count
    }
    
    return $analysis
}

function Get-SecurityAnalysis {
    param([array]$Entries)
    
    # Extract IP addresses
    $ips = @()
    foreach ($entry in $Entries) {
        if ($entry.PSObject.Properties['ip']) {
            $ips += $entry.ip
        }
        else {
            $matches = [regex]::Matches($entry.RawLine, $ExtractionPatterns['IPAddress'])
            $ips += $matches.Value
        }
    }
    
    # Failed logon detection
    $failedLogons = $Entries | Where-Object { 
        $_.RawLine -match 'failed|failure|denied|unauthorized' -and 
        $_.RawLine -match 'logon|login|auth'
    }
    
    # Suspicious activity patterns
    $suspiciousIPs = $ips | Group-Object | Where-Object Count -gt 100 | Select-Object Name, Count
    
    $analysis = @{
        UniqueIPs = ($ips | Select-Object -Unique).Count
        FailedLogons = $failedLogons.Count
        SuspiciousIPs = $suspiciousIPs
        FailedLogonsByIP = $failedLogons | ForEach-Object {
            if ($_ -match $ExtractionPatterns['IPAddress']) { $Matches[0] }
        } | Group-Object | Sort-Object Count -Descending | Select-Object -First 10 Name, Count
    }
    
    return $analysis
}

function New-HTMLReport {
    param(
        [array]$Entries,
        [hashtable]$ErrorAnalysis,
        [hashtable]$SecurityAnalysis,
        [hashtable]$Statistics
    )
    
    $reportPath = Join-Path $OutputPath "LogAnalysisReport-$timestamp.html"
    
    $errorRows = if ($ErrorAnalysis.TopErrors) {
        ($ErrorAnalysis.TopErrors | ForEach-Object {
            "<tr><td>$($_.Count)</td><td>$($_.Name)</td></tr>"
        }) -join "`n"
    } else { "<tr><td colspan='2'>No errors found</td></tr>" }
    
    $suspiciousIPRows = if ($SecurityAnalysis.SuspiciousIPs) {
        ($SecurityAnalysis.SuspiciousIPs | ForEach-Object {
            "<tr><td>$($_.Name)</td><td>$($_.Count)</td></tr>"
        }) -join "`n"
    } else { "<tr><td colspan='2'>No suspicious activity detected</td></tr>" }
    
    $statisticsSection = if ($Statistics) {
        @"
        <div class="section">
            <h2>📊 Statistics</h2>
            <div class="stats-grid">
                <div class="stat-card">
                    <h3>$($Statistics.TotalEntries)</h3>
                    <p>Total Log Entries</p>
                </div>
                <div class="stat-card">
                    <h3>$($Statistics.EntriesPerHour)</h3>
                    <p>Avg Entries/Hour</p>
                </div>
                <div class="stat-card">
                    <h3>$($Statistics.TimeSpan)</h3>
                    <p>Time Span</p>
                </div>
                <div class="stat-card">
                    <h3>$($Statistics.UniqueIPs)</h3>
                    <p>Unique IP Addresses</p>
                </div>
            </div>
        </div>
"@
    } else { "" }
    
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Log Analysis Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #2c3e50; }
        .section { background-color: #fff; padding: 20px; margin: 20px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .stats-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin: 20px 0; }
        .stat-card { background-color: #ecf0f1; padding: 20px; border-radius: 8px; text-align: center; }
        .stat-card h3 { margin: 0; font-size: 32px; color: #3498db; }
        .stat-card p { margin: 10px 0 0 0; color: #666; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th { background-color: #3498db; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .error { color: #e74c3c; font-weight: bold; }
        .warning { color: #f39c12; font-weight: bold; }
        .summary { background-color: #e8f4f8; padding: 15px; border-left: 4px solid #3498db; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>🔍 Log Analysis Report</h1>
    
    <div class="summary">
        <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Log Type:</strong> $LogType</p>
        <p><strong>Log File:</strong> $LogPath</p>
        <p><strong>Total Entries Analyzed:</strong> $($Entries.Count)</p>
    </div>
    
    $statisticsSection
    
    <div class="section">
        <h2>⚠️ Error Analysis</h2>
        <p><strong>Total Errors:</strong> <span class="error">$($ErrorAnalysis.TotalErrors)</span></p>
        
        <h3>Top 10 Error Messages</h3>
        <table>
            <tr><th>Count</th><th>Error Message</th></tr>
            $errorRows
        </table>
        
        <h3>Errors by Hour</h3>
        <table>
            <tr><th>Hour</th><th>Count</th></tr>
            $(if($ErrorAnalysis.ErrorsByHour) {
                ($ErrorAnalysis.ErrorsByHour | ForEach-Object { "<tr><td>$($_.Hour):00</td><td>$($_.Count)</td></tr>" }) -join "`n"
            } else { "<tr><td colspan='2'>No time-based data available</td></tr>" })
        </table>
    </div>
    
    <div class="section">
        <h2>🔒 Security Analysis</h2>
        <p><strong>Unique IP Addresses:</strong> $($SecurityAnalysis.UniqueIPs)</p>
        <p><strong>Failed Logon Attempts:</strong> <span class="error">$($SecurityAnalysis.FailedLogons)</span></p>
        
        <h3>Suspicious Activity (High Request Volume)</h3>
        <table>
            <tr><th>IP Address</th><th>Request Count</th></tr>
            $suspiciousIPRows
        </table>
        
        <h3>Top IPs with Failed Logons</h3>
        <table>
            <tr><th>IP Address</th><th>Failed Attempts</th></tr>
            $(if($SecurityAnalysis.FailedLogonsByIP) {
                ($SecurityAnalysis.FailedLogonsByIP | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.Count)</td></tr>" }) -join "`n"
            } else { "<tr><td colspan='2'>No failed logons detected</td></tr>" })
        </table>
    </div>
    
    <p style="margin-top: 40px; color: #7f8c8d; font-size: 0.9em;">
        Report generated by Log Analysis Tool | Detailed log: $reportLog
    </p>
</body>
</html>
"@
    
    $htmlReport | Out-File -Path $reportPath -Encoding UTF8
    return $reportPath
}

# Main execution
Write-AnalysisLog "=== LOG ANALYSIS STARTED ===" "INFO"
Write-AnalysisLog "Log Type: $LogType" "INFO"

# Get log pattern
$pattern = $LogPatterns[$LogType]

# Parse log entries
$entries = Get-LogEntries -Path $LogPath -Pattern $pattern

if ($entries.Count -eq 0) {
    Write-AnalysisLog "No log entries found or parsed. Exiting." "ERROR"
    exit 1
}

# Filter by date range if specified
if ($StartDate) {
    $entries = $entries | Where-Object { $_.TimestampParsed -ge $StartDate }
    Write-AnalysisLog "Filtered to entries after $StartDate : $($entries.Count) entries" "INFO"
}

$entries = $entries | Where-Object { $_.TimestampParsed -le $EndDate }

# Perform analysis
Write-AnalysisLog "`nPerforming error analysis..." "INFO"
$errorAnalysis = Get-ErrorAnalysis -Entries $entries

Write-AnalysisLog "Performing security analysis..." "INFO"
$securityAnalysis = Get-SecurityAnalysis -Entries $entries

# Calculate statistics if requested
$statistics = $null
if ($IncludeStatistics) {
    Write-AnalysisLog "Calculating statistics..." "INFO"
    $timestamps = $entries | Where-Object TimestampParsed | Select-Object -ExpandProperty TimestampParsed
    if ($timestamps) {
        $timeSpan = ($timestamps | Measure-Object -Maximum -Minimum)
        $hours = ($timeSpan.Maximum - $timeSpan.Minimum).TotalHours
        
        $statistics = @{
            TotalEntries = $entries.Count
            EntriesPerHour = if ($hours -gt 0) { [math]::Round($entries.Count / $hours, 1) } else { 0 }
            TimeSpan = "$([math]::Round($hours, 1)) hours"
            UniqueIPs = $securityAnalysis.UniqueIPs
        }
    }
}

# Generate reports
Write-AnalysisLog "`nGenerating HTML report..." "INFO"
$htmlReportPath = New-HTMLReport -Entries $entries -ErrorAnalysis $errorAnalysis -SecurityAnalysis $securityAnalysis -Statistics $statistics

# Export structured data
$jsonPath = Join-Path $OutputPath "LogData-$timestamp.json"
$entries | ConvertTo-Json -Depth 5 | Out-File -Path $jsonPath -Encoding UTF8

$csvPath = Join-Path $OutputPath "ErrorSummary-$timestamp.csv"
$errorAnalysis.TopErrors | Export-Csv -Path $csvPath -NoTypeInformation

# Summary
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "LOG ANALYSIS COMPLETE" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "Entries Analyzed: $($entries.Count)"
Write-Host "Errors Found: $($errorAnalysis.TotalErrors)"
Write-Host "Failed Logons: $($securityAnalysis.FailedLogons)"
Write-Host "`nReports Generated:"
Write-Host "  HTML Report: $htmlReportPath"
Write-Host "  JSON Data: $jsonPath"
Write-Host "  CSV Summary: $csvPath"
Write-Host "  Analysis Log: $reportLog"
Write-Host ("=" * 70) -ForegroundColor Cyan

Write-AnalysisLog "=== LOG ANALYSIS COMPLETED ===" "SUCCESS"

# Open HTML report
Start-Process $htmlReportPath