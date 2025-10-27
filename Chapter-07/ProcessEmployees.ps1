
Project Description: CSV Data Processing Script
Let's build a complete script that demonstrates everything you've learned: reading CSV files, processing data with loops, error handling, validation, and generating reports. This script processes employee data, validates it, and produces multiple output reports.

The scenario: HR provides a CSV file of employees. You need to validate the data, identify issues, generate username proposals, and create reports showing valid records, invalid records, and department summaries.

Using the script:
# Process employee data
.\ProcessEmployees.ps1 -InputFile "C:\Data\NewHires.csv"

# Specify custom output location
.\ProcessEmployees.ps1 -InputFile "C:\Data\NewHires.csv" -OutputFolder "C:\CustomReports"
