# PowerShell for System Administrators - Code Repository

Welcome to the official code repository for **"PowerShell for System Administrators"**. This repository contains all practical projects and code examples from the book.

## 📘 About This Repository

This repository provides production-ready PowerShell scripts and projects featured in the book. Each chapter folder includes:
- Complete, working code examples
- README with usage instructions
- Prerequisites and setup guidance

## 📂 Available Chapters

This repository contains code for chapters with substantial practical projects:

- **[Chapter 07](Chapter-07/)** - Working with Files and Data
- **[Chapter 10](Chapter-10/)** - Modules and Code Organization
- **[Chapter 11](Chapter-11/)** - File System Automation
- **[Chapter 12](Chapter-12/)** - Managing Services and Processes
- **[Chapter 13](Chapter-13/)** - Managing Users and Groups
- **[Chapter 14](Chapter-14/)** - Registry and System Configuration
- **[Chapter 15](Chapter-15/)** - Scheduled Tasks and Application Management
- **[Chapter 16](Chapter-16/)** - Remote Management
- **[Chapter 17](Chapter-17/)** - Event Logs and System Monitoring
- **[Chapter 18](Chapter-18/)** - Advanced Data Handling
- **[Chapter 19](Chapter-19/)** - Regular Expressions
- **[Chapter 20](Chapter-20/)** - Working with .NET and COM
- **[Chapter 25](Chapter-25/)** - [Chapter Title]

Each chapter folder contains its own README with detailed instructions.

## 🚀 Quick Start

### Download All Code

**Option 1: Download ZIP**
1. Click the green **"Code"** button above
2. Select **"Download ZIP"**
3. Extract to your preferred location

**Option 2: Clone with Git**
```powershell
git clone https://github.com/YourUsername/powershell-book-projects.git
cd powershell-book-projects
```

### Run a Script

```powershell
# Navigate to a chapter
cd Chapter-11

# Read the chapter README first
Get-Content README.md

# Run an example (after reviewing the code!)
.\ScriptName.ps1
```

## 📋 Prerequisites

- **Operating System**: Windows 10/11 or Windows Server 2016+
- **PowerShell**: Version 7.0 or later ([Download here](https://github.com/PowerShell/PowerShell))
- **Permissions**: Some scripts require administrator rights

### Installing PowerShell 7+

```powershell
# Check your current version
$PSVersionTable.PSVersion

# If below 7.0, download from:
# https://github.com/PowerShell/PowerShell/releases
```

## ⚠️ Important Notes

**Before running any script:**

1. ✅ **Review the code** - Understand what it does
2. ✅ **Check prerequisites** - Read the chapter README
3. ✅ **Test safely** - Run in a test environment first
4. ✅ **Administrator rights** - Some scripts require elevation
5. ✅ **Adjust paths** - Modify file paths to match your system

**Never run scripts blindly on production systems!**

## 🛠️ Usage Tips

### For Learning:
- Read the corresponding book chapter first
- Review the chapter README
- Examine the code with comments
- Run examples in a safe test environment
- Modify and experiment

### For Production:
- Test thoroughly before deployment
- Review security implications
- Adjust parameters for your environment
- Implement proper error handling
- Add logging as needed

## 🐛 Found an Issue?

If you encounter bugs or have suggestions:

1. **Open an Issue** on this repository
2. Include:
   - Chapter and script name
   - Error message (if applicable)
   - Your PowerShell version
   - Steps to reproduce
3. I'll respond within 48 hours

## 📖 Get the Book

[Add link to where readers can purchase your book]

## 📄 License

This code is provided for educational purposes. You may use and modify these scripts for learning and personal projects.

**Please note:** Some scripts perform system modifications. Always review and test before use.

## 📫 Contact

- **Author**: [Your Name]
- **Email**: [your.email@example.com]
- **Website**: [yourwebsite.com]

## 🙏 Acknowledgments

Thank you to all readers who have provided feedback and contributed improvements to these scripts!

---

**Last Updated**: October 2025  
**Book Version**: 1.0  
**Repository**: Code examples from "PowerShell for System Administrators"

---

## 💡 Quick Reference

### Common Commands

```powershell
# List all scripts in a chapter
Get-ChildItem Chapter-11 -Filter *.ps1 -Recurse

# Check script syntax without running
Get-Command -Syntax .\ScriptName.ps1

# View help for a script
Get-Help .\ScriptName.ps1 -Detailed

# Run with administrator rights
Start-Process powershell -Verb RunAs -ArgumentList "-File .\ScriptName.ps1"
```

### Need Help?

- 📖 Refer to the book chapter for detailed explanations
- 📝 Read the chapter README for specific instructions
- 🐛 Open an issue if you find a bug
- 💬 Check existing issues for solutions

---

**Happy Scripting!** 🚀
