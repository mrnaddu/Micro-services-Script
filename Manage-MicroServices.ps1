function To-PascalCase($text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }
    $parts = $text -split "[^a-zA-Z0-9]+" | Where-Object { $_ }
    if (-not $parts) { return "" }
    $transformed = $parts | ForEach-Object { 
        if ($_.Length -eq 0) { return "" }
        if ($_.Length -eq 1) { return $_.ToUpper() }
        return $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower()
    }
    return $transformed -join ""
}

# --- Dependency check ---
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Error: Git is not installed." -ForegroundColor Red
    exit 1
}
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host "Error: .NET SDK is not installed." -ForegroundColor Red
    exit 1
}

# --- Clone repo ---
$repoUrl = "https://github.com/mrnaddu/PlayTicket.git"
$cloneDir = "PlayTicket"
if (-not (Test-Path $cloneDir)) {
    Write-Host "Cloning repository..." -ForegroundColor Cyan
    git clone $repoUrl
} else {
    Write-Host "Repository already exists." -ForegroundColor Yellow
}
Set-Location $cloneDir

Write-Host "Welcome to the PlayTicket Service Manager" -ForegroundColor Cyan

# --- Initial solution setup ---
$solutionBaseName = "PlayTicket"
$solutionFile = "$solutionBaseName.sln"
$appHostFolder = "$solutionBaseName.AppHost"
$appHostProject = "$appHostFolder/$solutionBaseName.AppHost.csproj"
$programFile = "$appHostFolder/Program.cs"

# --- Ask how many services ---
$serviceCount = Read-Host "How many services would you like to create by cloning 'UserService' structure?"
while (-not ($serviceCount -as [int]) -or [int]$serviceCount -lt 1) {
    Write-Host "Error: Enter a number > 0" -ForegroundColor Red
    $serviceCount = Read-Host "How many services?"
}
$serviceCount = [int]$serviceCount

# --- Get service names ---
$defaultServices = "CashVoucher,Order,Profile"
$serviceInput = Read-Host "Enter $serviceCount service name(s) (comma-separated, e.g., $defaultServices)"
if ([string]::IsNullOrWhiteSpace($serviceInput)) {
    Write-Host "No input provided. Exiting." -ForegroundColor Red
    exit 1
}
$servicesRaw = $serviceInput -split "," | ForEach-Object { $_.Trim() }
$services = [string[]]($servicesRaw | ForEach-Object { To-PascalCase $_ })
$folders = [string[]]($servicesRaw | ForEach-Object { $_.Trim().ToLower() })

# --- Validate UserService template ---
$sourceFolder = "services/user"
if (-not (Test-Path $sourceFolder)) {
    Write-Host "Error: '$sourceFolder' does not exist." -ForegroundColor Red
    exit 1
}

# --- Clone and refactor services ---
foreach ($idx in 0..($services.Count-1)) {
    $servicePascal = $services[$idx]
    $targetFolder = "services/$($folders[$idx])"

    if (Test-Path $targetFolder) {
        Write-Host "Skipping existing folder $targetFolder" -ForegroundColor Yellow
        continue
    }

    Copy-Item $sourceFolder $targetFolder -Recurse -Force
    Write-Host "Copied template to $targetFolder" -ForegroundColor Green

    # Rename files/folders
    Get-ChildItem -Path $targetFolder -Recurse | Sort-Object -Descending -Property FullName | ForEach-Object {
        $oldName = $_.Name
        $newName = $oldName -replace "UserService", "$($servicePascal)Service" -replace "User", "$servicePascal"
        if ($oldName -ne $newName) {
            Rename-Item -Path $_.FullName -NewName $newName -Force
        }
    }

    # Replace namespace/refs inside files
    Get-ChildItem -Path $targetFolder -Recurse -File | ForEach-Object {
        (Get-Content $_.FullName -Raw) -replace "PlayTicket\.UserService", "$solutionBaseName.$($servicePascal)Service" `
            -replace "UserService", "$($servicePascal)Service" `
            -replace "\bUser\b", "$servicePascal" | Set-Content $_.FullName
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
        $serviceLower = $folders[$idx]
        $lineToAdd = "builder.AddProject<Projects.${solutionBaseName}_${servicePascal}Service_HttpApi_Host>(""$(($solutionBaseName).ToLower())-${serviceLower}service-httpapi-host"", launchProfileName: ""$solutionBaseName.${servicePascal}Service.Host"");"
        if (-not (Select-String -Path $programFile -Pattern $lineToAdd -SimpleMatch)) {
            (Get-Content $programFile) -replace "builder.Build\(\)\.Run\(\);", "$lineToAdd`r`n`$0" | Set-Content $programFile
        }
    }
}

