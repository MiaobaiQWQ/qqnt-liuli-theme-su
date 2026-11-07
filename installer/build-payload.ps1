param()

$ErrorActionPreference = 'Stop'
$psDir = $PSScriptRoot
$root = Split-Path -Parent $psDir
$ps = Join-Path $psDir 'ps'

# 1) 插件 payload
$payloadDir = Join-Path $psDir '.payload-src'
if (Test-Path $payloadDir) { Remove-Item -LiteralPath $payloadDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $payloadDir | Out-Null
foreach ($item in @('manifest.json', 'main', 'preload', 'renderer', 'assets')) {
    $src = Join-Path $root $item
    if (Test-Path $src) { Copy-Item -LiteralPath $src -Destination $payloadDir -Recurse -Force }
}
$screens = Join-Path $payloadDir 'assets\screenshots'
if (Test-Path $screens) { Remove-Item -LiteralPath $screens -Recurse -Force }
foreach ($f in @('assets\wallpaper.jpg', 'assets\wallpaper.css')) {
    $p = Join-Path $payloadDir $f
    if (Test-Path $p) { Remove-Item -LiteralPath $p -Force }
}
$payloadZip = Join-Path $psDir 'payload.zip'
if (Test-Path $payloadZip) { Remove-Item -LiteralPath $payloadZip -Force }
Compress-Archive -Path (Join-Path $payloadDir '*') -DestinationPath $payloadZip -CompressionLevel Optimal
Remove-Item -LiteralPath $payloadDir -Recurse -Force
Write-Host ("payload.zip: {0:N0} bytes" -f (Get-Item $payloadZip).Length)

# 2) LiteLoaderQQNT core（MIT，1.4.1）
$coreDir = Join-Path $psDir 'vendor\liteloader'
if (-not (Test-Path (Join-Path $coreDir 'src'))) { throw '缺少 installer/vendor/liteloader/src' }
$coreZip = Join-Path $psDir 'lite-loader.zip'
if (Test-Path $coreZip) { Remove-Item -LiteralPath $coreZip -Force }
$coreStage = Join-Path $psDir '.core-src'
if (Test-Path $coreStage) { Remove-Item -LiteralPath $coreStage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $coreStage | Out-Null
foreach ($item in @('package.json', 'LICENSE', 'src')) {
    Copy-Item -LiteralPath (Join-Path $coreDir $item) -Destination $coreStage -Recurse -Force
}
Compress-Archive -Path (Join-Path $coreStage '*') -DestinationPath $coreZip -CompressionLevel Optimal
Remove-Item -LiteralPath $coreStage -Recurse -Force
Write-Host ("lite-loader.zip: {0:N0} bytes" -f (Get-Item $coreZip).Length)

# 3) 同步到 ps（直接运行脚本调试时用；编译时已内嵌）
Copy-Item -LiteralPath $payloadZip -Destination (Join-Path $ps 'payload.zip') -Force
Copy-Item -LiteralPath $coreZip -Destination (Join-Path $ps 'lite-loader.zip') -Force
Write-Host 'payload/core 已同步到 installer/ps'
