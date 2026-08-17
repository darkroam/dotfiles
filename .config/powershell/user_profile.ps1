# Shared PowerShell profile for Windows Terminal.
# It is loaded from $PROFILE.CurrentUserCurrentHost by install-profile.ps1.

# Keep console input/output predictable for UTF-8 text.
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

function Import-ProfileModule {
    param([Parameter(Mandatory)][string]$Name)

    if (Get-Module -ListAvailable -Name $Name) {
        Import-Module $Name -ErrorAction SilentlyContinue
    }
}

if (Get-Command starship -ErrorAction SilentlyContinue) {
    try {
        Invoke-Expression (& starship init powershell)
    } catch {
        Write-Verbose "Starship initialization failed: $($_.Exception.Message)"
    }
}

# Optional modules are loaded only when installed, so a partial setup keeps working.
Import-ProfileModule Terminal-Icons
Import-ProfileModule PSReadLine
Import-ProfileModule PSFzf
Import-ProfileModule z

# Aliases
Set-Alias -Name vim -Value nvim -Scope Global -Force
Set-Alias -Name ll -Value ls -Scope Global -Force
Set-Alias -Name g -Value git -Scope Global -Force
Set-Alias -Name grep -Value findstr -Scope Global -Force
Set-Alias -Name open -Value explorer.exe -Scope Global -Force

$tig = Join-Path $HOME 'scoop\apps\git\current\usr\bin\tig.exe'
if (Test-Path -LiteralPath $tig) {
    Set-Alias -Name tig -Value $tig -Scope Global -Force
}

$less = Join-Path $HOME 'scoop\apps\git\current\usr\bin\less.exe'
if (Test-Path -LiteralPath $less) {
    Set-Alias -Name less -Value $less -Scope Global -Force
}

# Detect the optional fzf integration before configuring PSReadLine.  This
# lets PSFzf own Tab completion when available, while keeping MenuComplete as
# the fallback for a partial installation.
$psFzfOptionCommand = Get-Command Set-PsFzfOption -ErrorAction SilentlyContinue
$fzfCommand = Get-Command fzf -ErrorAction SilentlyContinue
$psFzfReady = $null -ne $psFzfOptionCommand -and $null -ne $fzfCommand
$psFzfTabExpansionEnabled = $false

# PSReadLine
if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -BellStyle None
    # Older Windows PowerShell 5.1 builds may ship a PSReadLine without the
    # prediction option.  Keep the rest of the profile usable in that case.
    try {
        Set-PSReadLineOption -PredictionSource History
    } catch {
        Write-Verbose "PSReadLine history prediction is unavailable."
    }
    Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteChar
    if (-not $psFzfReady) {
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    }
}

