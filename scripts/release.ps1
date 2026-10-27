<#
.SYNOPSIS
    Automated Interactive Release Script for EventXPro Organiser App.
.DESCRIPTION
    1. Prompts for version update (Patch / Bug Fix, Minor / Feature, Major, Custom, or Keep).
    2. Updates pubspec.yaml with the new version and build number.
    3. Prompts for optional release notes / description.
    4. Commits and pushes branch to GitHub.
    5. Creates and pushes a Git tag (e.g. v1.0.2).
    6. Builds the release APK (`flutter build apk --release`).
    7. Opens the APK folder and GitHub Releases web page for instant drag & drop upload.
.EXAMPLE
    .\release.ps1
    .\release.ps1 -Type patch
    .\release.ps1 -Version "1.0.2+3"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [ValidateSet("patch", "minor", "major", "build", "keep", "custom")]
    [string]$Type,

    [Parameter(Mandatory = $false)]
    [string]$Tag,

    [Parameter(Mandatory = $false)]
    [string]$Branch,

    [Parameter(Mandatory = $false)]
    [string]$Notes,

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

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "   EventXPro Release & Build Assistant    " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Project directory: $projectRoot" -ForegroundColor Gray

# 1. Read Current Version from pubspec.yaml
$pubspecPath = Join-Path $projectRoot "pubspec.yaml"
$pubspecContent = Get-Content $pubspecPath -Raw

if ($pubspecContent -match "version:\s*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)") {
    $currentVersion = $matches[1]
} else {
    Write-Error "Could not parse current version from pubspec.yaml."
    exit 1
}

Write-Host "Current App Version: " -NoNewline -ForegroundColor White
Write-Host $currentVersion -ForegroundColor Green

# Parse components
if ($currentVersion -match "^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)\+(?<build>\d+)$") {
    $major = [int]$matches['major']
    $minor = [int]$matches['minor']
    $patch = [int]$matches['patch']
    $build = [int]$matches['build']

    $nextPatch = "$major.$minor.$($patch + 1)+$($build + 1)"
    $nextMinor = "$major.$($minor + 1).0+$($build + 1)"
    $nextMajor = "$($major + 1).0.0+$($build + 1)"
    $nextBuild = "$major.$minor.$patch+$($build + 1)"
} else {
    $nextPatch = "$currentVersion"
    $nextMinor = "$currentVersion"
    $nextMajor = "$currentVersion"
    $nextBuild = "$currentVersion"
}

# 2. Determine New Version (Interactive or Parameter)
$selectedVersion = ""

if ($Version) {
    $selectedVersion = $Version
} elseif ($Type) {
    switch ($Type.ToLower()) {
        "patch"  { $selectedVersion = $nextPatch }
        "minor"  { $selectedVersion = $nextMinor }
        "major"  { $selectedVersion = $nextMajor }
        "build"  { $selectedVersion = $nextBuild }
        "keep"   { $selectedVersion = $currentVersion }
        "custom" {
            $selectedVersion = Read-Host "Enter custom version (e.g. 1.0.2+3)"
        }
    }
} else {
    # Interactive Menu
    Write-Host "`nSelect version update type:" -ForegroundColor Yellow
    Write-Host "  [1] Patch / Bug Fix      -> $nextPatch (Default)" -ForegroundColor White
    Write-Host "  [2] Minor / New Feature  -> $nextMinor" -ForegroundColor White
    Write-Host "  [3] Major / Breaking     -> $nextMajor" -ForegroundColor White
    Write-Host "  [4] Build Bump Only      -> $nextBuild" -ForegroundColor White
    Write-Host "  [5] Keep Current Version -> $currentVersion" -ForegroundColor White
    Write-Host "  [6] Custom Version       -> (Enter manually)" -ForegroundColor White

    $choice = Read-Host "`nEnter option [1-6] (Press Enter for [1] Patch)"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        $choice = "1"
    }

    switch ($choice.Trim()) {
        "1" { $selectedVersion = $nextPatch }
        "2" { $selectedVersion = $nextMinor }
        "3" { $selectedVersion = $nextMajor }
        "4" { $selectedVersion = $nextBuild }
        "5" { $selectedVersion = $currentVersion }
        "6" {
            $inputVer = Read-Host "Enter custom version (e.g. 1.0.2+3)"
            while (-not ($inputVer -match "^\d+\.\d+\.\d+\+\d+$")) {
                Write-Host "Invalid format. Must be format X.Y.Z+B (e.g. 1.0.2+3)." -ForegroundColor Red
                $inputVer = Read-Host "Enter custom version"
            }
            $selectedVersion = $inputVer
        }
        default {
            Write-Host "Defaulting to Patch ($nextPatch)..." -ForegroundColor Gray
            $selectedVersion = $nextPatch
        }
    }
}

Write-Host "`nSelected Target Version: " -NoNewline -ForegroundColor White
Write-Host $selectedVersion -ForegroundColor Green

# 3. Update pubspec.yaml if version changed
if ($selectedVersion -ne $currentVersion) {
    Write-Host "Updating pubspec.yaml..." -ForegroundColor Cyan
    $pubspecContent = $pubspecContent -replace "version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+", "version: $selectedVersion"
    Set-Content -Path $pubspecPath -Value $pubspecContent -NoNewline
    Write-Host "pubspec.yaml updated to $selectedVersion." -ForegroundColor Green
} else {
    Write-Host "Keeping version $currentVersion unchanged in pubspec.yaml." -ForegroundColor Gray
}