# List all services
    Write-Host "`nAvailable services in the 'services' directory:" -ForegroundColor Cyan
    $allServiceFolders = Get-ChildItem -Path "services" -Directory | ForEach-Object { $_.Name }
    if ($allServiceFolders) {
        $allServiceFolders | ForEach-Object { Write-Host "- $_" -ForegroundColor Green }
    } else {
        Write-Host "No services found in the 'services' directory." -ForegroundColor Yellow
    }

    # Prompt for services to delete
    $deleteInput = Read-Host "`nEnter the name(s) of service(s) to delete (comma-separated, e.g., cashvoucher,order) or 'none' to skip"
    if ($deleteInput -ne 'none') {
        $servicesToDelete = $deleteInput -split "," | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }

        if (-not $servicesToDelete) {
            Write-Host "No valid service names provided. Skipping deletion." -ForegroundColor Yellow
        } else {
            Write-Host "`nAttempting to delete the following service(s):" -ForegroundColor Cyan
            $servicesToDelete | ForEach-Object { Write-Host "- $_" }

            foreach ($service in $servicesToDelete) {
                $serviceFolder = "services/$service"
                $servicePascal = To-PascalCase $service
                if (Test-Path $serviceFolder) {
                    # Remove csproj from solution and AppHost references
                    Get-ChildItem -Path $serviceFolder -Recurse -Include *.csproj | ForEach-Object {
                        $projPath = Resolve-Path $_.FullName
                        Write-Host "Removing project $projPath from solution..." -ForegroundColor Cyan
                        dotnet sln PlayTicket.sln remove $projPath

                        # Remove project reference from AppHost if exists
                        $appHostProject = "PlayTicket.AppHost/PlayTicket.AppHost.csproj"
                        if (Test-Path $appHostProject) {
                            Write-Host "Removing reference from AppHost to $projPath..." -ForegroundColor Cyan
                            dotnet remove $appHostProject reference $projPath
                        }
                    }

                    # Remove line from Program.cs
                    $programFile = "PlayTicket.AppHost/Program.cs"
                    if (Test-Path $programFile) {
                        $pattern = "builder.AddProject<Projects.PlayTicket_${servicePascal}Service_HttpApi_Host>"
                        $content = Get-Content $programFile
                        $newContent = $content | Where-Object { $_ -notmatch $pattern }
                        if ($content.Count -ne $newContent.Count) {
                            Write-Host "Removing Program.cs registration for $servicePascal..." -ForegroundColor Cyan
                            $newContent | Set-Content $programFile
                        }
                    }

                    # Finally delete the folder
                    Write-Host "Deleting service folder: $serviceFolder..." -ForegroundColor Yellow
                    Remove-Item -Path $serviceFolder -Recurse -Force
                    Write-Host "Deleted $service successfully." -ForegroundColor Green
                } else {
                    Write-Host "Error: Service folder '$serviceFolder' does not exist." -ForegroundColor Red
                }
            }
        }
    } else {
        Write-Host "Skipping deletion of services." -ForegroundColor Yellow 
    }

