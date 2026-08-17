[CmdletBinding()]
param(
    [switch]$InstallFzf,
    [switch]$SkipPublisherCheck
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw 'PowerShell 5.1 or PowerShell 7 is required.'
}

# Windows PowerShell 5.1 otherwise commonly negotiates an obsolete TLS version.
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
    throw 'Install-Module is unavailable. Install PowerShellGet first.'
}

# PowerShell 5.1 may need NuGet before it can reach PSGallery.
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force
}

$modules = @('Terminal-Icons', 'z', 'PSReadLine', 'PSFzf')
$installParameters = @{
    Repository = 'PSGallery'
    Scope      = 'CurrentUser'
    Force      = $true
    AllowClobber = $true
}
if ($SkipPublisherCheck) {
    $installParameters.SkipPublisherCheck = $true
}

foreach ($module in $modules) {
    # -Force converges an existing installation to the current PSGallery
    # version, so rerunning this script is safe and does not duplicate modules.
    Write-Host "Installing or updating $module..."
    Install-Module -Name $module @installParameters
}

if (Get-Command fzf -ErrorAction SilentlyContinue) {
    Write-Host 'fzf executable: found'
} elseif ($InstallFzf) {
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        & scoop install fzf
        if ($LASTEXITCODE -ne 0) {
            throw "Scoop failed to install fzf (exit code $LASTEXITCODE)."
        }
    } elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        & winget install --id junegunn.fzf --exact --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet failed to install fzf (exit code $LASTEXITCODE)."
        }
    } else {
        Write-Warning 'Neither scoop nor winget is available; install fzf.exe manually.'
    }
} else {
    Write-Warning 'PSFzf is installed, but fzf.exe is missing. Re-run with -InstallFzf or install it manually.'
}

Write-Host 'PowerShell modules are ready. Run install-profile.ps1, then restart PowerShell.'