# 4. Optional Release Notes
if (-not $PSBoundParameters.ContainsKey('Notes') -or [string]::IsNullOrWhiteSpace($Notes)) {
    $enteredNotes = Read-Host "`nEnter release notes or summary (Optional - press Enter to skip)"
    if (-not [string]::IsNullOrWhiteSpace($enteredNotes)) {
        $Notes = $enteredNotes.Trim()
    }
}

# 5. Detect Branch & Tag
if (-not $Branch) {
    $currentBranch = (git branch --show-current).Trim()
    if (-not $currentBranch) {
        $currentBranch = "test"
    }
    $Branch = $currentBranch
}

if (-not $Tag) {
    $versionNameOnly = ($selectedVersion -split "\+")[0]
    $Tag = "v$versionNameOnly"
}

Write-Host "`nBranch  : " -NoNewline -ForegroundColor White
Write-Host $Branch -ForegroundColor Yellow
Write-Host "Git Tag : " -NoNewline -ForegroundColor White
Write-Host $Tag -ForegroundColor Magenta
if ($Notes) {
    Write-Host "Notes   : $Notes" -ForegroundColor Gray
}

# 6. Commit any changes
$status = (git status --porcelain).Trim()
if ($status) {
    Write-Host "`nStaging and committing changes..." -ForegroundColor Yellow
    git add pubspec.yaml
    $commitMsg = if ($Notes) { "chore: release $Tag - $Notes" } else { "chore: release $Tag (version $selectedVersion)" }
    git commit -m $commitMsg
}

# 7. Push Branch to Origin
Write-Host "`nPushing branch '$Branch' to origin..." -ForegroundColor Yellow
git push origin $Branch

# 8. Create and Push Git Tag
$tagExistsLocally = git tag -l $Tag
if ($tagExistsLocally) {
    Write-Host "Tag '$Tag' already exists locally." -ForegroundColor Yellow
} else {
    $tagMsg = if ($Notes) { "Release $Tag: $Notes" } else { "Release $Tag" }
    Write-Host "Creating git tag '$Tag'..." -ForegroundColor Green
    git tag -a $Tag -m $tagMsg
}

Write-Host "Pushing tag '$Tag' to GitHub..." -ForegroundColor Yellow
try {
    git push origin $Tag
    Write-Host "Tag '$Tag' pushed successfully." -ForegroundColor Green
} catch {
    Write-Host "Tag push note: $($_.Exception.Message)" -ForegroundColor Gray
}

# 9. Build Release APK
$apkPath = Join-Path $projectRoot "build\app\outputs\flutter-apk\app-release.apk"

if (-not $SkipBuild) {
    Write-Host "`n------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Building Release APK (flutter build apk --release)" -ForegroundColor Cyan
    Write-Host "------------------------------------------" -ForegroundColor Cyan
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

# 10. URLs for GitHub Release & Firebase Remote Config
$remoteUrl = (git config --get remote.origin.url)
$repoWebUrl = $remoteUrl -replace "\.git$", "" -replace "^git@github\.com:", "https://github.com/"

$githubReleaseUrl = "$repoWebUrl/releases/new?tag=$Tag"
$directDownloadUrl = "$repoWebUrl/releases/download/$Tag/app-release.apk"

Write-Host "`n------------------------------------------" -ForegroundColor Cyan
Write-Host "  Next Steps for GitHub Release" -ForegroundColor Cyan
Write-Host "------------------------------------------" -ForegroundColor Cyan
Write-Host "1. Create / View Release on GitHub:" -ForegroundColor Yellow
Write-Host "   $githubReleaseUrl" -ForegroundColor White
Write-Host "2. Direct APK Download URL (for Firebase Remote Config):" -ForegroundColor Yellow
Write-Host "   $directDownloadUrl" -ForegroundColor White

# 11. GitHub CLI Auto-Upload if available
$ghInstalled = Get-Command gh -ErrorAction SilentlyContinue
if ($ghInstalled) {
    Write-Host "`nGitHub CLI detected. Attempting direct upload..." -ForegroundColor Green
    try {
        $ghNotes = if ($Notes) { $Notes } else { "Release $Tag - EventXPro App" }
        gh release create $Tag $apkPath --title "$Tag" --notes $ghNotes
        Write-Host "Release created and APK uploaded automatically via GitHub CLI!" -ForegroundColor Green
        return
    } catch {
        Write-Host "Could not auto-upload via gh CLI ($($_.Exception.Message)). Opening browser..." -ForegroundColor Yellow
    }
}

# 12. Open Explorer & Browser
Write-Host "`nOpening APK folder in Windows Explorer..." -ForegroundColor Gray
Start-Process explorer.exe -ArgumentList "/select,`"$apkPath`""

if (-not $NoBrowser) {
    Write-Host "Opening GitHub Release page in browser..." -ForegroundColor Gray
    Start-Process $githubReleaseUrl
}

Write-Host "`nDone! Drag 'app-release.apk' into the GitHub release page and click 'Publish release'." -ForegroundColor Green
