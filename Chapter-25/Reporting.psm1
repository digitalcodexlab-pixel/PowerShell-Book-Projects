# Reporting module (Modules/Reporting.psm1):
# ✅ No special requirements
# WHERE TO RUN: Imported by main script
# WHAT THIS DOES: HTML report generation

function New-HealthReport {
    param(
        [PSCustomObject]$DiskData,
        [PSCustomObject]$ServiceData,
        [PSCustomObject]$MemoryData,
        [PSCustomObject]$EventData,
        [string]$OutputPath
    )
    
    $reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>System Health Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 30px; border-radius: 8px; }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background-color: #3498db; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f8f9fa; }
        .critical { color: #e74c3c; font-weight: bold; }
        .warning { color: #f39c12; font-weight: bold; }
        .healthy { color: #27ae60; font-weight: bold; }
        .header { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>System Health Report</h1>
        <div class="header">
            <strong>Computer:</strong> $env:COMPUTERNAME<br>
            <strong>Generated:</strong> $reportDate
        </div>
        
        <h2>Memory Status</h2>
        <table>
            <tr><th>Metric</th><th>Value</th></tr>
            <tr><td>Total Memory</td><td>$($MemoryData.TotalGB) GB</td></tr>
            <tr><td>Used Memory</td><td>$($MemoryData.UsedGB) GB</td></tr>
            <tr><td>Free Memory</td><td>$($MemoryData.FreeGB) GB</td></tr>
            <tr><td>Percent Used</td><td class="$($MemoryData.Status.ToLower())">$($MemoryData.PercentUsed)%</td></tr>
            <tr><td>Status</td><td class="$($MemoryData.Status.ToLower())">$($MemoryData.Status)</td></tr>
        </table>
        
        <h2>Disk Space</h2>
        <table>
            <tr><th>Drive</th><th>Total (GB)</th><th>Used (GB)</th><th>Free (GB)</th><th>% Used</th><th>Status</th></tr>
            $(($DiskData | ForEach-Object {
                "<tr>
                    <td>$($_.Drive)</td>
                    <td>$($_.TotalGB)</td>
                    <td>$($_.UsedGB)</td>
                    <td>$($_.FreeGB)</td>
                    <td>$($_.PercentUsed)%</td>
                    <td class=`"$($_.Status.ToLower())`">$($_.Status)</td>
                </tr>"
            }) -join "`n")
        </table>
        
        <h2>Service Status</h2>
        <table>
            <tr><th>Service Name</th><th>Display Name</th><th>Status</th><th>Start Type</th><th>Health</th></tr>
            $(($ServiceData | ForEach-Object {
                "<tr>
                    <td>$($_.ServiceName)</td>
                    <td>$($_.DisplayName)</td>
                    <td>$($_.Status)</td>
                    <td>$($_.StartType)</td>
                    <td class=`"$($_.Health.ToLower())`">$($_.Health)</td>
                </tr>"
            }) -join "`n")
        </table>
        
        <h2>Recent System Errors</h2>
        <table>
            <tr><th>Time</th><th>Source</th><th>Event ID</th><th>Message</th></tr>
            $(if ($EventData) {
                ($EventData | ForEach-Object {
                    "<tr>
                        <td>$($_.TimeGenerated)</td>
                        <td>$($_.Source)</td>
                        <td>$($_.EventID)</td>
                        <td>$($_.Message.Substring(0, [Math]::Min(100, $_.Message.Length)))...</td>
                    </tr>"
                }) -join "`n"
            } else {
                "<tr><td colspan='4'>No errors found</td></tr>"
            })
        </table>
    </div>
</body>
</html>
"@
    
    $reportFile = Join-Path $OutputPath "HealthReport-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
    $html | Out-File $reportFile -Encoding UTF8
    
    return $reportFile
}

Export-ModuleMember -Function New-HealthReport
