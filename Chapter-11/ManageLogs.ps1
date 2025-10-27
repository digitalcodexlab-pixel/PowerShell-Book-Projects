<#
.SYNOPSIS
    Automated Log File Management System
.DESCRIPTION
    Manages log files by archiving old logs, compressing archives,
    cleaning up space, and generating reports
.PARAMETER LogPath
    Path containing log files to manage
.PARAMETER ArchivePath
    Path where archived logs are stored
.PARAMETER DaysToKeepActive
    Days to keep logs in active directory before archiving
.PARAMETER DaysToKeepArchive
    Days to keep archived logs before deletion
.PARAMETER MaxArchiveSizeGB
    Maximum archive folder size in GB
#>

param(
    [string]$LogPath = "C:\Logs",
    [string]$ArchivePath = "C:\Archive\Logs",
    [int]$DaysToKeepActive = 30,
    [int]$DaysToKeepArchive = 365,
    [double]$MaxArchiveSizeGB = 100
)

# Create log for this script's operations
$scriptLogPath = "C:\Logs\LogManagement"
$scriptLogFile = Join-Path $scriptLogPath "LogManagement-$(Get-Date -Format 'yyyy-MM-dd').log"

# Ensure script log directory exists
if (-not (Test-Path $scriptLogPath)) {
    New-Item -Path $scriptLogPath -ItemType Directory -Force | Out-Null
}

function Write-ScriptLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    
    Add-Content -Path $scriptLogFile -Value $logEntry
    
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
    FilesArchived = 0
    FilesCompressed = 0
    FilesDeleted = 0
    SpaceFreedMB = 0
    Errors = 0
}

Write-ScriptLog "=== LOG FILE MANAGEMENT STARTED ===" "INFO"
Write-ScriptLog "Active Logs Path: $LogPath"
Write-ScriptLog "Archive Path: $ArchivePath"
Write-ScriptLog "Days to keep active: $DaysToKeepActive"
Write-ScriptLog "Days to keep archive: $DaysToKeepArchive"

# Verify source path exists
if (-not (Test-Path $LogPath)) {
    Write-ScriptLog "Log path not found: $LogPath" "ERROR"
    exit 1
}

# Create archive path if needed
if (-not (Test-Path $ArchivePath)) {
    New-Item -Path $ArchivePath -ItemType Directory -Force | Out-Null
    Write-ScriptLog "Created archive directory: $ArchivePath" "INFO"
}

#region Archive Old Logs

Write-ScriptLog "`n=== ARCHIVING OLD LOGS ===" "INFO"

$archiveCutoff = (Get-Date).AddDays(-$DaysToKeepActive)
$logsToArchive = Get-ChildItem -Path $LogPath -Filter "*.log" -File | 
    Where-Object LastWriteTime -lt $archiveCutoff

Write-ScriptLog "Found $($logsToArchive.Count) logs older than $DaysToKeepActive days"

foreach ($log in $logsToArchive) {
    try {
        # Create year-month subfolder in archive
        $yearMonth = $log.LastWriteTime.ToString("yyyy-MM")
        $archiveSubPath = Join-Path $ArchivePath $yearMonth
        
        if (-not (Test-Path $archiveSubPath)) {
            New-Item -Path $archiveSubPath -ItemType Directory -Force | Out-Null
        }
        
        # Move log to archive
        $destination = Join-Path $archiveSubPath $log.Name
        Move-Item -Path $log.FullName -Destination $destination -Force -ErrorAction Stop
        
        Write-ScriptLog "Archived: $($log.Name) to $yearMonth" "SUCCESS"
        $stats.FilesArchived++
    }
    catch {
        Write-ScriptLog "Failed to archive $($log.Name): $($_.Exception.Message)" "ERROR"
        $stats.Errors++
    }
}

#endregion

#region Compress Archives

Write-ScriptLog "`n=== COMPRESSING ARCHIVE FOLDERS ===" "INFO"

# Get month folders in archive
$archiveFolders = Get-ChildItem -Path $ArchivePath -Directory

foreach ($folder in $archiveFolders) {
    try {
        $zipFileName = "$($folder.Name).zip"
        $zipPath = Join-Path $ArchivePath $zipFileName
        
        # Skip if already compressed
        if (Test-Path $zipPath) {
            Write-ScriptLog "Already compressed: $($folder.Name)" "INFO"
            continue
        }
        
        # Compress folder contents
        Write-ScriptLog "Compressing $($folder.Name)..." "INFO"
        Compress-Archive -Path "$($folder.FullName)\*" -DestinationPath $zipPath -CompressionLevel Optimal -ErrorAction Stop
        
        # Calculate space saved
        $originalSize = (Get-ChildItem -Path $folder.FullName -Recurse -File | 
            Measure-Object Length -Sum).Sum
        $compressedSize = (Get-Item $zipPath).Length
        $spaceSaved = $originalSize - $compressedSize
        $spaceSavedMB = [math]::Round($spaceSaved / 1MB, 2)
        
        # Delete original folder after successful compression
        Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop
        
        Write-ScriptLog "Compressed $($folder.Name) (saved $spaceSavedMB MB)" "SUCCESS"
        $stats.FilesCompressed++
        $stats.SpaceFreedMB += $spaceSavedMB
    }
    catch {
        Write-ScriptLog "Failed to compress $($folder.Name): $($_.Exception.Message)" "ERROR"
        $stats.Errors++
    }
}

