# Health check module (Modules/HealthCheck.psm1):
# ✅ No special requirements
# WHERE TO RUN: Imported by main script
# WHAT THIS DOES: System health checking functions

function Get-DiskSpaceInfo {
    param([hashtable]$Thresholds)
    
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null }
    
    $results = foreach ($drive in $drives) {
        $percentUsed = ($drive.Used / ($drive.Used + $drive.Free)) * 100
        
        $status = if ($percentUsed -ge $Thresholds.DiskSpaceCritical) {
            "Critical"
        } elseif ($percentUsed -ge $Thresholds.DiskSpaceWarning) {
            "Warning"
        } else {
            "Healthy"
        }
        
        [PSCustomObject]@{
            Drive = "$($drive.Name):"
            TotalGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
            UsedGB = [math]::Round($drive.Used / 1GB, 2)
            FreeGB = [math]::Round($drive.Free / 1GB, 2)
            PercentUsed = [math]::Round($percentUsed, 1)
            Status = $status
        }
    }
    
    return $results
}

function Get-ServiceStatus {
    param([string[]]$CriticalServices = @("wuauserv", "BITS", "Spooler"))
    
    $results = foreach ($serviceName in $CriticalServices) {
        try {
            $service = Get-Service $serviceName -ErrorAction Stop
            
            [PSCustomObject]@{
                ServiceName = $service.Name
                DisplayName = $service.DisplayName
                Status = $service.Status
                StartType = $service.StartType
                Health = if ($service.Status -eq "Running") { "Healthy" } else { "Warning" }
            }
        }
        catch {
            [PSCustomObject]@{
                ServiceName = $serviceName
                DisplayName = "N/A"
                Status = "NotFound"
                StartType = "N/A"
                Health = "Error"
            }
        }
    }
    
    return $results
}

function Get-EventLogErrors {
    param([int]$MaxEvents = 10)
    
    try {
        $events = Get-EventLog -LogName System -EntryType Error -Newest $MaxEvents -ErrorAction Stop
        
        $results = $events | Select-Object TimeGenerated, Source, EventID, Message
        return $results
    }
    catch {
        Write-Error "Failed to retrieve event logs: $_"
        return $null
    }
}

function Get-MemoryStatus {
    param([hashtable]$Thresholds)
    
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedMemoryGB = $totalMemoryGB - $freeMemoryGB
    $percentUsed = ($usedMemoryGB / $totalMemoryGB) * 100
    
    $status = if ($percentUsed -ge $Thresholds.MemoryCritical) {
        "Critical"
    } elseif ($percentUsed -ge $Thresholds.MemoryWarning) {
        "Warning"
    } else {
        "Healthy"
    }
    
    return [PSCustomObject]@{
        TotalGB = $totalMemoryGB
        UsedGB = $usedMemoryGB
        FreeGB = $freeMemoryGB
        PercentUsed = [math]::Round($percentUsed, 1)
        Status = $status
    }
}

Export-ModuleMember -Function Get-DiskSpaceInfo, Get-ServiceStatus, Get-EventLogErrors, Get-MemoryStatus