# --- Rename Solution at the END ---
$useCustomSolution = Read-Host "Do you want to change the solution name from '$solutionBaseName'? (y/n)"
if ($useCustomSolution -eq "y" -or $useCustomSolution -eq "Y") {
    $newNameRaw = Read-Host "Enter new solution name"
    $newName = To-PascalCase $newNameRaw

    if (-not [string]::IsNullOrWhiteSpace($newName) -and $newName -ne $solutionBaseName) {
        Write-Host "`nRenaming solution '$solutionBaseName' → '$newName' ..." -ForegroundColor Cyan

        # --- 1. Replace text across all file contents (code, project, config files) ---
        Write-Host "Replacing '$solutionBaseName' with '$newName' in file contents..." -ForegroundColor Cyan
        Get-ChildItem -Recurse -File -Include *.cs,*.csproj,*.json,*.sln,*.xml,*.md | ForEach-Object {
            $content = Get-Content $_.FullName -Raw
            $updatedContent = $content -replace "\b$solutionBaseName\b", $newName
            if ($content -ne $updatedContent) {
                Set-Content $_.FullName -Value $updatedContent
                Write-Host "Updated: $($_.FullName)" -ForegroundColor Gray
            }
        }

        # --- 2. Rename solution file ---
        if (Test-Path "$solutionBaseName.sln") {
            Rename-Item "$solutionBaseName.sln" "$newName.sln" -Force
            Write-Host "Renamed solution file to $newName.sln" -ForegroundColor Green
        }

        # --- 3. Rename AppHost folder and project ---
        if (Test-Path "$solutionBaseName.AppHost") {
            $newAppHostFolder = "$newName.AppHost"
            Rename-Item "$solutionBaseName.AppHost" $newAppHostFolder -Force

            $projFile = Get-ChildItem $newAppHostFolder -Filter "*.csproj" | Select-Object -First 1
            if ($projFile -and $projFile.Name -ne "$newName.AppHost.csproj") {
                Rename-Item $projFile.FullName "$newName.AppHost.csproj" -Force
                Write-Host "Renamed AppHost project file to $newName.AppHost.csproj" -ForegroundColor Green
            }
        }

        # --- 4. Rename folders and files in 'services/' ---
        Write-Host "Renaming all folders and files in 'services/' containing old solution name..." -ForegroundColor Cyan

        # Rename folders
        Get-ChildItem -Path "services" -Recurse -Directory | Sort-Object -Descending -Property FullName | Where-Object { $_.Name -match $solutionBaseName } | ForEach-Object {
            $newFolderName = $_.Name -replace [Regex]::Escape($solutionBaseName), $newName
            $newFolderPath = Join-Path -Path (Split-Path $_.FullName -Parent) -ChildPath $newFolderName
            if ($_.FullName -ne $newFolderPath) {
                Rename-Item $_.FullName -NewName $newFolderName -Force
                Write-Host "Renamed folder: $($_.Name) → $newFolderName" -ForegroundColor Green
            }
        }

        # Rename files
        Get-ChildItem -Path "services" -Recurse -File | Where-Object { $_.Name -match $solutionBaseName } | ForEach-Object {
            $newFileName = $_.Name -replace [Regex]::Escape($solutionBaseName), $newName
            $newFilePath = Join-Path -Path (Split-Path $_.FullName -Parent) -ChildPath $newFileName
            if ($_.FullName -ne $newFilePath) {
                Rename-Item $_.FullName -NewName $newFileName -Force
                Write-Host "Renamed file: $($_.Name) → $newFileName" -ForegroundColor Green
            }
        }

        # --- 5. Rename folders and projects outside services that match old solution name ---
        $allProjectDirs = Get-ChildItem -Recurse -Directory | Where-Object { $_.Name -like "$solutionBaseName.*" }
        foreach ($dir in $allProjectDirs) {
            $parent = Split-Path -Parent $dir.FullName
            $newDirName = $dir.Name -replace "^$solutionBaseName", $newName
            $newDirPath = Join-Path $parent $newDirName
            if ($dir.FullName -ne $newDirPath) {
                Rename-Item $dir.FullName $newDirPath -Force
                Write-Host "Renamed folder $($dir.Name) → $newDirName" -ForegroundColor Green
            }

            # Rename .csproj inside renamed folder
            $projFile = Get-ChildItem $newDirPath -Filter "*.csproj" | Select-Object -First 1
            if ($projFile -and $projFile.Name -like "$solutionBaseName*") {
                $newProjName = $projFile.Name -replace "^$solutionBaseName", $newName
                Rename-Item $projFile.FullName $newProjName -Force
                Write-Host "Renamed project file $($projFile.Name) → $newProjName" -ForegroundColor Green
            }
        }

        # --- 6. Rename root repo folder ---
        $parent = Split-Path -Parent (Get-Location)
        $currentFolder = Split-Path -Leaf (Get-Location)
        Set-Location $parent
        if ($currentFolder -ne $newName) {
            Rename-Item $currentFolder $newName -Force
            Write-Host "Renamed repo folder to $newName" -ForegroundColor Green
        }
        Set-Location $newName

        Write-Host "✅ Solution successfully renamed to '$newName' everywhere (sln, csproj, services, folders, repo)." -ForegroundColor Cyan
    }
}

Write-Host "`nService management complete. Ready!" -ForegroundColor Green
