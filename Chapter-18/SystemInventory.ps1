<#
.SYNOPSIS
    System Inventory Report with API Integration
.DESCRIPTION
    Collects system information from local and remote computers,
    enriches data with external API information, and generates
    reports in JSON, CSV, and HTML formats
.PARAMETER ComputerName
    Target computers for inventory collection
.PARAMETER IncludePublicIP
    Query external API for public IP information
.PARAMETER OutputPath
    Directory for generated reports
.PARAMETER OutputFormat
    Report formats to generate (JSON, CSV, HTML, All)
.NOTES
    REQUIRES: Internet connectivity for API features
    REQUIRES: WinRM enabled for remote computer queries
    REQUIRES: Administrator privileges for complete inventory
#>

param(
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    [switch]$IncludePublicIP,
    [string]$OutputPath = "C:\Reports\Inventory",
    [ValidateSet("JSON", "CSV", "HTML", "All")]
    [string]$OutputFormat = "All"
)

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$logFile = Join-Path $OutputPath "InventoryLog-$timestamp.log"

function Write-InventoryLog {
    param([string]$Message, [string]$Level = "INFO")
    
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" | Add-Content -Path $logFile
    
    $color = @{
        "ERROR" = "Red"
        "WARNING" = "Yellow"
        "SUCCESS" = "Green"
        "INFO" = "Cyan"
    }[$Level]
    
    Write-Host $Message -ForegroundColor $color
}

function Get-PublicIPInfo {
    # ⚠️ REQUIRES: Internet connectivity
    try {
        $response = Invoke-RestMethod -Uri "https://ipapi.co/json/" -Method Get -TimeoutSec 10 -ErrorAction Stop
        
        return [PSCustomObject]@{
            PublicIP = $response.ip
            City = $response.city
            Region = $response.region
            Country = $response.country_name
            ISP = $response.org
        }
    }
    catch {
        Write-InventoryLog "Failed to retrieve public IP info: $($_.Exception.Message)" "WARNING"
        return $null
    }
}

