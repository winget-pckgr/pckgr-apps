param(
    [string]$ManifestPath # Relative path to the manifest file
)

# Convert the relative path to an absolute path
$AbsolutePath = Join-Path -Path $env:GITHUB_WORKSPACE -ChildPath $ManifestPath


# Set global variables (if specific version needed, set it here)
$script:Prerelease = $false
$script:WinGetVersion = "" # Leave empty for the latest version
$tempFolder = [System.IO.Path]::GetTempPath()
$ProgressPreference = 'SilentlyContinue' 

# Function to download and install dependencies
function Download-Dependency {
    param (
        [Parameter(Mandatory = $true)]
        [string]$url,
        [Parameter(Mandatory = $true)]
        [string]$hash,
        [Parameter(Mandatory = $true)]
        [string]$saveTo
    )

    Invoke-WebRequest -Uri $url -OutFile $saveTo
    $fileHash = Get-FileHash -Path $saveTo -Algorithm SHA256
<#
    if ($fileHash.Hash -ne $hash) {
        throw "Hash mismatch for file: $saveTo"
    }

#>
}

# Function to get the release of winget
function Get-Release {
    $releasesAPIResponse = Invoke-RestMethod 'https://api.github.com/repos/microsoft/winget-cli/releases?per_page=100'
    if (!$script:Prerelease) {
        $releasesAPIResponse = $releasesAPIResponse.Where({ !$_.prerelease })
    }
    if (![String]::IsNullOrWhiteSpace($script:WinGetVersion)) {
        $releasesAPIResponse = @($releasesAPIResponse.Where({ $_.tag_name -match $('^v?' + [regex]::escape($script:WinGetVersion)) }))
    }
    if ($releasesAPIResponse.Count -lt 1) {
        Write-Output 'No WinGet releases found matching criteria'
        exit 1
    }

    $latestRelease = $releasesAPIResponse[0]
    $assetUrl = $latestRelease.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -ExpandProperty browser_download_url

    $wingetInstallerPath = Join-Path $tempFolder -ChildPath "winget.appxbundle"
    Invoke-WebRequest -Uri $assetUrl -OutFile $wingetInstallerPath

    return $wingetInstallerPath
}

# Dependency URLs and hashes
$vcLibsUwp = @{
    url    = 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx'
    hash   = '9BFDE6CFCC530EF073AB4BC9C4817575F63BE1251DD75AAA58CB89299697A569'
    SaveTo = Join-Path $tempFolder -ChildPath 'Microsoft.VCLibs.x64.14.00.Desktop.appx'
}

$uiLibsUwp = @{
    url    = 'https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.7.3/Microsoft.UI.Xaml.2.7.x64.appx'
    hash   = '8CE30D92ABEC6522BEB2544E7B716983F5CBA50751B580D89A36048BF4D90316'
    SaveTo = Join-Path $tempFolder -ChildPath 'Microsoft.UI.Xaml.2.7.x64.appx'
}

# Download and install dependencies
Download-Dependency @vcLibsUwp
Download-Dependency @uiLibsUwp

Add-AppxPackage -Path $vcLibsUwp.SaveTo -ErrorAction Ignore
Add-AppxPackage -Path $uiLibsUwp.SaveTo -ErrorAction Ignore

# Download and install winget
$wingetInstallerPath = Get-Release
Add-AppxPackage -Path $wingetInstallerPath

Write-Host "Winget and dependencies installed successfully."

#Test installing the package

# Get the directory path containing the installer.yaml file
$DirectoryPath = Split-Path -Path $ManifestPath -Parent

# Output the directory path
Write-Host "The directory path is: $DirectoryPath"

$result = winget install -m "$DirectoryPath" --silent
if($result -match 'Successfully installed')
{
    Write-Host "Application has successfully passed installation test"
    exit 0
}
else
{
    Write-Host "Application has failed installation test"
    exit 1
}
