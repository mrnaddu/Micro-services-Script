# ===============================
# 🛠️ Utility Function: PascalCase
# ===============================
function To-PascalCase($text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }
    $parts = $text -split "[^a-zA-Z0-9]+" | Where-Object { $_ }
    return ($parts | ForEach-Object {
        if ($_.Length -eq 1) { $_.ToUpper() }
        else { $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower() }
    }) -join ""
}

# ===============================
# 🔍 Check Dependencies
# ===============================
function Check-Dependency($cmd, $friendlyName) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "❌ $friendlyName is not installed or not available in PATH." -ForegroundColor Red
        exit 1
    }
}
Check-Dependency "git" "Git"
Check-Dependency "dotnet" ".NET SDK"

# ===============================
# 🧠 Prompt Helpers
# ===============================
function Ask-YesNo($message) {
    $response = Read-Host "$message (y/n)"
    return ($response -match '^[Yy]$')
}

# ===============================
# 📁 Clone Repository
# ===============================
$repoUrl = "https://github.com/mrnaddu/PlayTicket.git"
$cloneDir = "PlayTicket"

if (-not (Test-Path $cloneDir)) {
    Write-Host "📥 Cloning repository..." -ForegroundColor Cyan
    git clone $repoUrl
} else {
    Write-Host "📦 Repository already exists." -ForegroundColor Yellow
}
Set-Location $cloneDir
Write-Host "✅ Welcome to the Microservices Manager" -ForegroundColor Green

# ===============================
# ⚙️ Setup Variables
# ===============================
$solutionBaseName = "PlayTicket"
$solutionFile = "$solutionBaseName.sln"
$appHostFolder = "$solutionBaseName.AppHost"
$appHostProject = "$appHostFolder/$solutionBaseName.AppHost.csproj"
$programFile = "$appHostFolder/Program.cs"
$templateSourceFolder = "services/user"

if (-not (Test-Path $templateSourceFolder)) {
    Write-Host "❌ Template source folder '$templateSourceFolder' not found." -ForegroundColor Red
    exit 1
}

# ===============================
# 🧩 Create Services
# ===============================
function Create-Services {
    param (
        [int]$count,
        [string[]]$names
    )
    for ($i = 0; $i -lt $count; $i++) {
        if ($i -ge $names.Length -or [string]::IsNullOrWhiteSpace($names[$i])) {
            Write-Host "Warning: Not enough service names provided. Skipping remaining services." -ForegroundColor Yellow
            break
        }
        $rawName = $names[$i].Trim()
        $pascalName = To-PascalCase $rawName
        $folderName = $rawName.ToLower()
        $targetFolder = "services/$folderName"

        if (Test-Path $targetFolder) {
            Write-Host "⚠️ Service '$folderName' already exists. Skipping..." -ForegroundColor Yellow
            continue
        }

        # Copy template
        Copy-Item $templateSourceFolder $targetFolder -Recurse -Force
        Write-Host "📁 Created service folder: $targetFolder" -ForegroundColor Green

        # Rename files/folders
        Get-ChildItem -Path $targetFolder -Recurse | Sort-Object -Descending -Property FullName | ForEach-Object {
            $newName = $_.Name -replace "UserService", "${pascalName}Service" -replace "User", "$pascalName"
            if ($_.Name -ne $newName) {
                try {
                    Rename-Item $_.FullName -NewName $newName -Force
                } catch {
                    Write-Host "Warning: Could not rename $($_.Name)" -ForegroundColor Yellow
                }
            }
        }

        # Update contents
        Get-ChildItem -Path $targetFolder -Recurse -File | ForEach-Object {
            try {
                $content = Get-Content $_.FullName -Raw
                $updated = $content -replace "PlayTicket\.UserService", "$solutionBaseName.${pascalName}Service" -replace "UserService", "${pascalName}Service" -replace "\bUser\b", "$pascalName"
                if ($content -ne $updated) {
                    Set-Content $_.FullName $updated
                }
            } catch {
                Write-Host "Warning: Could not update content of $($_.Name)" -ForegroundColor Yellow
            }
        }

        # Add projects to solution
        if (-not (Test-Path $solutionFile)) {
            dotnet new sln -n $solutionBaseName
        }
        Get-ChildItem -Path $targetFolder -Recurse -Include *.csproj | ForEach-Object {
            $projPath = $_.FullName
            dotnet sln $solutionFile add $projPath
            if (Test-Path $appHostProject) {
                dotnet add $appHostProject reference $projPath
            }
        }

        # Update Program.cs with builder.AddProject
        if (Test-Path $programFile) {
            $lineToAdd = "builder.AddProject<Projects.$($solutionBaseName)_$($pascalName)Service_HttpApi_Host>(`"$($solutionBaseName.ToLower())-$($folderName)service-httpapi-host`", launchProfileName: `"$solutionBaseName.$($pascalName)Service.Host`");"
            if (-not (Select-String -Path $programFile -Pattern $lineToAdd -SimpleMatch)) {
                $content = Get-Content $programFile -Raw
                $newContent = $content -replace 'builder\.Build\(\)\.Run\(\);', "$lineToAdd`r`nbuilder.Build().Run();"
                Set-Content $programFile $newContent
            }
        }

        Write-Host "Created and configured service: $pascalName" -ForegroundColor Cyan
    }
}

