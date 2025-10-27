<#
.SYNOPSIS
    Employee Data Processing and Validation
.DESCRIPTION
    Processes employee CSV data, validates records, generates usernames,
    and produces detailed reports
.PARAMETER InputFile
    Path to input CSV file containing employee data
.PARAMETER OutputFolder
    Folder where reports will be saved
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile,
    
    [string]$OutputFolder = "C:\Reports\EmployeeProcessing"
)

# Ensure output folder exists
if (-not (Test-Path $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
    Write-Host "Created output folder: $OutputFolder" -ForegroundColor Cyan
}

# Verify input file exists
if (-not (Test-Path $InputFile)) {
    Write-Host "ERROR: Input file not found: $InputFile" -ForegroundColor Red
    exit 1
}

Write-Host "=== EMPLOYEE DATA PROCESSING ===" -ForegroundColor Cyan
Write-Host "Input: $InputFile"
Write-Host "Output: $OutputFolder"
Write-Host ""

# Import employee data
try {
    $employees = Import-Csv $InputFile -ErrorAction Stop
    Write-Host "Imported $($employees.Count) employee records" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Failed to import CSV: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize result collections
$validEmployees = @()
$invalidEmployees = @()
$departmentStats = @{}

# Process each employee
$currentRecord = 0

foreach ($employee in $employees) {
    $currentRecord++
    Write-Host "[$currentRecord/$($employees.Count)] Processing: $($employee.FirstName) $($employee.LastName)..." -NoNewline
    
    # Validation tracking
    $validationErrors = @()
    
    # Validate required fields
    if ([string]::IsNullOrWhiteSpace($employee.FirstName)) {
        $validationErrors += "Missing FirstName"
    }
    if ([string]::IsNullOrWhiteSpace($employee.LastName)) {
        $validationErrors += "Missing LastName"
    }
    if ([string]::IsNullOrWhiteSpace($employee.Department)) {
        $validationErrors += "Missing Department"
    }
    
    # Validate email format if provided
    if (-not [string]::IsNullOrWhiteSpace($employee.Email)) {
        if ($employee.Email -notmatch '^[\w\.-]+@[\w\.-]+\.\w+$') {
            $validationErrors += "Invalid email format"
        }
    }
    
    # Check if this record is valid
    if ($validationErrors.Count -eq 0) {
        # Generate username (first initial + lastname, lowercase)
        $username = ($employee.FirstName.Substring(0,1) + $employee.LastName).ToLower()
        
        # Create enhanced employee object
        $processedEmployee = [PSCustomObject]@{
            FirstName = $employee.FirstName
            LastName = $employee.LastName
            Department = $employee.Department
            Title = $employee.Title
            Email = $employee.Email
            ProposedUsername = $username
            ProcessedDate = Get-Date -Format "yyyy-MM-dd"
            Status = "Valid"
        }
        
        $validEmployees += $processedEmployee
        
        # Update department statistics
        if (-not $departmentStats.ContainsKey($employee.Department)) {
            $departmentStats[$employee.Department] = 0
        }
        $departmentStats[$employee.Department]++
        
        Write-Host " VALID" -ForegroundColor Green
    }
    else {
        # Record is invalid
        $invalidEmployee = [PSCustomObject]@{
            FirstName = $employee.FirstName
            LastName = $employee.LastName
            Department = $employee.Department
            Email = $employee.Email
            ValidationErrors = $validationErrors -join "; "
            Status = "Invalid"
        }
        
        $invalidEmployees += $invalidEmployee
        Write-Host " INVALID: $($validationErrors -join ', ')" -ForegroundColor Red
    }
}

# Generate timestamp for report files
$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"

# Export valid employees
if ($validEmployees.Count -gt 0) {
    $validFile = Join-Path $OutputFolder "ValidEmployees-$timestamp.csv"
    $validEmployees | Export-Csv $validFile -NoTypeInformation
    Write-Host "`nExported $($validEmployees.Count) valid records to: $validFile" -ForegroundColor Green
}

# Export invalid employees
if ($invalidEmployees.Count -gt 0) {
    $invalidFile = Join-Path $OutputFolder "InvalidEmployees-$timestamp.csv"
    $invalidEmployees | Export-Csv $invalidFile -NoTypeInformation
    Write-Host "Exported $($invalidEmployees.Count) invalid records to: $invalidFile" -ForegroundColor Yellow
}

# Generate department summary report
$deptSummary = foreach ($dept in $departmentStats.Keys) {
    [PSCustomObject]@{
        Department = $dept
        ValidEmployees = $departmentStats[$dept]
    }
}

if ($deptSummary) {
    $summaryFile = Join-Path $OutputFolder "DepartmentSummary-$timestamp.csv"
    $deptSummary | Sort-Object Department | Export-Csv $summaryFile -NoTypeInformation
    Write-Host "Exported department summary to: $summaryFile" -ForegroundColor Green
}

# Display final summary
Write-Host "`n" + ("=" * 50) -ForegroundColor Cyan
Write-Host "PROCESSING COMPLETE" -ForegroundColor Cyan
Write-Host ("=" * 50) -ForegroundColor Cyan
Write-Host "Total Records: $($employees.Count)"
Write-Host "Valid: $($validEmployees.Count)" -ForegroundColor Green
Write-Host "Invalid: $($invalidEmployees.Count)" -ForegroundColor Red
Write-Host "Departments: $($departmentStats.Keys.Count)"
Write-Host "`nAll reports saved to: $OutputFolder"

