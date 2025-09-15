# ===============================
# 🛠️ Utility Function: PascalCase
# ===============================
function To-PascalCase($text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }
    $parts = $text -split "[^a-zA-Z0-9]+" | Where-Object { $_ }
    return ($parts | ForEach-Object { 
            if ($_.Length -eq 1) { $_.ToUpper() } 
            else { $_.Substring(0, 1).ToUpper() + $_.Substring(1).ToLower() } 
        }) -join ""
}

# split combined PascalCase words (e.g., "CoreOps" -> "Core", "Ops")
function Split-PascalCase($text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    
    # First, handle common abbreviations and numbers
    $words = @()
    $currentWord = ""
    
    for ($i = 0; $i -lt $text.Length; $i++) {
        $char = $text[$i]
        
        # Start of a new word
        if ($i -gt 0 -and (
                # Capital followed by lowercase (e.g., "Ops" in "CoreOps")
                ([char]::IsUpper($char) -and [char]::IsLower($text[$i + 1])) -or
                # Lowercase followed by capital (e.g., "System" in "OpsSystem")
                ([char]::IsLower($char) -and $i + 1 -lt $text.Length -and [char]::IsUpper($text[$i + 1])) -or
                # Number after letter or letter after number
                ([char]::IsLetter($char) -and $i + 1 -lt $text.Length -and [char]::IsNumber($text[$i + 1])) -or
                ([char]::IsNumber($char) -and $i + 1 -lt $text.Length -and [char]::IsLetter($text[$i + 1]))
            )) {
            if ($currentWord) {
                $words += $currentWord
                $currentWord = ""
            }
        }
        
        $currentWord += $char
    }
    
    if ($currentWord) {
        $words += $currentWord
    }
    
    return $words
}

function Convert-ToSolutionName($inputName) {
    # Remove any non-alphanumeric characters and split into words
    $words = $inputName -replace '[^a-zA-Z0-9]', ' ' -split '\s+' | Where-Object { $_ }
    
    # Handle each word
    $processedWords = foreach ($word in $words) {
        # Split words that might be combined (e.g., "CoreOps" -> "Core", "Ops")
        $subWords = Split-PascalCase($word)
        if ($subWords.Count -gt 0) {
            $subWords
        }
        else {
            $word
        }
    }
    
    # Convert each word to proper case
    $properWords = $processedWords | ForEach-Object {
        if ($_.Length -le 2) { 
            # Keep short words (like "UI", "OS") uppercase
            $_.ToUpper()
        }
        else {
            # Proper case for longer words
            $_.Substring(0, 1).ToUpper() + $_.Substring(1).ToLower()
        }
    }
    
    return ($properWords -join '')
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
}
else {
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
                }
                catch {
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
            }
            catch {
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
    }
    else {
        Write-Host "❌ No valid services selected or operation cancelled." -ForegroundColor Yellow
    }
}

# ===============================
# ✏️ Rename Solution
# ===============================
if (Ask-YesNo "Rename solution from '$solutionBaseName'?") {
    $inputName = Read-Host "Enter new solution name"
    $newName = Convert-ToSolutionName $inputName
    
    if ($newName -and $newName -ne $solutionBaseName) {
        Write-Host "🔄 Renaming solution '$solutionBaseName' to '$newName'..." -ForegroundColor Cyan

        # 1. Update file contents first
        Write-Host "🔍 Updating file contents..." -ForegroundColor Cyan
        $filesToUpdate = Get-ChildItem -Recurse -File -Include *.cs, *.csproj, *.json, *.sln, *.xml, *.md -ErrorAction SilentlyContinue
        foreach ($file in $filesToUpdate) {
            try {
                $content = Get-Content $file.FullName -Raw -ErrorAction Stop
                if ([string]::IsNullOrEmpty($content)) { continue }

                $updated = $content
                $updated = $updated -replace "\bProjects\.$([regex]::Escape($solutionBaseName))_", "Projects.${newName}_"
                $updated = $updated -replace "\b$([regex]::Escape($solutionBaseName))\.", "$newName."
                $updated = $updated -replace "$([regex]::Escape($solutionBaseName.ToLower()))-", "$($newName.ToLower())-"
                $updated = $updated -replace "\b$([regex]::Escape($solutionBaseName))\b", $newName

                if ($content -ne $updated) {
                    Set-Content $file.FullName $updated -ErrorAction Stop
                    Write-Host "✏️ Updated: $($file.Name)" -ForegroundColor Gray
                }
            }
            catch {
                Write-Host "⚠️ Failed to update $($file.Name): $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        # 2. Rename files and folders (deepest first)
        Write-Host "📁 Renaming files and folders..." -ForegroundColor Cyan
        $itemsToRename = Get-ChildItem -Recurse -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -like "*$solutionBaseName*" } |
        Sort-Object { $_.FullName.Length } -Descending
        
        foreach ($item in $itemsToRename) {
            try {
                $newItemName = $item.Name -replace [regex]::Escape($solutionBaseName), $newName
                if ($item.Name -ne $newItemName) {
                    $newPath = Join-Path $item.Directory.FullName $newItemName
                    if (-not (Test-Path $newPath)) {
                        Rename-Item $item.FullName -NewName $newItemName -Force -ErrorAction Stop
                        Write-Host "✅ Renamed: $($item.Name) → $newItemName" -ForegroundColor Gray
                    }
                }
            }
            catch {
                Write-Host "⚠️ Could not rename $($item.Name): $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        # 3. Update variables and final message
        $solutionBaseName = $newName
        $solutionFile = "$solutionBaseName.sln"
        $appHostFolder = "$solutionBaseName.AppHost"
        $appHostProject = "$appHostFolder/$solutionBaseName.AppHost.csproj"
        $programFile = "$appHostFolder/Program.cs"

        Write-Host "✅ Solution successfully renamed to '$newName'" -ForegroundColor Green
    }
    else {
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
}
else {
    Write-Host "❌ Build failed. Please check the output above." -ForegroundColor Red
}

Write-Host "`n🎉 Service management complete. All operations finished." -ForegroundColor Green

