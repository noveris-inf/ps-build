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
Remove-Module Noveris.ModuleMgmt -EA SilentlyContinue
Import-Module ./Noveris.ModuleMgmt/source/Noveris.ModuleMgmt/Noveris.ModuleMgmt.psm1

Remove-Module noveris.build -EA SilentlyContinue
if ($UseLocalBuild)
{
    Import-Module ./source/noveris.build/noveris.build.psm1
} else {
    Import-Module -Name noveris.build -RequiredVersion (Install-PSModuleWithSpec -Name noveris.build -Major 0 -Minor 5)
}

########
# Capture version information
$version = @(
    $Env:GITHUB_REF,
    $Env:BUILD_SOURCEBRANCH,
    $Env:CI_COMMIT_TAG,
    $Env:BUILD_VERSION,
    "v0.1.0"
) | Select-ValidVersions -First -Required

########
# Build stage
Invoke-BuildStage -Name "Build" -Filters $Stages -Script {
    # Template PowerShell module definition
    Write-Information "Templating noveris.build.psd1"
    Format-TemplateFile -Template source/noveris.build.psd1.tpl -Target source/noveris.build/noveris.build.psd1 -Content @{
        __FULLVERSION__ = $version.Full
    }

    # Trust powershell gallery
    Write-Information "Setup for access to powershell gallery"
    Use-PowerShellGallery

    # Install any dependencies for the module manifest
    Write-Information "Installing required dependencies from manifest"
    Install-PSModuleFromManifest -ManifestPath source/noveris.build/noveris.build.psd1

    # Test the module manifest
    Write-Information "Testing module manifest"
    Test-ModuleManifest source/noveris.build/noveris.build.psd1

    # Import modules as test
    Write-Information "Importing module"
    Import-Module ./source/noveris.build/noveris.build.psm1
}

Invoke-BuildStage -Name "Publish" -Filters $Stages -Script {
    # Publish module
    Publish-Module -Path ./source/noveris.build -NuGetApiKey $Env:NUGET_API_KEY
}