# === Prompt for service creation ===
$serviceCount = Read-Host "How many services would you like to create?"
while (-not ($serviceCount -as [int]) -or [int]$serviceCount -lt 1) {
    $serviceCount = Read-Host "Enter a number > 0"
}
$serviceCount = [int]$serviceCount

$defaultServices = "CashVoucher,Order,Profile"
$serviceInput = Read-Host "Enter $serviceCount service name(s) (comma-separated, e.g., $defaultServices)"
if ([string]::IsNullOrWhiteSpace($serviceInput)) {
    Write-Host "❌ No input provided. Exiting." -ForegroundColor Red
    exit 1
}
$servicesRaw = $serviceInput -split "," | ForEach-Object { $_.Trim() }
Create-Services -count $serviceCount -names $servicesRaw

# ===============================
# 🗑️ Optional: Delete Services
# ===============================
function Delete-Services {
    param([string[]]$serviceNames)

    foreach ($name in $serviceNames) {
        $folderName = $name.ToLower()
        $pascalName = To-PascalCase $name
        $folderPath = "services/$folderName"

        if (-not (Test-Path $folderPath)) {
            Write-Host "⚠️ Service folder '$folderPath' not found. Skipping..." -ForegroundColor Yellow
            continue
        }

        # Remove from solution and AppHost
        Get-ChildItem -Path $folderPath -Recurse -Include *.csproj | ForEach-Object {
            dotnet sln $solutionFile remove $_.FullName
            if (Test-Path $appHostProject) {
                dotnet remove $appHostProject reference $_.FullName
            }
        }

        # Remove from Program.cs
        if (Test-Path $programFile) {
            $pattern = "builder.AddProject<Projects.${solutionBaseName}_${pascalName}Service_HttpApi_Host>"
            $content = Get-Content $programFile
            $newContent = $content | Where-Object { $_ -notmatch $pattern }
            $newContent | Set-Content $programFile
        }

        # Delete folder
        Remove-Item -Path $folderPath -Recurse -Force
        Write-Host "🗑️ Deleted service '$folderName'" -ForegroundColor Green
    }
}

# === Prompt for deletion ===
Write-Host "`nAvailable services:" -ForegroundColor Cyan
Get-ChildItem -Path "services" -Directory | ForEach-Object { Write-Host "- $($_.Name)" -ForegroundColor Green }

$deleteInput = Read-Host "`nEnter service name(s) to delete (comma-separated) or 'none'"
if ($deleteInput -ne "none") {
    $toDelete = $deleteInput -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if ($toDelete.Count -gt 0 -and (Ask-YesNo "Are you sure you want to delete these service(s)?")) {
        Delete-Services -serviceNames $toDelete
    } else {
        Write-Host "❌ No valid services selected or operation cancelled." -ForegroundColor Yellow
    }
}

