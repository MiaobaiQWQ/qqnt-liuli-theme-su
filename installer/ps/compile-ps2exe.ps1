param(
    [Parameter(Mandatory = $true)][string]$Merged,
    [Parameter(Mandatory = $true)][string]$Out,
    [switch]$NoAdmin
)
$ErrorActionPreference = 'Stop'
Import-Module PS2EXE
$params = @{ inputFile = $Merged; outputFile = $Out; noConsole = $true; STA = $true; DPIAware = $true; version = '1.3.4'; title = '琉璃主题安装器'; description = '琉璃主题 + LiteLoaderQQNT 一键安装/复原' }
if (-not $NoAdmin) { $params.requireAdmin = $true }
Invoke-PS2EXE @params