#endregion

#region Delete Old Archives

Write-ScriptLog "`n=== DELETING OLD ARCHIVES ===" "INFO"

$deleteCutoff = (Get-Date).AddDays(-$DaysToKeepArchive)
$oldArchives = Get-ChildItem -Path $ArchivePath -Filter "*.zip" -File | 
    Where-Object LastWriteTime -lt $deleteCutoff

Write-ScriptLog "Found $($oldArchives.Count) archives older than $DaysToKeepArchive days"

foreach ($archive in $oldArchives) {
    try {
        $sizeMB = [math]::Round($archive.Length / 1MB, 2)
        Remove-Item -Path $archive.FullName -Force -ErrorAction Stop
        
        Write-ScriptLog "Deleted old archive: $($archive.Name) ($sizeMB MB)" "WARNING"
        $stats.FilesDeleted++
        $stats.SpaceFreedMB += $sizeMB
    }
    catch {
        Write-ScriptLog "Failed to delete $($archive.Name): $($_.Exception.Message)" "ERROR"
        $stats.Errors++
    }
}

#endregion

#region Check Archive Size Limits

Write-ScriptLog "`n=== CHECKING ARCHIVE SIZE LIMITS ===" "INFO"

$currentSize = (Get-ChildItem -Path $ArchivePath -Recurse -File | 
    Measure-Object Length -Sum).Sum
$currentSizeGB = [math]::Round($currentSize / 1GB, 2)

Write-ScriptLog "Current archive size: $currentSizeGB GB (limit: $MaxArchiveSizeGB GB)"

if ($currentSizeGB -gt $MaxArchiveSizeGB) {
    Write-ScriptLog "Archive size exceeds limit, removing oldest archives..." "WARNING"
    
    $archives = Get-ChildItem -Path $ArchivePath -Filter "*.zip" -File | 
        Sort-Object LastWriteTime
    
    foreach ($archive in $archives) {
        if ($currentSizeGB -le $MaxArchiveSizeGB) { break }
        
        $archiveSizeGB = $archive.Length / 1GB
        $archiveSizeMB = [math]::Round($archive.Length / 1MB, 2)
        
        Remove-Item -Path $archive.FullName -Force
        Write-ScriptLog "Removed oldest archive: $($archive.Name) ($archiveSizeMB MB)" "WARNING"
        
        $currentSizeGB -= $archiveSizeGB
        $stats.FilesDeleted++
        $stats.SpaceFreedMB += $archiveSizeMB
    }
    
    Write-ScriptLog "Archive size now: $currentSizeGB GB" "SUCCESS"
}

#endregion

#region Generate Summary Report

Write-ScriptLog "`n=== MANAGEMENT SUMMARY ===" "SUCCESS"
Write-ScriptLog "Files Archived: $($stats.FilesArchived)"
Write-ScriptLog "Folders Compressed: $($stats.FilesCompressed)"
Write-ScriptLog "Archives Deleted: $($stats.FilesDeleted)"
Write-ScriptLog "Space Freed: $($stats.SpaceFreedMB) MB"
Write-ScriptLog "Errors: $($stats.Errors)"

# Create summary report file
$reportPath = Join-Path $scriptLogPath "Summary-$(Get-Date -Format 'yyyy-MM-dd').txt"
@"
LOG MANAGEMENT SUMMARY
Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

STATISTICS
----------
Files Archived: $($stats.FilesArchived)
Folders Compressed: $($stats.FilesCompressed)
Archives Deleted: $($stats.FilesDeleted)
Space Freed: $($stats.SpaceFreedMB) MB
Errors Encountered: $($stats.Errors)

PATHS
-----
Active Logs: $LogPath
Archive Location: $ArchivePath
Current Archive Size: $currentSizeGB GB

POLICIES
--------
Days to Keep Active: $DaysToKeepActive
Days to Keep Archive: $DaysToKeepArchive
Max Archive Size: $MaxArchiveSizeGB GB
"@ | Out-File -Path $reportPath

Write-ScriptLog "Summary report saved: $reportPath"
Write-ScriptLog "=== LOG FILE MANAGEMENT COMPLETED ===" "SUCCESS"

#endregion
