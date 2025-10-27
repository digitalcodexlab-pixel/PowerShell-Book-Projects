<#
Main toolkit script (AdminToolkit.ps1):
#Requires -Version 5.1
# ✅ No special requirements for viewing menu
# ⚠️ REQUIRES: Administrator privileges for some operations (disk cleanup, service management)
# WHERE TO RUN: PowerShell
# WHAT THIS DOES: Main menu interface for admin toolkit
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Load configuration
$configPath = Join-Path $PSScriptRoot "Config\settings.json"
if (-not (Test-Path $configPath)) {
    Write-Host "Configuration file not found: $configPath" -ForegroundColor Red
    exit 1
}

$script:Config = Get-Content $configPath | ConvertFrom-Json

# Import modules
Import-Module (Join-Path $PSScriptRoot "Modules\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Modules\HealthCheck.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Modules\Reporting.psm1") -Force

# Initialize logging
Initialize-Logging -LogDirectory $script:Config.LogPath
Write-ToolkitLog "Admin Toolkit started" "INFO"

# Main menu function
function Show-MainMenu {
    Clear-Host
    Write-Host ""
    Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║    SYSTEM ADMINISTRATION TOOLKIT       ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. Check Disk Space" -ForegroundColor White
    Write-Host "  2. Check Service Status" -ForegroundColor White
    Write-Host "  3. Check Memory Usage" -ForegroundColor White
    Write-Host "  4. View Recent Errors" -ForegroundColor White
    Write-Host "  5. Generate Health Report" -ForegroundColor White
    Write-Host "  6. Clean Temporary Files" -ForegroundColor Yellow
    Write-Host "  7. Full System Check" -ForegroundColor Green
    Write-Host "  Q. Quit" -ForegroundColor Red
    Write-Host ""
    Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
}

