# Practical Project: System Inventory Report from API
You'll build a comprehensive system inventory report that combines data from multiple sources—local WMI/CIM queries, web APIs for external data, and generates output in multiple formats—demonstrating real-world data handling automation.


## Using the inventory report tool:
```powershell

# Basic local inventory
.\SystemInventory.ps1

# Multiple systems with public IP lookup
.\SystemInventory.ps1 -ComputerName "SERVER01","SERVER02","WORKSTATION03" -IncludePublicIP

# Generate only JSON format
.\SystemInventory.ps1 -OutputFormat JSON

# Custom output location
.\SystemInventory.ps1 -OutputPath "D:\Reports" -OutputFormat All

```
This production-ready inventory system demonstrates comprehensive data handling: collecting structured data from CIM/WMI queries, enriching local data with external API information, handling complex nested data structures (disks, network adapters, software), converting between multiple formats (JSON, CSV, HTML), flattening complex objects for CSV compatibility, generating visual HTML reports with styling, comprehensive error handling and logging, and flexible output format selection. It combines local system queries, REST API integration, and multi-format reporting into unified inventory automation—real enterprise asset management solving operational data collection challenges.
