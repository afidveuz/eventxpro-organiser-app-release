<#
.SYNOPSIS
    Automated Release Script for EventXPro Organiser App.
.DESCRIPTION
    1. Reads or bumps version in pubspec.yaml.
    2. Commits and pushes branch to GitHub.
    3. Creates and pushes a Git tag (e.g. v1.0.1).
    4. Builds the release APK (`flutter build apk --release`).
    5. Opens the release folder and GitHub Releases web page for instant drag & drop upload.
    6. If GitHub CLI (`gh`) is available, it can automatically upload the APK directly.
.EXAMPLE
    .\scripts\release.ps1
    .\scripts\release.ps1 -Version "1.0.2+3"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [string]$Tag,

    [Parameter(Mandatory = $false)]
    [string]$Branch,

    [Parameter(Mandatory = $false)]
    [switch]$SkipBuild,

    [Parameter(Mandatory = $false)]
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"

# Ensure script is executed in the Flutter project directory
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path "$projectRoot\pubspec.yaml")) {
    $projectRoot = Get-Location
}
Set-Location $projectRoot

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  EventXPro Flutter App Release Script    " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Project directory: $projectRoot" -ForegroundColor Gray

# 1. Detect current branch
if (-not $Branch) {
    $currentBranch = (git branch --show-current).Trim()
    if (-not $currentBranch) {
        $currentBranch = "test"
    }
    $Branch = $currentBranch
}
Write-Host "Active Git Branch: $Branch" -ForegroundColor Yellow

# 2. Get / Update Version in pubspec.yaml
$pubspecPath = Join-Path $projectRoot "pubspec.yaml"
$pubspecContent = Get-Content $pubspecPath -Raw

if ($pubspecContent -match "version:\s*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)") {
    $currentVersion = $matches[1]
} else {
    Write-Error "Could not parse current version from pubspec.yaml."
    exit 1
}

Write-Host "Current pubspec.yaml version: $currentVersion" -ForegroundColor Gray

if ($Version) {
    Write-Host "Updating version to: $Version" -ForegroundColor Green
    $pubspecContent = $pubspecContent -replace "version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+", "version: $Version"
    Set-Content -Path $pubspecPath -Value $pubspecContent -NoNewline
    $appVersion = $Version
} else {
    $appVersion = $currentVersion
}

# 3. Determine Tag (e.g., v1.0.1 from 1.0.1+2)
if (-not $Tag) {
    $versionNameOnly = ($appVersion -split "\+")[0]
    $Tag = "v$versionNameOnly"
}
Write-Host "Release Tag: $Tag" -ForegroundColor Magenta

# 4. Check for unstaged changes in pubspec or repo
$status = (git status --porcelain).Trim()
if ($status) {
    Write-Host "Staging and committing changes..." -ForegroundColor Yellow
    git add pubspec.yaml
    git commit -m "chore: release $Tag (version $appVersion)"
}

# 5. Push branch
Write-Host "Pushing branch '$Branch' to origin..." -ForegroundColor Yellow
git push origin $Branch

# 6. Create & Push Git Tag
Write-Host "Checking if tag '$Tag' exists locally..." -ForegroundColor Gray
$tagExistsLocally = git tag -l $Tag
if ($tagExistsLocally) {
    Write-Host "Tag '$Tag' already exists locally." -ForegroundColor Yellow
} else {
    Write-Host "Creating tag '$Tag'..." -ForegroundColor Green
    git tag -a $Tag -m "Release $Tag"
}

Write-Host "Pushing tag '$Tag' to GitHub..." -ForegroundColor Yellow
try {
    git push origin $Tag
    Write-Host "Tag '$Tag' pushed successfully." -ForegroundColor Green
} catch {
    Write-Host "Tag push note: $($_.Exception.Message)" -ForegroundColor Gray
}

# 7. Build Release APK
$apkPath = Join-Path $projectRoot "build\app\outputs\flutter-apk\app-release.apk"

if (-not $SkipBuild) {
    Write-Host "`nBuilding release APK (flutter build apk --release)..." -ForegroundColor Cyan
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter build failed with exit code $LASTEXITCODE."
        exit $LASTEXITCODE
    }
}

if (-not (Test-Path $apkPath)) {
    Write-Error "Release APK not found at: $apkPath"
    exit 1
}

$apkItem = Get-Item $apkPath
$apkSizeMB = [math]::Round($apkItem.Length / 1MB, 2)
Write-Host "`n==========================================" -ForegroundColor Green
Write-Host "  Build Succeeded!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host "APK Location : $($apkItem.FullName)" -ForegroundColor White
Write-Host "APK Size     : $apkSizeMB MB" -ForegroundColor White
Write-Host "Last Modified: $($apkItem.LastWriteTime)" -ForegroundColor White

# 8. GitHub Remote Repo Information
$remoteUrl = (git config --get remote.origin.url)
# Clean git@github.com:User/Repo.git or https://github.com/User/Repo.git
$repoWebUrl = $remoteUrl -replace "\.git$", "" -replace "^git@github\.com:", "https://github.com/"

$githubReleaseUrl = "$repoWebUrl/releases/new?tag=$Tag"
$directDownloadUrl = "$repoWebUrl/releases/download/$Tag/app-release.apk"

Write-Host "`n------------------------------------------" -ForegroundColor Cyan
Write-Host "  Next Steps for GitHub Release" -ForegroundColor Cyan
Write-Host "------------------------------------------" -ForegroundColor Cyan
Write-Host "1. Create Release on GitHub:" -ForegroundColor Yellow
Write-Host "   $githubReleaseUrl" -ForegroundColor White
Write-Host "2. Direct APK Download URL (for Firebase Remote Config):" -ForegroundColor Yellow
Write-Host "   $directDownloadUrl" -ForegroundColor White

# 9. Automatic GitHub CLI Upload if installed
$ghInstalled = Get-Command gh -ErrorAction SilentlyContinue
if ($ghInstalled) {
    Write-Host "`nGitHub CLI (gh) detected. Attempting automatic release creation..." -ForegroundColor Green
    try {
        gh release create $Tag $apkPath --title "$Tag" --notes "Release $Tag - EventXPro App"
        Write-Host "Release created and APK uploaded automatically!" -ForegroundColor Green
        return
    } catch {
        Write-Host "Could not auto-upload via gh CLI. Opening browser instead..." -ForegroundColor Yellow
    }
}

# 10. Open folder and browser for easy drag & drop
Write-Host "`nOpening APK folder in Explorer..." -ForegroundColor Gray
Start-Process explorer.exe -ArgumentList "/select,`"$apkPath`""

if (-not $NoBrowser) {
    Write-Host "Opening GitHub Release page in browser..." -ForegroundColor Gray
    Start-Process $githubReleaseUrl
}

Write-Host "`nDone! Just drag 'app-release.apk' into the GitHub release page and click 'Publish release'." -ForegroundColor Green
