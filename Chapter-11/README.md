# Practical Project: Automated Log File Management
Let's build a complete log file management system that archives old logs, compresses them, cleans up space, and reports on actions taken—real-world automation you'd deploy in production environments.



## Using the script:
```powershell
# Run with defaults
.\ManageLogs.ps1


#Custom settings
.\ManageLogs.ps1 -LogPath "C:\AppLogs" -DaysToKeepActive 14 -MaxArchiveSizeGB 50


#Schedule with Task Scheduler to run nightly

```
This production-ready script demonstrates comprehensive file management: archiving by date, compression to save space, policy-based deletion, size limit enforcement, detailed logging, error handling, and summary reporting. It's the kind of automation that runs unattended in production, maintaining clean file systems without administrator intervention—real professional automation solving real operational problems.
