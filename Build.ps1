<#
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Stages,

    [Parameter(Mandatory=$false)]
    [switch]$UseLocalBuild = $false
)

########
# Global settings
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

########
# Modules
Remove-Module Noveris.Build -EA SilentlyContinue
if ($UseLocalBuild)
{
    Import-Module ./source/Noveris.Build
} else {
    $module = Find-Module Noveris.Build -MaximumVersion 0.4.9999
    Install-Module -Scope CurrentUser -Name $module.Name -RequiredVersion $module.Version -Confirm:$false -SkipPublisherCheck
    Import-Module -Name $module.Name -RequiredVersion $module.Version
}

########
# Capture version information
$version = Get-BuildVersionInfo -Sources @(
    $Env:GITHUB_REF,
    $Env:BUILD_SOURCEBRANCH,
    $Env:CI_COMMIT_TAG,
    $Env:BUILD_VERSION,
    "v0.1.0"
)

########
# Build stage
Invoke-BuildStage -Name "Build" -Filters $Stages -Script {
    # Template PowerShell module definition
    Write-Information "Templating Noveris.Build.psd1"
    Format-TemplateFile -Template source/Noveris.Build.psd1.tpl -Target source/Noveris.Build/Noveris.Build.psd1 -Content @{
        __FULLVERSION__ = $version.Full
    }
}

Invoke-BuildStage -Name "Publish" -Filters $Stages -Script {
    # Publish module
    Publish-Module -Path ./source/Noveris.Build -NuGetApiKey $Env:NUGET_API_KEY
}
