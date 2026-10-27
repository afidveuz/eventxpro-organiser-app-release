<#
.SYNOPSIS
    Uploads an APK to a GitHub Release in the public release repository.
.DESCRIPTION
    Uses GitHub REST API and a Personal Access Token to create a release (if not existing)
    and upload the APK file automatically.
.EXAMPLE
    .\scripts\upload_release.ps1
    .\scripts\upload_release.ps1 -Token "ghp_..." -Tag "v1.0.1"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Token,

    [Parameter(Mandatory = $false)]
    [string]$Tag,

    [Parameter(Mandatory = $false)]
    [string]$ApkPath,

    [Parameter(Mandatory = $false)]
    [string]$Repo = "afidveuz/eventxpro-organiser-app-release",

    [Parameter(Mandatory = $false)]
    [string]$Notes
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path "$projectRoot\pubspec.yaml")) {
    $projectRoot = Get-Location
}

# 1. Resolve GitHub Token
$githubToken = $Token
if (-not $githubToken) {
    if ($env:GITHUB_TOKEN) {
        $githubToken = $env:GITHUB_TOKEN
    } elseif ($env:GH_TOKEN) {
        $githubToken = $env:GH_TOKEN
    } else {
        $tokenFilePath = Join-Path $projectRoot ".github_token"
        if (Test-Path $tokenFilePath) {
            $githubToken = (Get-Content $tokenFilePath -Raw).Trim()
        }
    }
}

if (-not $githubToken) {
    Write-Host "`nGitHub Token not found." -ForegroundColor Yellow
    Write-Host "Please enter your GitHub Personal Access Token (classic with 'repo' scope, or fine-grained with 'Contents: Read & Write')." -ForegroundColor Gray
    $inputToken = Read-Host "GitHub Token"
    if ([string]::IsNullOrWhiteSpace($inputToken)) {
        Write-Error "A GitHub Token is required to upload builds automatically."
        exit 1
    }
    $githubToken = $inputToken.Trim()

    $saveAns = Read-Host "Save token in .github_token for future automatic uploads? (Y/n)"
    if ($saveAns.Trim().ToLower() -ne "n") {
        Set-Content -Path (Join-Path $projectRoot ".github_token") -Value $githubToken -NoNewline
        Write-Host "Token saved to .github_token (file is protected and git-ignored)." -ForegroundColor Green
    }
}

# 2. Determine Tag and APK path if not specified
if (-not $Tag) {
    $pubspecPath = Join-Path $projectRoot "pubspec.yaml"
    if (Test-Path $pubspecPath) {
        $content = Get-Content $pubspecPath -Raw
        if ($content -match "version:\s*([0-9]+\.[0-9]+\.[0-9]+)") {
            $Tag = "v$($matches[1])"
        }
    }
    if (-not $Tag) {
        $Tag = Read-Host "Enter release tag (e.g. v1.0.1)"
    }
}

if (-not $ApkPath) {
    $cleanVersion = $Tag.TrimStart("v")
    $candidates = @(
        (Join-Path $projectRoot "build\app\outputs\flutter-apk\eventxpro-scanner-$Tag.apk"),
        (Join-Path $projectRoot "build\app\outputs\flutter-apk\eventxpro-scanner-v$cleanVersion.apk"),
        (Join-Path $projectRoot "build\app\outputs\flutter-apk\app-release.apk")
    )
    foreach ($cand in $candidates) {
        if (Test-Path $cand) {
            $ApkPath = $cand
            break
        }
    }
}

if (-not $ApkPath -or -not (Test-Path $ApkPath)) {
    Write-Error "Could not find release APK to upload. Checked candidates: $($candidates -join ', ')"
    exit 1
}

$apkItem = Get-Item $ApkPath
$apkFileName = $apkItem.Name
$apkSizeMB = [math]::Round($apkItem.Length / 1MB, 2)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "    GitHub Release Automatic Uploader     " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Repository : $Repo" -ForegroundColor White
Write-Host "Tag        : $Tag" -ForegroundColor Magenta
Write-Host "File       : $apkFileName ($apkSizeMB MB)" -ForegroundColor Yellow
Write-Host "File Path  : $($apkItem.FullName)" -ForegroundColor Gray

# Common headers
$headers = @{
    "Authorization"        = "Bearer $githubToken"
    "Accept"               = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent"           = "EventXPro-ReleaseScript"
}

# 3. Get or Create Release on GitHub
$apiBase = "https://api.github.com/repos/$Repo"
$release = $null

