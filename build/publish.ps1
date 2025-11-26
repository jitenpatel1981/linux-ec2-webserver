<#
  publish.ps1 (updated)
  - Finds the ASP.NET Core web project (Microsoft.NET.Sdk.Web) or first csproj
  - Publishes it into a staging folder
  - Prepares dist\app with published files + appspec.yml + scripts
  - Removes any .zip files in publish output to avoid nested zips
  - Creates artifact.zip at repo root (contains contents of dist: app/, appspec.yml, scripts/)
  - Safe / idempotent (removes old folders)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "---- publish.ps1 started ----"

# helper to find dotnet
$dotnetCandidates = @("C:\dotnet\dotnet.exe","dotnet")
$dotnet = $dotnetCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $dotnet) {
  Write-Host "WARNING: dotnet not found at C:\dotnet\dotnet.exe and not on PATH. Trying 'dotnet'..."
  $dotnet = "dotnet"
}

Write-Host "Using dotnet executable: $dotnet"

# determine publish configuration
if (-not $env:CONFIGURATION -or $env:CONFIGURATION -eq "") { $config = "Release" } else { $config = $env:CONFIGURATION }
Write-Host "Publish configuration: $config"

# find project: prefer Web SDK projects
Write-Host "Searching for web project (.csproj with Microsoft.NET.Sdk.Web)..."
$webProj = Get-ChildItem -Recurse -Filter *.csproj -ErrorAction SilentlyContinue |
           Where-Object {
             try {
               Select-String -Path $_.FullName -Pattern 'Microsoft\.NET\.Sdk\.Web' -Quiet -SimpleMatch
             } catch {
               $false
             }
           } |
           Select-Object -First 1

if ($webProj) {
  $projPath = $webProj.FullName
  Write-Host "Found web project: $projPath"
} else {
  Write-Host "No explicit web project found. Picking first .csproj in repo."
  $firstProj = Get-ChildItem -Recurse -Filter *.csproj -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $firstProj) {
    Write-Error "No .csproj files found in repository. Exiting."
    exit 1
  }
  $projPath = $firstProj.FullName
  Write-Host "Selected project: $projPath"
}

# pick publish root: prefer env:PUBLISH_DIR if provided (used in some buildspecs)
if ($env:PUBLISH_DIR -and $env:PUBLISH_DIR -ne "") {
  $pubRoot = Join-Path (Get-Location) $env:PUBLISH_DIR
  Write-Host "Using PUBLISH_DIR from environment: $env:PUBLISH_DIR -> $pubRoot"
} else {
  $pubRoot = Join-Path (Get-Location) "output"
  Write-Host "Using default publish root: $pubRoot"
}

# clean previous outputs
if (Test-Path $pubRoot) {
  Write-Host "Removing existing publish root: $pubRoot"
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $pubRoot
}
if (Test-Path "dist") {
  Write-Host "Removing existing dist folder"
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "dist"
}
if (Test-Path "artifact.zip") {
  Write-Host "Removing existing artifact.zip"
  Remove-Item -Force "artifact.zip" -ErrorAction SilentlyContinue
}

# publish to pubRoot\app
$outDir = Join-Path $pubRoot "app"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host "Running dotnet publish for project:"
Write-Host "  $projPath"
Write-Host "  output -> $outDir"
& $dotnet publish $projPath -c $config -o $outDir

Write-Host "dotnet publish completed. Published files count: " (Get-ChildItem -Recurse -Path $outDir | Measure-Object).Count

# remove any .zip files from publish output to avoid nested zips
Write-Host "Removing any .zip files from publish output (to avoid nested zips)..."
Get-ChildItem -Path $outDir -Filter *.zip -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
  Write-Host "  Removing zip: $($_.FullName)"
  Remove-Item -Force -Path $_.FullName -ErrorAction SilentlyContinue
}

# Prepare dist/app for artifact (CodeDeploy expects artifact root with appspec.yml & scripts)
$distRoot = Join-Path (Get-Location) "dist"
$distApp = Join-Path $distRoot "app"
New-Item -ItemType Directory -Force -Path $distApp | Out-Null

# copy published output into dist\app
Write-Host "Copying published output to $distApp"
Copy-Item -Path (Join-Path $outDir '*') -Destination $distApp -Recurse -Force

# Include appspec.yml (if present) into dist root (not dist\app)
if (Test-Path "appspec.yml") {
  Write-Host "Copying appspec.yml to dist"
  Copy-Item -Path "appspec.yml" -Destination $distRoot -Force
} else {
  Write-Host "No appspec.yml found in repo root. Make sure you have one for CodeDeploy."
}

# Include scripts folder under dist/scripts (if present)
# Use Copy-Item to copy the folder itself so dist\scripts\... will exist
if (Test-Path "scripts") {
  Write-Host "Copying entire 'scripts' folder to dist (preserve folder name)..."
  $destScripts = Join-Path $distRoot "scripts"
  # Remove if exists to ensure clean copy
  if (Test-Path $destScripts) { Remove-Item -Recurse -Force $destScripts -ErrorAction SilentlyContinue }
  Copy-Item -Path (Join-Path (Get-Location) "scripts") -Destination $distRoot -Recurse -Force
  Write-Host "Scripts copied to $destScripts"
} else {
  Write-Host "No scripts folder found in repo root. (That's OK if you don't use lifecycle scripts.)"
}

# sanity: list dist contents for debug
Write-Host "Dist tree (for debug):"
Get-ChildItem -Path $distRoot -Force | ForEach-Object { Write-Host " - $($_.Name) (Type: $($_.PSIsContainer))" }

# create artifact.zip containing contents of dist (not the dist folder itself)
Write-Host "Creating artifact.zip from contents of dist (root entries: app, appspec.yml, scripts if present)..."
Compress-Archive -Path (Join-Path $distRoot '*') -DestinationPath (Join-Path (Get-Location) "artifact.zip") -Force

# --- Convert Linux shell scripts to Unix (LF) line endings ---
$scriptDir = "dist/scripts"

if (Test-Path $scriptDir) {
    Write-Host "Converting .sh scripts to Unix (LF) line endings in $scriptDir"
    Get-ChildItem -Path $scriptDir -Filter *.sh | ForEach-Object {
        $path = $_.FullName
        Write-Host "  Converting $path"
        $content = Get-Content $path -Raw
        # Replace CRLF with LF
        $content = $content -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($path, $content)
    }
}
else {
    Write-Host "No dist/scripts directory found, skipping .sh conversion."
}


Write-Host "artifact.zip created: $(Get-Item artifact.zip).FullName"

Write-Host "---- publish.ps1 finished successfully ----"
exit 0
