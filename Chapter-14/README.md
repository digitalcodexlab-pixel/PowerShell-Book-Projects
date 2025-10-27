# Practical Project: System Hardening Script
This project provides a comprehensive PowerShell script designed to automate the security hardening of Windows systems. The script configures a wide range of security settings, disables unnecessary or insecure features, and helps enforce organizational security policies.

It is designed to be "production-ready," meaning it includes features like logging, report generation, and a "report-only" mode that allows administrators to check system compliance without making any changes. This makes it a powerful tool for ensuring a consistent and secure baseline across multiple Windows machines.

## Using the hardening script:

```powershell
# Report mode - check settings without making changes
.\SystemHardening.ps1 -ReportOnly

# Apply hardening with all defaults
.\SystemHardening.ps1

# Skip Windows Update configuration
.\SystemHardening.ps1 -SkipWindowsUpdate

# Skip firewall verification
.\SystemHardening.ps1 -SkipFirewall
```

This system hardening script demonstrates production-ready security automation: comprehensive registry modifications, service management, feature control, configurable options via parameters, report-only mode for validation, detailed logging and HTML reporting, and modular design allowing selective application. It transforms hours of manual security configuration into a repeatable, auditable, two-minute operation that ensures consistent security posture across your environment.
