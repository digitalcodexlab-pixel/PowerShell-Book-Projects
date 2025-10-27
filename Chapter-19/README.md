# Practical Project: Log Analysis and Reporting Script
You'll build a comprehensive log analysis and reporting system that parses various log formats, extracts critical information using regex, identifies patterns and anomalies, and generates detailed reports—demonstrating production-ready log processing automation.


## Using the log analysis tool:
```powershell

# Analyze application log
.\LogAnalysis.ps1 -LogPath "C:\Logs\application.log" -LogType Application -IncludeStatistics

# Analyze IIS logs with date filter
.\LogAnalysis.ps1 -LogPath "C:\inetpub\logs\LogFiles\u_ex241006.log" -LogType IIS -StartDate "2024-10-06"

# Security log analysis
.\LogAnalysis.ps1 -LogPath "C:\Logs\security.log" -LogType Security -OutputPath "D:\Reports"

# Custom log format
.\LogAnalysis.ps1 -LogPath "C:\Logs\custom.log" -LogType Custom

```
This production-ready log analysis system demonstrates comprehensive regex usage: pattern-based log parsing for multiple formats, structured data extraction using capturing groups, error pattern detection and classification, security event identification and anomaly detection, statistical analysis of log patterns, multi-format output (HTML, JSON, CSV), and reusable pattern library for common data types. It transforms thousands of unstructured log lines into actionable intelligence—real operational insight for troubleshooting, security monitoring, and performance analysis.
