

# ⚙️ Microservices Management Script

Powerful PowerShell automation for managing microservices in a .NET solution. This script helps you **scaffold**, **delete**, and **rename** microservices based on a reusable template structure — ideal for rapid microservice development using the [PlayTicket](https://github.com/mrnaddu/PlayTicket) architecture.

> 🛠️ Script: [`Manage-MicroServices.ps1`](./Manage-MicroServices.ps1)

---

## 🚀 Features

✅ Clone the base repository (`PlayTicket`)  
✅ Scaffold new microservices from a template  
✅ Automatically rename files, folders, and namespaces  
✅ Add services to the `.sln` and reference them in AppHost  
✅ Delete services cleanly and safely  
✅ Rename the entire solution structure interactively  

---

## 📦 Requirements

Make sure the following tools are installed and available in your system's `PATH`:

| Tool       | Purpose                   | Download                                      |
|------------|---------------------------|-----------------------------------------------|
| PowerShell | Script execution          | https://github.com/PowerShell/PowerShell     |
| Git        | Cloning repo              | https://git-scm.com                          |
| .NET SDK   | Managing projects/solutions| https://dotnet.microsoft.com/download        |

---

## 🧰 Getting Started

### 1. Clone This Repository

```bash
git clone https://github.com/mrnaddu/Micro-services-Script.git
cd Micro-services-Script
2. Run the Script
powershell
Copy code
powershell -ExecutionPolicy Bypass -File .\Manage-MicroServices.ps1
✅ The script will automatically clone the PlayTicket repository (if not already cloned) and guide you interactively.

✨ What This Script Does
🔧 Create Services
Prompts how many services to create

Accepts comma-separated service names (e.g. Inventory,Billing)

Copies from services/user template

Renames folders, files, and content (UserService → InventoryService, etc.)

Adds new .csproj files to the .sln and references them in the AppHost

Updates Program.cs to register the new services

🗑️ Delete Services
Lists existing services

Prompts which services to delete

Removes references from solution and Program.cs

Deletes associated service folders

🔄 Rename Solution
Interactively rename from PlayTicket to a new solution name

Updates:

Folder and file names

Code namespaces

.sln, .csproj, .json, .md content

🧪 Example
plaintext
Copy code
How many services would you like to create? 2
Enter 2 service name(s) (comma-separated, e.g., Inventory,Billing): Inventory,Billing

📁 Created service folder: services/inventory
📁 Created service folder: services/billing
✅ Added InventoryService to solution
✅ Added BillingService to solution

Would you like to rename the solution from 'PlayTicket'? (y/n): y
Enter new solution name: TicketPro
✅ Solution renamed to 'TicketPro'
🧠 Tips
✅ Use PascalCase for service names (e.g., UserProfile, ReportEngine)

🧪 Always test in a fresh copy or branch

🔄 Use version control to undo or inspect script changes

📁 Project Structure (After Scaffolding)
bash
Copy code
PlayTicket/
│
├── PlayTicket.sln
├── PlayTicket.AppHost/
│   └── Program.cs (auto-updated)
├── services/
│   ├── user/              # Template service
│   ├── inventory/         # Newly created
│   └── billing/           # Newly created
🧩 Advanced Ideas (Future Improvements)
Package as a PowerShell module

Add CLI arguments (non-interactive mode)

Integrate with dotnet new templates

Add unit tests for PowerShell functions

📄 License
MIT License — free to use, modify, and distribute.

🙏 Credits
Created and maintained by @mrnaddu
Designed to enhance productivity when building microservice solutions in .NET.

⭐️ Show Your Support
If you find this script helpful:

Star ⭐ the repo

Share it with your team

Suggest improvements or contribute via PR

Would you like me to help turn this into a PowerShell module or package it for distribution (e.g., PowerShell Gallery)?
