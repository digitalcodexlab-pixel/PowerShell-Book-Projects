# Practical Project: Automated Log File Management
We'll build a complete log file management system that archives old logs, compresses them, cleans up space, and reports on actions taken—real-world automation you'd deploy in production environments.


## Using the script: Chapter-07/ProcessEmployees.ps1
 *Run with defaults*--->  .\ManageLogs.ps1


*Custom settings*--->  .\ManageLogs.ps1 -LogPath "C:\AppLogs" -DaysToKeepActive 14 -MaxArchiveSizeGB 50


*Schedule with Task Scheduler to run nightly*

**What this script demonstrates:**

This production-ready script combines CSV import/export, loops, validation, error handling, data collection, and reporting. It reads employee data, validates every field, generates usernames, tracks statistics, and produces three separate reports—valid employees ready for account creation, invalid employees requiring HR correction, and department summaries.

The script follows best practices: parameter validation, error handling, progress tracking, informative output, and timestamped reports. It's the kind of automation you'd actually deploy in production environments.

This project shows how concepts combine into useful tools. CSV import provides data. Loops process each record. Validation ensures data quality. Error tracking identifies problems. Export creates actionable reports. Together, they transform raw HR data into validated, actionable information ready for account provisioning.

