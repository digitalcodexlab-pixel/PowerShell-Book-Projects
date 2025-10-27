# Practical Project: Advanced Email Notification System
You'll build a comprehensive email notification system that monitors system health, generates HTML reports, handles multiple notification types, includes attachments, manages templates, and provides robust error handling—demonstrating production-ready .NET integration for operational automation.


## Using the email notification system:
```powershell

# Basic health report
.\EmailNotification.ps1 -Recipients "admin@company.com" -SmtpServer "smtp.gmail.com" -SmtpPort 587

# Alert with system report attachment
.\EmailNotification.ps1 -NotificationType Alert -Recipients "admin@company.com","manager@company.com" -SmtpServer "smtp.company.com" -IncludeSystemReport

# Custom thresholds
.\EmailNotification.ps1 -Recipients "ops@company.com" -SmtpServer "smtp.company.com" -Threshold @{CPUPercent=90; MemoryPercent=90; DiskPercent=95}

# Using saved credentials
# First, save credentials:
# Get-Credential | Export-Clixml -Path "C:\Secure\smtp-creds.xml"
.\EmailNotification.ps1 -Recipients "team@company.com" -SmtpServer "smtp.company.com" -CredentialPath "C:\Secure\smtp-creds.xml"

```
This production-ready notification system demonstrates comprehensive .NET integration: System.Net.Mail classes for robust email delivery, System.IO for efficient file operations and logging, HTML email generation with dynamic styling based on system status, health monitoring combining CIM queries with .NET processing, attachment handling for detailed reports, secure credential management with encrypted storage, comprehensive error handling and logging, template-based email formatting, threshold-based alerting, and modular design enabling reuse. It combines system monitoring, data collection, report generation, and email delivery into unified operational automation—real infrastructure notification solving monitoring and alerting challenges.
