<#
.SYNOPSIS
    New Employee Onboarding Automation
.DESCRIPTION
    Complete onboarding workflow: creates AD account, assigns groups,
    creates home directory with permissions, generates welcome documentation
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$FirstName,
    
    [Parameter(Mandatory=$true)]
    [string]$LastName,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("IT", "HR", "Sales", "Engineering")]
    [string]$Department,
    
    [Parameter(Mandatory=$true)]
    [string]$Title,
    
    [string]$Manager
)

# Environment configuration
$config = @{
    Domain = "company.com"
    UsersOU = "OU=Users,DC=company,DC=com"
    HomeDirectoryRoot = "\\FileServer\Home"
    LogPath = "C:\Logs\Onboarding"
}

# Department-specific settings
$deptConfig = @{
    IT = @{
        Groups = @("IT-Staff", "VPN-Users", "Admin-Tools-Access")
        HomeDriveQuotaGB = 50
    }
    HR = @{
        Groups = @("HR-Staff", "VPN-Users", "HRIS-Access")
        HomeDriveQuotaGB = 20
    }
    Sales = @{
        Groups = @("Sales-Team", "CRM-Users", "VPN-Users")
        HomeDriveQuotaGB = 30
    }
    Engineering = @{
        Groups = @("Engineering", "VPN-Users", "DevTools", "Source-Control")
        HomeDriveQuotaGB = 100
    }
}

# Logging setup
$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
if (-not (Test-Path $config.LogPath)) {
    New-Item -Path $config.LogPath -ItemType Directory | Out-Null
}
$logFile = Join-Path $config.LogPath "Onboarding-$timestamp.log"

function Write-OnboardingLog {
    param([string]$Message, [string]$Level = "INFO")
    
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" | 
        Add-Content -Path $logFile
    
    $color = @{
        "ERROR" = "Red"
        "WARNING" = "Yellow"  
        "SUCCESS" = "Green"
        "INFO" = "White"
    }[$Level]
    
    Write-Host $Message -ForegroundColor $color
}

# Generate account details
$username = ($FirstName.Substring(0,1) + $LastName).ToLower()
$displayName = "$FirstName $LastName"
$email = "$FirstName.$LastName@$($config.Domain)".ToLower()
$upn = "$username@$($config.Domain)"

Write-OnboardingLog "=== ONBOARDING: $displayName ===" "INFO"
Write-OnboardingLog "Username: $username | Email: $email" "INFO"

# Verify account doesn't exist
if (Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue) {
    Write-OnboardingLog "Account $username already exists" "ERROR"
    exit 1
}

# Generate secure temporary password
$passwordChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%"
$tempPassword = -join (1..16 | ForEach-Object { 
    $passwordChars[(Get-Random -Maximum $passwordChars.Length)] 
})
$securePassword = ConvertTo-SecureString $tempPassword -AsPlainText -Force

# Create AD account
Write-OnboardingLog "Creating Active Directory account..." "INFO"
try {
    $userParams = @{
        Name = $displayName
        GivenName = $FirstName
        Surname = $LastName
        SamAccountName = $username
        UserPrincipalName = $upn
        EmailAddress = $email
        Department = $Department
        Title = $Title
        Path = $config.UsersOU
        AccountPassword = $securePassword
        Enabled = $true
        ChangePasswordAtLogon = $true
    }
    
    # Add manager if specified
    if ($Manager) {
        $managerObj = Get-ADUser -Filter "SamAccountName -eq '$Manager'" -ErrorAction SilentlyContinue
        if ($managerObj) {
            $userParams.Manager = $managerObj.DistinguishedName
        }
    }
    
    New-ADUser @userParams -ErrorAction Stop
    Write-OnboardingLog "Account created successfully" "SUCCESS"
}
catch {
    Write-OnboardingLog "Account creation failed: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Assign to groups
Write-OnboardingLog "Configuring group memberships..." "INFO"
$assignedGroups = @()
foreach ($groupName in $deptConfig[$Department].Groups) {
    try {
        if (Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue) {
            Add-ADGroupMember -Identity $groupName -Members $username -ErrorAction Stop
            $assignedGroups += $groupName
            Write-OnboardingLog "  Added to: $groupName" "SUCCESS"
        }
    }
    catch {
        Write-OnboardingLog "  Failed to add to $groupName" "WARNING"
    }
}

# Create home directory
Write-OnboardingLog "Provisioning home directory..." "INFO"
$homeDir = Join-Path $config.HomeDirectoryRoot $username
try {
    New-Item -Path $homeDir -ItemType Directory -Force | Out-Null
    
    # Set NTFS permissions
    $acl = Get-Acl $homeDir
    $userPermission = "$($config.Domain)\$username", "FullControl", 
        "ContainerInherit,ObjectInherit", "None", "Allow"
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule $userPermission
    $acl.SetAccessRule($rule)
    Set-Acl -Path $homeDir -AclObject $acl
    
    # Map in AD
    Set-ADUser -Identity $username -HomeDrive "H:" -HomeDirectory $homeDir
    
    Write-OnboardingLog "Home directory: $homeDir" "SUCCESS"
}
catch {
    Write-OnboardingLog "Home directory creation failed" "WARNING"
}

# Generate welcome documentation
Write-OnboardingLog "Generating welcome documentation..." "INFO"
$welcomeDoc = @"
==========================================
WELCOME TO $(($config.Domain -split '\.')[0].ToUpper())
==========================================

Employee Information
--------------------
Name:        $displayName
Username:    $username
Email:       $email
Department:  $Department
Title:       $Title
Start Date:  $(Get-Date -Format "MMMM dd, yyyy")

Login Credentials
-----------------
Username: $username
Temporary Password: $tempPassword

⚠️ IMPORTANT: Change this password immediately at first login

Resources
---------
Home Directory: H:\ drive (mapped automatically)
Email Access:   https://mail.$($config.Domain)
VPN Portal:     https://vpn.$($config.Domain)

Group Access
------------
$($assignedGroups | ForEach-Object { "• $_" } | Out-String)

Next Steps
----------
1. Log in using credentials above
2. Change password when prompted
3. Configure email client
4. Review employee handbook
5. Complete orientation training

Support Contacts
----------------
IT Helpdesk: helpdesk@$($config.Domain)
HR Team:     hr@$($config.Domain)
Manager:     $(if ($Manager) { $Manager } else { "To be assigned" })

==========================================
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

$welcomeFile = Join-Path $config.LogPath "Welcome-$username-$timestamp.txt"
$welcomeDoc | Out-File -Path $welcomeFile -Encoding UTF8

# Display summary
Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "ONBOARDING COMPLETE" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Employee:      $displayName"
Write-Host "Username:      $username"
Write-Host "Email:         $email"
Write-Host "Department:    $Department"
Write-Host "Groups:        $($assignedGroups.Count) assigned"
Write-Host "Home Dir:      $homeDir"
Write-Host "`nWelcome Doc:   $welcomeFile" -ForegroundColor Green
Write-Host "`n⚠️  SECURELY DELIVER welcome document to employee" -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor Cyan

Write-OnboardingLog "=== ONBOARDING COMPLETED SUCCESSFULLY ===" "SUCCESS"

# Return details for further automation
return [PSCustomObject]@{
    Username = $username
    Email = $email
    DisplayName = $displayName
    Department = $Department
    Groups = $assignedGroups
    HomeDirectory = $homeDir
    WelcomeDocument = $welcomeFile
    Timestamp = Get-Date
}
