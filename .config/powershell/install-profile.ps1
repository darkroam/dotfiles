# From a PowerShell prompt:
# Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
# & "$env:USERPROFILE\.config\powershell\install-modules.ps1" -InstallFzf
# & "$env:USERPROFILE\.config\powershell\install-profile.ps1" -Backup
# . $PROFILE

[CmdletBinding()]
param(
    [switch]$Backup
)

$ErrorActionPreference = 'Stop'
$profilePath = $PROFILE.CurrentUserCurrentHost
$profileDirectory = Split-Path -Parent $profilePath
$profileLine = '. $env:USERPROFILE\.config\powershell\user_profile.ps1'

New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null

if (Test-Path -LiteralPath $profilePath) {
    if ($Backup) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item -LiteralPath $profilePath -Destination "$profilePath.bak-$stamp"
    }
    $profileText = Get-Content -LiteralPath $profilePath -Raw
} else {
    $profileText = ''
}

# The exact-line check below makes normal reruns idempotent.  -Backup is an
# explicit opt-in and intentionally creates a fresh snapshot on each run.
if ($profileText -notmatch '(?m)^\s*\.\s+\$env:USERPROFILE\\\.config\\powershell\\user_profile\.ps1\s*$') {
    if ($profileText.Length -gt 0 -and $profileText -notmatch "(\r?\n)\z") {
        Add-Content -LiteralPath $profilePath -Value ''
    }
    Add-Content -LiteralPath $profilePath -Value $profileLine
    Write-Host "Added dot-source entry to $profilePath"
} else {
    Write-Host "Dot-source entry already exists in $profilePath"
}

Write-Host 'Restart PowerShell or run `. $PROFILE` to load the profile.'
