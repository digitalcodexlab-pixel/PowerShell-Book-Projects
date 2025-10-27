#We'll build a complete, practical module you'll actually use—a collection of system administration utilities with proper organization, documentation, and deployment.

#Create the module structure:
$moduleName = "AdminTools"
$modulePath = "$env:USERPROFILE\Documents\PowerShell\Modules\$moduleName"

# Create module directory
New-Item -Path $modulePath -ItemType Directory -Force

# Create module file
$moduleFile = Join-Path $modulePath "$moduleName.psm1"

#Add useful functions to AdminTools.psm1:
function Get-QuickSystemInfo {
    <#
    .SYNOPSIS
        Gets essential system information quickly
    .EXAMPLE
        Get-QuickSystemInfo
    #>
    
    [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        OS = (Get-CimInstance Win32_OperatingSystem).Caption
        OSVersion = (Get-CimInstance Win32_OperatingSystem).Version
        MemoryGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
        Uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        LastBoot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    }
}

function Test-PortOpen {
    <#
    .SYNOPSIS
        Tests if a network port is open
    .EXAMPLE
        Test-PortOpen -ComputerName "SERVER01" -Port 80
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        
        [Parameter(Mandatory=$true)]
        [int]$Port,
        
        [int]$TimeoutSeconds = 2
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $result = $tcpClient.BeginConnect($ComputerName, $Port, $null, $null)
        $success = $result.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)
        
        if ($success) {
            $tcpClient.EndConnect($result)
            $tcpClient.Close()
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes timestamped log entries
    .EXAMPLE
        Write-Log "Operation completed" -Level INFO
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",
        
        [string]$LogFile = "$env:TEMP\AdminTools.log"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    
    Add-Content -Path $LogFile -Value $logEntry
    
    $color = switch($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    
    Write-Host $logEntry -ForegroundColor $color
}

# Export functions
Export-ModuleMember -Function Get-QuickSystemInfo, Test-PortOpen, Write-Log

#Create the manifest:
$manifestPath = Join-Path $modulePath "$moduleName.psd1"

New-ModuleManifest -Path $manifestPath `
    -RootModule "$moduleName.psm1" `
    -ModuleVersion "1.0.0" `
    -Author $env:USERNAME `
    -Description "Personal system administration utility functions" `
    -PowerShellVersion "5.1" `
    -FunctionsToExport @("Get-QuickSystemInfo", "Test-PortOpen", "Write-Log") `
    -Tags @("Administration", "Utilities", "Tools")

#Test your module:
# Import it
Import-Module AdminTools

# Test functions
Get-QuickSystemInfo
Test-PortOpen -ComputerName "google.com" -Port 80
Write-Log "Testing my new module" -Level SUCCESS

# Verify
Get-Command -Module AdminTools

#Create README documentation:
$readmePath = Join-Path $modulePath "README.md"
@"
# AdminTools Module

Personal system administration utilities.

## Functions

- **Get-QuickSystemInfo**: Returns essential system information
- **Test-PortOpen**: Tests network port connectivity  
- **Write-Log**: Creates timestamped log entries

## Installation

Copy to: `$env:USERPROFILE\Documents\PowerShell\Modules\AdminTools`

## Usage

``````powershell
Import-Module AdminTools
Get-QuickSystemInfo
"@ | Out-File $readmePath

<#
You've built a professional module with documentation, versioning, and useful functions. 
Add to it over time—when you write a useful function, add it here instead of leaving it scattered across scripts. 
This module becomes your personal toolkit, growing with your experience.
#>