# PSFzf needs both the PowerShell module and the fzf executable.
if ($psFzfReady) {
    # Keep these triggers aligned with fzf's Linux zsh bindings.
    $psFzfOptions = @{
        PSReadlineChordProvider       = 'Ctrl+t'
        PSReadlineChordReverseHistory = 'Ctrl+r'
        PSReadlineChordSetLocation    = 'Alt+c'
    }

    # Filter options so an older PSFzf release does not make the profile fail
    # when a newer switch is unavailable.
    foreach ($optionName in @($psFzfOptions.Keys)) {
        if (-not $psFzfOptionCommand.Parameters.ContainsKey($optionName)) {
            $psFzfOptions.Remove($optionName)
        }
    }
    if ($psFzfOptions.Count -gt 0) {
        try {
            Set-PsFzfOption @psFzfOptions
        } catch {
            Write-Verbose "PSFzf key binding setup failed: $($_.Exception.Message)"
        }
    }

    # Linux fzf completion uses ** + Tab.  Enable the PSFzf equivalent only
    # when this installed PSFzf version exposes it.
    if ($psFzfOptionCommand.Parameters.ContainsKey('TabExpansion')) {
        if ([string]::IsNullOrWhiteSpace($env:FZF_COMPLETION_TRIGGER)) {
            $env:FZF_COMPLETION_TRIGGER = '**'
        }
        try {
            Set-PsFzfOption -TabExpansion
            $psFzfTabExpansionEnabled = $true
        } catch {
            Write-Verbose "PSFzf Tab completion is unavailable."
        }
    }

    # Do not leave PSFzf's optional history-arguments chord (usually Alt+A)
    # behind when it is identifiable.  A user-defined Alt+A binding is left
    # untouched.
    $removeKeyHandler = Get-Command Remove-PSReadLineKeyHandler -ErrorAction SilentlyContinue
    $getKeyHandler = Get-Command Get-PSReadLineKeyHandler -ErrorAction SilentlyContinue
    if ($null -ne $removeKeyHandler -and $null -ne $getKeyHandler) {
        $altAHandler = Get-PSReadLineKeyHandler -Bound -ErrorAction SilentlyContinue |
            Where-Object {
                $handlerText = "$($_.Function) $($_.Description)"
                $_.Key -eq 'Alt+a' -and $handlerText -match '(?i)fzf.*history|history.*fzf'
            }
        if ($null -ne $altAHandler) {
            Remove-PSReadLineKeyHandler -Chord 'Alt+a'
        }
    }

}

if ($null -ne $fzfCommand) {
    # Preserve user supplied options and append only missing project defaults.
    # This is safe to run repeatedly when the profile is reloaded.
    $fzfDefaultOptions = @(
        @{ Text = '--height 90%'; Pattern = '(^|\s)--height(?:=|\s)' }
        @{ Text = '--layout=reverse'; Pattern = '(^|\s)--layout(?:=|\s)' }
        @{ Text = '--bind=alt-j:down'; Pattern = '(^|\s)--bind(?:=|\s)[^\s]*alt-j:down' }
        @{ Text = '--bind=alt-k:up'; Pattern = '(^|\s)--bind(?:=|\s)[^\s]*alt-k:up' }
        @{ Text = '--bind=alt-i:toggle+down'; Pattern = '(^|\s)--bind(?:=|\s)[^\s]*alt-i:toggle\+down' }
        @{ Text = '--border'; Pattern = '(^|\s)--border(?:=|\s|$)' }
    )
    $currentFzfOptions = [string]$env:FZF_DEFAULT_OPTS
    foreach ($defaultOption in $fzfDefaultOptions) {
        if ($currentFzfOptions -notmatch $defaultOption.Pattern) {
            if (-not [string]::IsNullOrWhiteSpace($currentFzfOptions)) {
                $currentFzfOptions += ' '
            }
            $currentFzfOptions += $defaultOption.Text
        }
    }
    $env:FZF_DEFAULT_OPTS = $currentFzfOptions
}

if ($psFzfReady -and -not $psFzfTabExpansionEnabled -and
    (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue)) {
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}

# Utilities
function whereis {
    param([Parameter(Mandatory, Position = 0)][string]$Command)

    Get-Command -Name $Command -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Path -ErrorAction SilentlyContinue
}

function lsc {
    param([int]$Columns = 5)

    Get-ChildItem | Format-Wide -Column $Columns -Property Name
}

function setproxy {
    $env:HTTP_PROXY = 'http://127.0.0.1:7890'
    $env:HTTPS_PROXY = 'http://127.0.0.1:7890'
}

function unsetproxy {
    Remove-Item Env:HTTP_PROXY, Env:HTTPS_PROXY -ErrorAction SilentlyContinue
}

Remove-Item Function:\Import-ProfileModule -ErrorAction SilentlyContinue
Remove-Variable utf8, tig, less, psFzfOptionCommand, fzfCommand,
    psFzfReady, psFzfTabExpansionEnabled, psFzfOptions, optionName,
    fzfDefaultOptions, currentFzfOptions, defaultOption,
    removeKeyHandler, getKeyHandler, altAHandler -ErrorAction SilentlyContinue