# ===============================
# ✏️ Rename Solution
# ===============================
if (Ask-YesNo "Rename solution from '$solutionBaseName'?") {
    $newName = To-PascalCase (Read-Host "Enter new solution name")
    if ($newName -and $newName -ne $solutionBaseName) {
        Write-Host "🔄 Renaming solution '$solutionBaseName' to '$newName'..." -ForegroundColor Cyan

        # 1. Update file contents
        Write-Host "🔍 Updating file contents..." -ForegroundColor Cyan
        $filesToUpdate = Get-ChildItem -Recurse -File -Include *.cs,*.csproj,*.json,*.sln,*.xml,*.md
        foreach ($file in $filesToUpdate) {
            try {
                $content = Get-Content $file.FullName -Raw
                $updated = $content -replace "\b$solutionBaseName\b", $newName
                if ($content -ne $updated) {
                    Set-Content $file.FullName $updated
                    Write-Host "✏️ Updated: $($file.FullName)" -ForegroundColor Gray
                }
            } catch {
                Write-Host "⚠️ Failed to update $($file.FullName)" -ForegroundColor Yellow
            }
        }

        # 2. Rename solution file
        if (Test-Path "$solutionBaseName.sln") {
            try {
                Rename-Item "$solutionBaseName.sln" "$newName.sln" -Force
                Write-Host "📄 Renamed solution file to '$newName.sln'" -ForegroundColor Green
            } catch {
                Write-Host "❌ Failed to rename solution file." -ForegroundColor Red
            }
        }

        # 3. Rename folders and files with solution name
        Write-Host "📁 Renaming folders and files containing '$solutionBaseName'..." -ForegroundColor Cyan
        Get-ChildItem -Recurse | Where-Object { $_.Name -like "*$solutionBaseName*" } |
        Sort-Object -Descending -Property FullName | ForEach-Object {
            try {
                $newItemName = $_.Name -replace "$solutionBaseName", $newName
                if ($_.Name -ne $newItemName) {
                    Rename-Item $_.FullName -NewName $newItemName -Force
                    Write-Host "✅ Renamed: $($_.FullName) → $newItemName" -ForegroundColor Gray
                }
            } catch {
                Write-Host "⚠️ Could not rename $($_.FullName)" -ForegroundColor Yellow
            }
        }

        # 4. Rename repo folder (if matches)
        $currentFolder = Split-Path -Leaf (Get-Location)
        if ($currentFolder -eq $solutionBaseName) {
            $parentFolder = Split-Path -Parent (Get-Location)
            try {
                Set-Location $parentFolder
                Rename-Item $solutionBaseName $newName -Force
                Set-Location "$parentFolder\$newName"
                Write-Host "📂 Renamed root folder to '$newName'" -ForegroundColor Green
            } catch {
                Write-Host "⚠️ Could not rename root folder." -ForegroundColor Yellow
                Set-Location "$parentFolder\$solutionBaseName"
            }
        }

        # Update in-memory solutionBaseName variable
        $solutionBaseName = $newName
        $solutionFile = "$solutionBaseName.sln"
        $appHostFolder = "$solutionBaseName.AppHost"
        $appHostProject = "$appHostFolder/$solutionBaseName.AppHost.csproj"
        $programFile = "$appHostFolder/Program.cs"

        Write-Host "✅ Solution successfully renamed to '$solutionBaseName'" -ForegroundColor Green
    } else {
        Write-Host "❌ Invalid or unchanged solution name. Skipping rename." -ForegroundColor Yellow
    }
}

# ===============================
# 🛠️ Final Build
# ===============================
Write-Host "`n🚧 Building the solution..." -ForegroundColor Cyan
dotnet build $solutionFile
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Build succeeded." -ForegroundColor Green
} else {
    Write-Host "❌ Build failed. Please check the output above." -ForegroundColor Red
}

Write-Host "`n🎉 Service management complete. All operations finished." -ForegroundColor Green

