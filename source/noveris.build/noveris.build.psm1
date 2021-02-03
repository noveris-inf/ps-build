<#
#>

#Requires -Modules @{"ModuleName"="Noveris.Logger";"RequiredVersion"="0.6.1"}
#Requires -Modules @{"ModuleName"="Noveris.Version";"RequiredVersion"="0.5.1"}
#Requires -Modules @{"ModuleName"="Noveris.GitHubApi";"RequiredVersion"="0.1.2"}

########
# Global settings
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

########
# Script variables
$script:BuildDirectories = New-Object 'System.Collections.Generic.HashSet[string]'

<#
#>
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
                Write-Error "Source string (${Name}) failed validation"
                return
            }
        }

        $val
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
        [ScriptBlock]$Script,

        [Parameter(mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Filters
    )

    process
    {
        if ($PSBoundParameters.Keys -contains "Filters" -and  ($Filters | ForEach-Object { $Name -eq $_ }) -notcontains $true)
        {
            # Filters have been supplied and our build stage name doesn't match
            return
        }

		try {
            Write-Information ""
            Write-Information ("================ BEGIN ({0}) Stage: $Name" -f [DateTime]::Now.ToString("yyyyMMdd HHmm"))
            Write-Information ""

            & $Script *>&1 |
                Format-RecordAsString -DisplaySummary |
                Out-String -Stream
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
        [Hashtable]$Content,

        [Parameter(Mandatory=$false)]
        [switch]$Stream = $false
    )

    process
    {
        $dirPath = ([System.IO.Path]::GetDirectoryName($Target))
        if (![string]::IsNullOrEmpty($dirPath)) {
            New-Item -ItemType Directory -Path $dirPath -EA Ignore
        }

        if (!$Stream)
        {
            $data = Get-Content $Template -Encoding UTF8 | Format-TemplateString -Content $Content
            $data | Out-File -Encoding UTF8 $Target
        } else {
            Get-Content $Template -Encoding UTF8 | Format-TemplateString -Content $Content | Out-File -Encoding UTF8 $Target
        }
    }
}

<#
#>
Function Format-TemplateString
{
    [OutputType('System.String')]
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