function Get-SystemInventory {
    param([string]$Computer)
    
    Write-InventoryLog "Collecting inventory from $Computer..." "INFO"
    
    try {
        # Collect system information via CIM
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $Computer -ErrorAction Stop
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $Computer -ErrorAction Stop
        $cpu = Get-CimInstance -ClassName Win32_Processor -ComputerName $Computer -ErrorAction Stop
        $bios = Get-CimInstance -ClassName Win32_BIOS -ComputerName $Computer -ErrorAction Stop
        
        # Collect disk information
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ComputerName $Computer -ErrorAction Stop
        $diskInfo = $disks | ForEach-Object {
            [PSCustomObject]@{
                Drive = $_.DeviceID
                SizeGB = [math]::Round($_.Size / 1GB, 2)
                FreeGB = [math]::Round($_.FreeSpace / 1GB, 2)
                PercentFree = [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
            }
        }
        
        # Collect network adapter information
        $adapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ComputerName $Computer -ErrorAction Stop
        $networkInfo = $adapters | ForEach-Object {
            [PSCustomObject]@{
                Description = $_.Description
                IPAddress = $_.IPAddress -join ", "
                MACAddress = $_.MACAddress
                Gateway = $_.DefaultIPGateway -join ", "
            }
        }
        
        # Collect installed software (top 20 by name)
        $software = Get-CimInstance -ClassName Win32_Product -ComputerName $Computer -ErrorAction SilentlyContinue |
            Select-Object Name, Version, Vendor -First 20
        
        # Build inventory object
        $inventory = [PSCustomObject]@{
            ComputerName = $Computer
            CollectionTime = Get-Date
            OperatingSystem = $os.Caption
            OSVersion = $os.Version
            OSArchitecture = $os.OSArchitecture
            Manufacturer = $cs.Manufacturer
            Model = $cs.Model
            SerialNumber = $bios.SerialNumber
            BIOSVersion = $bios.SMBIOSBIOSVersion
            TotalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
            FreeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
            CPUModel = $cpu.Name
            CPUCores = $cpu.NumberOfCores
            CPULogicalProcessors = $cpu.NumberOfLogicalProcessors
            LastBoot = $os.LastBootUpTime
            UptimeDays = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 2)
            Domain = $cs.Domain
            Disks = $diskInfo
            NetworkAdapters = $networkInfo
            InstalledSoftware = $software
            PublicIPInfo = $null
        }
        
        Write-InventoryLog "  Inventory collected successfully" "SUCCESS"
        return $inventory
    }
    catch {
        Write-InventoryLog "  Failed to collect inventory: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Main execution
Write-InventoryLog "=== SYSTEM INVENTORY COLLECTION STARTED ===" "INFO"
Write-InventoryLog "Target systems: $($ComputerName -join ', ')" "INFO"

# Collect inventory from all computers
$inventoryData = @()

foreach ($computer in $ComputerName) {
    $inventory = Get-SystemInventory -Computer $computer
    if ($inventory) {
        $inventoryData += $inventory
    }
}

# Enrich with public IP information if requested
if ($IncludePublicIP -and $inventoryData.Count -gt 0) {
    Write-InventoryLog "`nEnriching data with public IP information..." "INFO"
    $publicIPInfo = Get-PublicIPInfo
    
    if ($publicIPInfo) {
        # Add public IP info to each inventory record
        foreach ($inv in $inventoryData) {
            $inv.PublicIPInfo = $publicIPInfo
        }
        Write-InventoryLog "  Public IP enrichment completed" "SUCCESS"
    }
}

if ($inventoryData.Count -eq 0) {
    Write-InventoryLog "No inventory data collected. Exiting." "ERROR"
    exit 1
}

Write-InventoryLog "`nGenerating reports..." "INFO"

# Generate JSON report
if ($OutputFormat -in "JSON", "All") {
    $jsonPath = Join-Path $OutputPath "Inventory-$timestamp.json"
    
    # Create JSON with proper depth for nested objects
    $inventoryData | ConvertTo-Json -Depth 10 | Out-File -Path $jsonPath -Encoding UTF8
    
    Write-InventoryLog "  JSON report: $jsonPath" "SUCCESS"
}

# Generate CSV report (flattened data)
if ($OutputFormat -in "CSV", "All") {
    $csvPath = Join-Path $OutputPath "Inventory-$timestamp.csv"
    
    # Flatten complex objects for CSV
    $flatData = $inventoryData | ForEach-Object {
        [PSCustomObject]@{
            ComputerName = $_.ComputerName
            CollectionTime = $_.CollectionTime
            OS = $_.OperatingSystem
            OSVersion = $_.OSVersion
            Manufacturer = $_.Manufacturer
            Model = $_.Model
            SerialNumber = $_.SerialNumber
            TotalMemoryGB = $_.TotalMemoryGB
            FreeMemoryGB = $_.FreeMemoryGB
            CPUModel = $_.CPUModel
            CPUCores = $_.CPUCores
            UptimeDays = $_.UptimeDays
            Domain = $_.Domain
            DiskCount = $_.Disks.Count
            SoftwareCount = $_.InstalledSoftware.Count
            PublicIP = if ($_.PublicIPInfo) { $_.PublicIPInfo.PublicIP } else { "N/A" }
        }
    }
    
    $flatData | Export-Csv -Path $csvPath -NoTypeInformation
    
    Write-InventoryLog "  CSV report: $csvPath" "SUCCESS"
}

# Generate HTML report
if ($OutputFormat -in "HTML", "All") {
    $htmlPath = Join-Path $OutputPath "Inventory-$timestamp.html"
    
    # Build system rows
    $systemRows = foreach ($inv in $inventoryData) {
        $diskRows = ($inv.Disks | ForEach-Object {
            "<tr><td>$($_.Drive)</td><td>$($_.SizeGB) GB</td><td>$($_.FreeGB) GB</td><td>$($_.PercentFree)%</td></tr>"
        }) -join ""
        
        $networkRows = ($inv.NetworkAdapters | ForEach-Object {
            "<tr><td>$($_.Description)</td><td>$($_.IPAddress)</td><td>$($_.MACAddress)</td></tr>"
        }) -join ""
        
        $publicIPSection = if ($inv.PublicIPInfo) {
            "<p><strong>Public IP:</strong> $($inv.PublicIPInfo.PublicIP) ($($inv.PublicIPInfo.City), $($inv.PublicIPInfo.Country))</p>"
        } else {
            ""
        }
        
        @"
        <div class="system-card">
            <h2>$($inv.ComputerName)</h2>
            <div class="info-grid">
                <div>
                    <h3>System Information</h3>
                    <p><strong>OS:</strong> $($inv.OperatingSystem)</p>
                    <p><strong>Version:</strong> $($inv.OSVersion)</p>
                    <p><strong>Manufacturer:</strong> $($inv.Manufacturer)</p>
                    <p><strong>Model:</strong> $($inv.Model)</p>
                    <p><strong>Serial:</strong> $($inv.SerialNumber)</p>
                    <p><strong>Domain:</strong> $($inv.Domain)</p>
                    <p><strong>Uptime:</strong> $($inv.UptimeDays) days</p>
                    $publicIPSection
                </div>
                <div>
                    <h3>Hardware</h3>
                    <p><strong>CPU:</strong> $($inv.CPUModel)</p>
                    <p><strong>Cores:</strong> $($inv.CPUCores) ($($inv.CPULogicalProcessors) logical)</p>
                    <p><strong>Total Memory:</strong> $($inv.TotalMemoryGB) GB</p>
                    <p><strong>Free Memory:</strong> $($inv.FreeMemoryGB) GB</p>
                </div>
            </div>
            
            <h3>Disk Information</h3>
            <table>
                <tr><th>Drive</th><th>Size</th><th>Free</th><th>% Free</th></tr>
                $diskRows
            </table>
            
            <h3>Network Adapters</h3>
            <table>
                <tr><th>Description</th><th>IP Address</th><th>MAC Address</th></tr>
                $networkRows
            </table>
            
            <p><strong>Installed Software:</strong> $($inv.InstalledSoftware.Count) packages</p>
        </div>
"@
    }
    
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>System Inventory Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #2c3e50; }
        .summary { background-color: #fff; padding: 20px; margin: 20px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .system-card { background-color: #fff; padding: 20px; margin: 20px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 20px 0; }
        h2 { color: #3498db; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
        h3 { color: #34495e; margin-top: 20px; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th { background-color: #3498db; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        p { margin: 5px 0; }
        .timestamp { color: #7f8c8d; font-size: 0.9em; margin-top: 30px; }
    </style>
</head>
<body>
    <h1>📊 System Inventory Report</h1>
    
    <div class="summary">
        <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Systems Inventoried:</strong> $($inventoryData.Count)</p>
        <p><strong>Total Memory:</strong> $(($inventoryData | Measure-Object TotalMemoryGB -Sum).Sum) GB</p>
        <p><strong>Total Disks:</strong> $(($inventoryData.Disks | Measure-Object).Count)</p>
    </div>
    
    $($systemRows -join "`n")
    
    <p class="timestamp">Report generated by System Inventory Tool</p>
</body>
</html>
"@
    
    $htmlReport | Out-File -Path $htmlPath -Encoding UTF8
    
    Write-InventoryLog "  HTML report: $htmlPath" "SUCCESS"
}

# Summary
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "SYSTEM INVENTORY REPORT COMPLETE" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "Systems Inventoried: $($inventoryData.Count)"
Write-Host "Reports Generated: $OutputPath"
Write-Host "Log File: $logFile"

if ($IncludePublicIP -and $publicIPInfo) {
    Write-Host "`nPublic IP Information:" -ForegroundColor Cyan
    Write-Host "  IP: $($publicIPInfo.PublicIP)"
    Write-Host "  Location: $($publicIPInfo.City), $($publicIPInfo.Country)"
}

Write-Host ("=" * 70) -ForegroundColor Cyan

Write-InventoryLog "=== SYSTEM INVENTORY COLLECTION COMPLETED ===" "SUCCESS"

# Return inventory data
return $inventoryData