# Menu loop
do {
    Show-MainMenu
    $choice = Read-Host "Select option"
    
    switch ($choice) {
        "1" {
            Write-Host "`nChecking disk space..." -ForegroundColor Cyan
            Write-ToolkitLog "Disk space check initiated" "INFO"
            
            $diskInfo = Get-DiskSpaceInfo -Thresholds $script:Config.HealthThresholds
            $diskInfo | Format-Table -AutoSize
            
            Write-ToolkitLog "Disk space check completed" "SUCCESS"
        }
        
        "2" {
            Write-Host "`nChecking service status..." -ForegroundColor Cyan
            Write-ToolkitLog "Service status check initiated" "INFO"
            
            $serviceInfo = Get-ServiceStatus
            $serviceInfo | Format-Table -AutoSize
            
            Write-ToolkitLog "Service status check completed" "SUCCESS"
        }
        
        "3" {
            Write-Host "`nChecking memory usage..." -ForegroundColor Cyan
            Write-ToolkitLog "Memory check initiated" "INFO"
            
            $memoryInfo = Get-MemoryStatus -Thresholds $script:Config.HealthThresholds
            $memoryInfo | Format-List
            
            Write-ToolkitLog "Memory check completed" "SUCCESS"
        }
        
        "4" {
            Write-Host "`nRetrieving recent errors..." -ForegroundColor Cyan
            Write-ToolkitLog "Event log check initiated" "INFO"
            
            $events = Get-EventLogErrors -MaxEvents 10
            if ($events) {
                $events | Format-Table TimeGenerated, Source, EventID -AutoSize
            } else {
                Write-Host "No recent errors found" -ForegroundColor Green
            }
            
            Write-ToolkitLog "Event log check completed" "SUCCESS"
        }
        
        "5" {
            Write-Host "`nGenerating health report..." -ForegroundColor Cyan
            Write-ToolkitLog "Health report generation initiated" "INFO"
            
            try {
                $diskData = Get-DiskSpaceInfo -Thresholds $script:Config.HealthThresholds
                $serviceData = Get-ServiceStatus
                $memoryData = Get-MemoryStatus -Thresholds $script:Config.HealthThresholds
                $eventData = Get-EventLogErrors -MaxEvents 10
                
                $reportPath = New-HealthReport -DiskData $diskData -ServiceData $serviceData `
                    -MemoryData $memoryData -EventData $eventData -OutputPath $script:Config.ReportPath
                
                Write-Host "Report generated: $reportPath" -ForegroundColor Green
                Write-ToolkitLog "Health report generated: $reportPath" "SUCCESS"
                
                $openReport = Read-Host "Open report in browser? (Y/N)"
                if ($openReport -eq "Y") {
                    Start-Process $reportPath
                }
            }
            catch {
                Write-Host "Report generation failed: $_" -ForegroundColor Red
                Write-ToolkitLog "Report generation failed: $_" "ERROR"
            }
        }
        
        "6" {
            Write-Host "`nCleaning temporary files..." -ForegroundColor Yellow
            Write-Host "WARNING: This will delete old temporary files" -ForegroundColor Yellow
            $confirm = Read-Host "Continue? (Y/N)"
            
            if ($confirm -eq "Y") {
                Write-ToolkitLog "Temp file cleanup initiated" "INFO"
                
                $totalCleaned = 0
                $retentionDate = (Get-Date).AddDays(-$script:Config.CleanupRetentionDays)
                
                foreach ($path in $script:Config.TempCleanupPaths) {
                    if (Test-Path $path) {
                        try {
                            $files = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue |
                                Where-Object LastWriteTime -lt $retentionDate
                            
                            $sizeMB = ($files | Measure-Object Length -Sum).Sum / 1MB
                            $files | Remove-Item -Force -ErrorAction SilentlyContinue
                            
                            $totalCleaned += $sizeMB
                            Write-Host "Cleaned $([math]::Round($sizeMB, 2)) MB from $path" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "Error cleaning $path : $_" -ForegroundColor Red
                        }
                    }
                }
                
                Write-Host "Total space cleaned: $([math]::Round($totalCleaned, 2)) MB" -ForegroundColor Green
                Write-ToolkitLog "Temp cleanup completed: $([math]::Round($totalCleaned, 2)) MB" "SUCCESS"
            }
        }
        
        "7" {
            Write-Host "`nRunning full system check..." -ForegroundColor Cyan
            Write-ToolkitLog "Full system check initiated" "INFO"
            
            Write-Progress -Activity "Full System Check" -Status "Checking disk space..." -PercentComplete 20
            $diskData = Get-DiskSpaceInfo -Thresholds $script:Config.HealthThresholds
            
            Write-Progress -Activity "Full System Check" -Status "Checking services..." -PercentComplete 40
            $serviceData = Get-ServiceStatus
            
            Write-Progress -Activity "Full System Check" -Status "Checking memory..." -PercentComplete 60
            $memoryData = Get-MemoryStatus -Thresholds $script:Config.HealthThresholds
            
            Write-Progress -Activity "Full System Check" -Status "Checking event logs..." -PercentComplete 80
            $eventData = Get-EventLogErrors -MaxEvents 10
            
            Write-Progress -Activity "Full System Check" -Status "Generating report..." -PercentComplete 90
            $reportPath = New-HealthReport -DiskData $diskData -ServiceData $serviceData `
                -MemoryData $memoryData -EventData $eventData -OutputPath $script:Config.ReportPath
            
            Write-Progress -Activity "Full System Check" -Completed
            
            Write-Host "`nSystem check completed!" -ForegroundColor Green
            Write-Host "Report: $reportPath" -ForegroundColor Cyan
            
            Write-ToolkitLog "Full system check completed" "SUCCESS"
            
            Start-Process $reportPath
        }
        
        "Q" {
            Write-Host "`nExiting Admin Toolkit..." -ForegroundColor Yellow
            Write-ToolkitLog "Admin Toolkit exited" "INFO"
            break
        }
        
        default {
            Write-Host "`nInvalid selection. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
    
    if ($choice -ne "Q") {
        Write-Host ""
        Read-Host "Press Enter to continue"
    }
    
} while ($choice -ne "Q")

Write-Host "Goodbye!" -ForegroundColor Cyan
