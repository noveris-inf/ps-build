<#
#>

################
# Global settings
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

################
# Script variables
$semVerPattern = "^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$"

$script:BuildState = [PSCustomObject]@{
    Stages = @{}
    RunState = @{}
}

$script:BuildArtifacts = New-Object 'System.Collections.Generic.HashSet[string]'
$script:BuildDirectories = New-Object 'System.Collections.Generic.HashSet[string]'

Function Use-EnvVar
{
    [CmdletBinding()]
    param(
        [Parameter(mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(mandatory=$false)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Default,

        [Parameter(mandatory=$false)]
        [ValidateNotNull()]
        [ScriptBlock]$Check
    )

    process
    {
        $val = $Default
        if (Test-Path "Env:\$Name")
        {
            $val = (Get-Item "Env:\$Name").Value
        } elseif ($PSBoundParameters.keys -notcontains "Default")
        {
            Write-Error "Missing environment variable ($Name) and no default specified"
        }

        if ($PSBoundParameters.keys -contains "Check")
        {
            $ret = $val | ForEach-Object -Process $Check
            if (!$ret)
            {
                Write-Error "Source string (${Source}) failed validation"
                return
            }
        }

        $val
    }
}

<#
#>
Function Get-BuildVersionInfo
{
    [CmdletBinding()]
    param(
        [Parameter(mandatory=$true)]
        [ValidateNotNull()]
        [AllowEmptyString()]
        [string[]]$Sources
    )

    process
    {
        foreach ($src in $Sources)
        {
            if ($null -eq $src -or $src -eq "")
            {
                continue
            }

            Write-Verbose "Processing version candidate: ${src}"

            # Strip any refs/tags/ reference at the beginning of the version source
            $tagBranch = "refs/tags/"
            if ($src.StartsWith($tagBranch))
            {
                Write-Verbose "Version starts with refs/tags format - Removing"
                $src = $src.Substring($tagBranch.Length)
            }

            if ($src.StartsWith("v"))
            {
                Write-Verbose "Version starts with 'v' - Removing"
                $src = $src.Substring(1)
            }

            if ($src -notmatch $semVerPattern)
            {
                Write-Verbose "Version string not in correct format. skipping"
                continue
            }

            $Prerelease = $Matches[4]
            if ($null -eq $Prerelease) {
                $Prerelease = ""
            }

            $Buildmetadata = $Matches[5]
            if ($null -eq $Buildmetadata) {
                $Buildmetadata = ""
            }

            $major = [Convert]::ToInt32($Matches[1])
            $minor = [Convert]::ToInt32($Matches[2])
            $patch = [Convert]::ToInt32($Matches[3])
            $plain = "${major}.${minor}.${patch}"

            Write-Verbose "Version is valid"
            [PSCustomObject]@{
                Full = $src
                Major = $major
                Minor = $minor
                Patch = $patch
                Prerelease = $Prerelease
                Buildmetadata = $Buildmetadata
                PlainVersion = $plain
                BuildVersion = ("{0}.{1}" -f $plain, (Get-BuildNumber))
                AssemblyVersion = "${major}.0.0.0"
            }

            return
        }

        # throw error as we didn't find a valid version source
        Write-Error "Could not find a valid version source"
    }
}

<#
#>
Function Assert-SuccessExitCode
{
	[CmdletBinding()]
	param(
		[Parameter(mandatory=$true)]
		[ValidateNotNull()]
		[int]$ExitCode,

		[Parameter(mandatory=$false)]
		[ValidateNotNull()]
		[int[]]$ValidCodes = @(0)
	)

	process
	{
		if ($ValidCodes -notcontains $ExitCode)
		{
			Write-Error "Invalid exit code: ${ExitCode}"
		}
	}
}

<#
#>
Function Invoke-BuildStage
{
    [CmdletBinding()]
    param(
        [Parameter(mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(mandatory=$true)]
        [ValidateNotNull()]
        [ScriptBlock]$Script
    )

    process
    {
		try {
            Write-Information ""
            Write-Information ("================ BEGIN ({0}) Stage: $Name" -f [DateTime]::Now.ToString("yyyyMMdd HHmm"))
            Write-Information ""

            & $Script *>&1 |
                ForEach-Object {
                    $timestamp = [DateTime]::Now.ToString("yyyyMMdd:HHmm")

                    if ([System.Management.Automation.InformationRecord].IsAssignableFrom($_.GetType()))
                    {
                        ("{0} (INFO): {1}" -f $timestamp, $_.ToString())
                    }
                    elseif ([System.Management.Automation.VerboseRecord].IsAssignableFrom($_.GetType()))
                    {
                        ("{0} (VERBOSE): {1}" -f $timestamp, $_.ToString())
                    }
                    elseif ([System.Management.Automation.ErrorRecord].IsAssignableFrom($_.GetType()))
                    {
                        $errors++
                        ("{0} (ERROR): {1}" -f $timestamp, $_.ToString())
                        $_ | Out-String -Stream | ForEach-Object {
                            ("{0} (ERROR): {1}" -f $timestamp, $_.ToString())
                        }
                    }
                    elseif ([System.Management.Automation.DebugRecord].IsAssignableFrom($_.GetType()))
                    {
                        ("{0} (DEBUG): {1}" -f $timestamp, $_.ToString())
                    }
                    elseif ([System.Management.Automation.WarningRecord].IsAssignableFrom($_.GetType()))
                    {
                        $warnings++
                        ("{0} (WARNING): {1}" -f $timestamp, $_.ToString())
                    }
                    elseif ([string].IsAssignableFrom($_.GetType()))
                    {
                        ("{0} (INFO): {1}" -f $timestamp, $_.ToString())
                    }
                    else
                    {
                        # Don't do ToString() here as this breaks things like Format-Table that
                        # don't convert to string properly. Out-String (below) will handle this for us.
                        $_
                    }
                } | Out-String -Stream
            Write-Information ("================ END ({0}) Stage: $_" -f [DateTime]::Now.ToString("yyyyMMdd HHmm"))
		} catch {
			$ex = $_

			# Display as information - Some systems don't show the exception properly
			Write-Information "Invoke-BuildStages failed with exception"
			Write-Information "Exception Information: $ex"
			Write-Information ("Exception is null?: " + ($null -eq $ex).ToString())

            Write-Information "Exception Members:"
			$ex | Get-Member

			Write-Information "Exception Properties: "
			$ex | Format-List -property *

            # rethrow exception
			throw $ex
		}
    }
}

<#
#>
Function Format-TemplateFile
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Template,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Target,

        [Parameter(Mandatory=$true)]
        [Hashtable]$Content
    )

    process
    {
        $dirPath = ([System.IO.Path]::GetDirectoryName($Target))
        if (![string]::IsNullOrEmpty($dirPath)) {
            New-Item -ItemType Directory -Path $dirPath -EA Ignore
        }

        Get-Content $Template -Encoding UTF8 | Format-TemplateString -Content $Content | Out-File -Encoding UTF8 $Target
    }
}

<#
#>
Function Format-TemplateString
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$TemplateString,

        [Parameter(Mandatory=$true)]
        [Hashtable]$Content
    )

    process
    {
        $working = $TemplateString

        $Content.Keys | ForEach-Object { $working = $working.Replace($_, $Content[$_]) }

        $working
    }
}

