<#
#>

[CmdletBinding()]
param(
)

########
# Global settings
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

########
# Modules
Remove-Module Noveris.Build -EA SilentlyContinue
Import-Module ./source/Noveris.Build

########
# Project settings
$projectName = "noveris.build"

########
# Capture version information
$version = Get-BuildVersionInfo -Sources @(
    $Env:BUILD_SOURCEBRANCH,
    $Env:CI_COMMIT_TAG,
    $Env:BUILD_VERSION,
    "v0.1.0"
)

########
# Set up build directory
Use-BuildDirectories @(
    "package",
    "stage"
)

########
# Build stage
Invoke-BuildStage -Name "Build" -Script {

    Write-Information "Updating version information"
    Write-Information ("Setting BUILD_VERSION: " + $version.Full)
    Write-Information ("##vso[task.setvariable variable=BUILD_VERSION;]" + $version.Full)

    # Clear build directories
    Clear-BuildDirectories

    # Template PowerShell module definition
    Write-Information "Templating Noveris.Build.psd1"
    Format-TemplateFile -Template source/Noveris.Build.psd1.tpl -Target source/Noveris.Build/Noveris.Build.psd1 -Content @{
        __FULLVERSION__ = $version.Full
    }

    $artifactDir = $Env:BUILD_ARTIFACTSTAGINGDIRECTORY
    if (![string]::IsNullOrEmpty($artifactDir))
    {
      Copy-Item ./source/Noveris.Build/* $Env:BUILD_ARTIFACTSTAGINGDIRECTORY -Force -Recurse
    }

    Copy-Item ./source/Noveris.Build/* ./stage/ -Force -Recurse

    Write-Information "Packaging artifacts"
    $version = $version.Full
    $artifactName = "package/${projectName}-${version}.zip"
    Write-Information "Target file: ${artifactName}"

    Compress-Archive -Destination $artifactName -Path "./stage/*" -Force
}
