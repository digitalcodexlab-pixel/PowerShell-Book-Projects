# Practical Project: New Employee Onboarding Script
You'll build a complete employee onboarding system demonstrating professional automation. This script orchestrates user creation, group assignments, home directory setup, and documentation generation—real production automation.


## Using the onboarding script:
### Basic onboarding
.\New-EmployeeOnboarding.ps1 -FirstName "Sarah" -LastName "Connor" -Department "Engineering" -Title "Software Engineer"

### With manager assignment
.\New-EmployeeOnboarding.ps1 -FirstName "John" -LastName "Connor" -Department "IT" -Title "Systems Administrator" -Manager "skyle"

### Capture output for additional automation
$result = .\New-EmployeeOnboarding.ps1 -FirstName "Kyle" -LastName "Reese" -Department "Sales" -Title "Account Executive"

***Could trigger email notifications, ticketing system updates, etc.***

This onboarding automation demonstrates professional script development: parameterized configuration separating environment from logic, department-specific rules driving group assignments and quotas, comprehensive error handling at each step, detailed audit logging, security-conscious password handling, and structured output enabling integration with other systems. It transforms a multi-hour manual process into a consistent, auditable, two-minute operation.