Write-Host "`nChecking release for tag '$Tag' on GitHub..." -ForegroundColor Cyan
try {
    $release = Invoke-RestMethod -Uri "$apiBase/releases/tags/$Tag" -Method Get -Headers $headers
    Write-Host "Found existing release (ID: $($release.id))." -ForegroundColor Green
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 404 -or $_.Exception.Message -match "404") {
        Write-Host "Release for tag '$Tag' does not exist yet. Creating release..." -ForegroundColor Yellow
        $bodyNotes = if ($Notes) { $Notes } else { "Official release of EventXPro Organiser ($Tag)" }
        $releaseBody = @{
            tag_name         = $Tag
            name             = "Release $Tag"
            body             = $bodyNotes
            draft            = $false
            prerelease       = $false
            generate_release_notes = $true
        } | ConvertTo-Json

        $release = Invoke-RestMethod -Uri "$apiBase/releases" -Method Post -Headers $headers -Body $releaseBody -ContentType "application/json"
        Write-Host "Release created successfully (ID: $($release.id))!" -ForegroundColor Green
    } else {
        Write-Error "Failed to fetch or create release: $($_.Exception.Message)"
        exit 1
    }
}

# 4. Check if an asset with the same name already exists and delete it
Write-Host "`nChecking existing assets for '$apkFileName'..." -ForegroundColor Cyan
try {
    $existingAssets = Invoke-RestMethod -Uri "$apiBase/releases/$($release.id)/assets" -Method Get -Headers $headers
    foreach ($asset in $existingAssets) {
        if ($asset.name -eq $apkFileName) {
            Write-Host "Deleting previous asset '$apkFileName' (ID: $($asset.id))..." -ForegroundColor Yellow
            Invoke-RestMethod -Uri "$apiBase/releases/assets/$($asset.id)" -Method Delete -Headers $headers
            Write-Host "Previous asset removed." -ForegroundColor Green
            break
        }
    }
} catch {
    Write-Host "Note checking existing assets: $($_.Exception.Message)" -ForegroundColor Gray
}

# 5. Upload Asset using System.Net.Http.HttpClient (Streaming upload for large binaries)
Add-Type -AssemblyName System.Net.Http

$rawUploadUrl = $release.upload_url
$uploadUrl = $rawUploadUrl -replace '\{\?name,label\}', "?name=$apkFileName"

Write-Host "`nUploading '$apkFileName' ($apkSizeMB MB) to GitHub..." -ForegroundColor Cyan
Write-Host "Please wait while the binary uploads..." -ForegroundColor Gray

$httpClient = [System.Net.Http.HttpClient]::new()
$httpClient.Timeout = [System.TimeSpan]::FromMinutes(15)
$httpClient.DefaultRequestHeaders.Add("User-Agent", "EventXPro-ReleaseScript")
$httpClient.DefaultRequestHeaders.Add("Authorization", "Bearer $githubToken")
$httpClient.DefaultRequestHeaders.Add("Accept", "application/vnd.github+json")
$httpClient.DefaultRequestHeaders.Add("X-GitHub-Api-Version", "2022-11-28")

$fileStream = [System.IO.File]::OpenRead($apkItem.FullName)
$content = [System.Net.Http.StreamContent]::new($fileStream)
$content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/vnd.android.package-archive")
$content.Headers.ContentLength = $apkItem.Length

$uploadSuccess = $false
try {
    $response = $httpClient.PostAsync($uploadUrl, $content).GetAwaiter().GetResult()
    if ($response.IsSuccessStatusCode) {
        $uploadSuccess = $true
    } else {
        $errBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        Write-Error "Upload failed with HTTP $($response.StatusCode): $errBody"
    }
} finally {
    $fileStream.Close()
    $fileStream.Dispose()
    $httpClient.Dispose()
}

if ($uploadSuccess) {
    $downloadUrl = "https://github.com/$Repo/releases/download/$Tag/$apkFileName"
    Write-Host "`n==========================================" -ForegroundColor Green
    Write-Host "    UPLOAD COMPLETED SUCCESSFULLY!        " -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Release Page : $($release.html_url)" -ForegroundColor White
    Write-Host "`nPublic Direct Download Link (for Firebase Remote Config):" -ForegroundColor Yellow
    Write-Host "$downloadUrl" -ForegroundColor Green
    Write-Host "`nThis link is ready to use immediately without login!" -ForegroundColor White
}