<#
#>
Function Get-BuildNumber {
    [OutputType('System.Int64')]
    [CmdletBinding()]
    param(
    )

    process
    {
        $MinDate = New-Object DateTime -ArgumentList 1970, 1, 1
        [Int64]([DateTime]::Now - $MinDate).TotalDays
    }
}

<#
#>
Function Use-BuildDirectories
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[AllowEmptyCollection()]
		[string[]]$Directories
	)

	process
	{
		$Directories | ForEach-Object { Use-BuildDirectory $_ }
	}
}

<#
#>
Function Use-BuildDirectory
{
    [CmdletBinding()]
    param(
        [Parameter(mandatory=$true,ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    process
    {
        New-Item -ItemType Directory $Path -EA Ignore | Out-Null

        Write-Information "Using build directory: ${Path}"
        if (!(Test-Path $Path -PathType Container)) {
            Write-Error "Target does not exist or is not a directory"
        }

        try {
            Get-Item $Path -Force | Out-Null
        } catch {
            Write-Error $_
        }

        $script:BuildDirectories.Add($Path) | Out-Null
    }
}

<#
#>
Function Clear-BuildDirectory
{
    [CmdletBinding()]
    param(
        [Parameter(mandatory=$true,ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    process
    {
        Use-BuildDirectory -Path $Path | Out-Null
        Write-Information "Clearing directory: ${Path}"
        Get-ChildItem -Path $Path | ForEach-Object { Remove-Item -Path $_.FullName -Recurse -Force }
    }
}

<#
#>
Function Clear-BuildDirectories
{
	[CmdletBinding()]
	param(
	)

	process
	{
        Write-Information "Clearing build directories"
        Get-BuildDirectories
        Get-BuildDirectories | ForEach-Object { Clear-BuildDirectory $_ }
	}
}

<#
#>
Function Get-BuildDirectories
{
    [CmdletBinding()]
    param(
    )

    process
    {
        $script:BuildDirectories | ForEach-Object { $_ }
    }
}
