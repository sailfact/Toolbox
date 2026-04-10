#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Interactively removes Windows user profiles one by one with confirmation prompts.

.DESCRIPTION
    Iterates through all user profiles on the system, skipping built-in accounts
    (Default, Public, Administrator, System). Prompts for confirmation before
    deleting each profile.

.NOTES
    Must be run as Administrator.
#>

$excludedNames = @('Default', 'Public', 'Administrator', 'systemprofile', 'LocalService', 'NetworkService')

# Get all profiles, filter out loaded and excluded ones
$profiles = Get-WmiObject -Class Win32_UserProfile | Where-Object {
    $name = Split-Path $_.LocalPath -Leaf
    -not $_.Special -and
    $name -notin $excludedNames
} | Sort-Object LocalPath

if ($profiles.Count -eq 0) {
    Write-Host "No eligible user profiles found." -ForegroundColor Yellow
    exit
}

Write-Host ""
Write-Host "Found $($profiles.Count) user profile(s):" -ForegroundColor Cyan
Write-Host ""

$deleted  = @()
$skipped  = @()
$failed   = @()

foreach ($profile in $profiles) {
    $name = Split-Path $profile.LocalPath -Leaf
    $path = $profile.LocalPath

    if ($profile.Loaded) {
        Write-Host "[ SKIP ] $name" -ForegroundColor DarkYellow
        Write-Host "         Path   : $path"
        Write-Host "         Reason : Profile is currently loaded (user logged in)" -ForegroundColor DarkYellow
        Write-Host ""
        $skipped += $name
        continue
    }

    Write-Host "Profile : $name" -ForegroundColor White
    Write-Host "Path    : $path"

    $response = Read-Host "Delete this profile? [y/N]"

    if ($response -match '^[Yy]$') {
        try {
            $profile.Delete()
            Write-Host "Deleted." -ForegroundColor Green
            $deleted += $name
        } catch {
            Write-Host "Failed to delete: $_" -ForegroundColor Red
            $failed += $name
        }
    } else {
        Write-Host "Skipped." -ForegroundColor DarkGray
        $skipped += $name
    }

    Write-Host ""
}

# Summary
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Cyan

if ($deleted.Count -gt 0) {
    Write-Host "Deleted  ($($deleted.Count)): $($deleted -join ', ')" -ForegroundColor Green
}
if ($skipped.Count -gt 0) {
    Write-Host "Skipped  ($($skipped.Count)): $($skipped -join ', ')" -ForegroundColor DarkGray
}
if ($failed.Count -gt 0) {
    Write-Host "Failed   ($($failed.Count)): $($failed -join ', ')" -ForegroundColor Red
}
