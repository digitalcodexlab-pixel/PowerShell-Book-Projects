# Logging module (Modules/Logging.psm1):
# ✅ No special requirements
# WHERE TO RUN: Imported by main script
# WHAT THIS DOES: Provides centralized logging functionality

$script:LogPath = ""
$script:LogFile = ""

function Initialize-Logging {
    param([string]$LogDirectory)
    
    $script:LogPath = $LogDirectory
    
    if (-not (Test-Path $script:LogPath)) {
        New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null
    }
    
    $script:LogFile = Join-Path $script:LogPath "AdminToolkit-$(Get-Date -Format 'yyyy-MM-dd').log"
}

function Write-ToolkitLog {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    Add-Content -Path $script:LogFile -Value $logEntry
    
    $color = @{
        "INFO" = "Cyan"
        "WARNING" = "Yellow"
        "ERROR" = "Red"
        "SUCCESS" = "Green"
    }[$Level]
    
    Write-Host $logEntry -ForegroundColor $color
}

Export-ModuleMember -Function Initialize-Logging, Write-ToolkitLog
