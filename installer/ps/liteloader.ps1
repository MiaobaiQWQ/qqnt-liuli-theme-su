# LiteLoaderQQNT 自动安装/复原模块
# 安装内容：core 到 <QQ>\LiteLoaderQQNT，QQ 启动入口、QQNT.dll 校验补丁、store.js 兼容修复。

function Test-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-QqVersionDir([string]$qqDir) {
    $versions = Join-Path $qqDir 'versions'
    if (-not (Test-Path -LiteralPath $versions -PathType Container)) { return '' }
    $dirs = @(Get-ChildItem -LiteralPath $versions -Directory | Sort-Object Name -Descending)
    if ($dirs.Count -eq 0) { return '' }
    $preferred = $dirs | Where-Object { $_.Name -like '9.9.36*' } | Select-Object -First 1
    if ($preferred) { return $preferred.FullName }
    return $dirs[0].FullName
}

function Find-BytePattern([byte[]]$haystack, [byte[]]$needle) {
    if ($null -eq $haystack -or $null -eq $needle -or $needle.Length -eq 0) { return @() }
    $enc = [Text.Encoding]::GetEncoding(28591)
    $h = $enc.GetString($haystack)
    $n = $enc.GetString($needle)
    $hits = New-Object System.Collections.Generic.List[int]
    $start = 0
    while ($start -le ($h.Length - $n.Length)) {
        $idx = $h.IndexOf($n, $start, [StringComparison]::Ordinal)
        if ($idx -lt 0) { break }
        $hits.Add($idx)
        $start = $idx + 1
    }
    return $hits.ToArray()
}

function Copy-TreeSafe([string]$src, [string]$dst) {
    if (-not (Test-Path -LiteralPath $src -PathType Container)) { return }
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $src -Force)) {
        $target = Join-Path $dst $item.Name
        if ($item.PSIsContainer) { Copy-TreeSafe $item.FullName $target }
        else { Copy-Item -LiteralPath $item.FullName -Destination $target -Force }
    }
}

function Expand-ZipBytes([byte[]]$bytes, [string]$dest) {
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $full = [IO.Path]::GetFullPath($dest).TrimEnd('\') + '\'
    $ms = New-Object IO.MemoryStream(,$bytes)
    $zip = New-Object IO.Compression.ZipArchive($ms, [IO.Compression.ZipArchiveMode]::Read)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('/', [IO.Path]::DirectorySeparatorChar)
            $target = [IO.Path]::GetFullPath((Join-Path $dest $name))
            if (-not $target.StartsWith($full, [StringComparison]::OrdinalIgnoreCase)) { throw ('非法压缩路径：' + $entry.FullName) }
            if ([string]::IsNullOrEmpty($entry.Name) -or $entry.FullName.EndsWith('/')) {
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                continue
            }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            $entry.ExtractToFile($target, $true)
        }
    } finally {
        $zip.Dispose(); $ms.Dispose()
    }
}

function Get-LiteLoaderBackups([string]$qqDir) {
    $root = Join-Path $qqDir 'liuli-backups'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $root -Directory |
        Where-Object {
            $r = Join-Path $_.FullName 'record.json'
            if (-not (Test-Path -LiteralPath $r -PathType Leaf)) { return $false }
            try { (Get-Content -LiteralPath $r -Raw -Encoding UTF8 | ConvertFrom-Json).kind -eq 'liteloader' } catch { return $false }
        } |
        Sort-Object Name -Descending |
        ForEach-Object { $_.FullName })
}

function Get-LatestLiteLoaderBackup([string]$qqDir) {
    $list = @(Get-LiteLoaderBackups $qqDir)
    if ($list.Count -eq 0) { return '' }
    return $list[0]
}

function Install-LiteLoader([string]$qqDir, [string]$profile, [string]$zipPath, [scriptblock]$Log) {
    if (-not (Test-Admin) -and -not $env:LIULI_INSTALLER_TEST_NO_ADMIN) { throw '自动安装 LiteLoaderQQNT 需要管理员权限，请右键以管理员身份运行安装器。' }
    if (-not $script:CoreBytes -and -not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw '安装包缺少 lite-loader.zip' }
    $versionDir = Get-QqVersionDir $qqDir
    if (-not $versionDir) { throw '找不到 QQ versions 目录' }
    $appDir = Join-Path $versionDir 'resources\app'
    $packageFile = Join-Path $appDir 'package.json'
    $dllFile = Join-Path $versionDir 'QQNT.dll'
    $launcherDir = Join-Path $appDir 'app_launcher'
    $launcherFile = Join-Path $launcherDir 'LiteLoader.js'
    $coreDir = Join-Path $qqDir 'LiteLoaderQQNT'
    if (-not (Test-Path -LiteralPath $packageFile -PathType Leaf)) { throw '找不到 QQ resources/app/package.json' }
    if (-not (Test-Path -LiteralPath $dllFile -PathType Leaf)) { throw '找不到 QQNT.dll' }

    New-Item -ItemType Directory -Force -Path $profile | Out-Null
    New-Item -ItemType Directory -Force -Path $coreDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupRoot = Join-Path $qqDir 'liuli-backups'
    $backup = Join-Path $backupRoot $stamp
    New-Item -ItemType Directory -Force -Path $backup | Out-Null

    $lljsExisted = Test-Path -LiteralPath $launcherFile -PathType Leaf
    $coreExisted = Test-Path -LiteralPath $coreDir -PathType Container
    Copy-Item -LiteralPath $packageFile -Destination (Join-Path $backup 'package.json') -Force
    Copy-Item -LiteralPath $dllFile -Destination (Join-Path $backup 'QQNT.dll') -Force
    if ($lljsExisted) { Copy-Item -LiteralPath $launcherFile -Destination (Join-Path $backup 'LiteLoader.js') -Force }
    if ($coreExisted) { Copy-TreeSafe $coreDir (Join-Path $backup 'core') }
    $envBefore = [Environment]::GetEnvironmentVariable('LITELOADERQQNT_PROFILE', 'User')
    $envSet = $false

    try {
        # 1) 解出 core，保留已有 plugins/data
        $tmpCore = Join-Path $profile ('.liuli-core-' + [guid]::NewGuid().ToString('N'))
        if ($script:CoreBytes) {
            $coreTmpZip = Join-Path $profile ('.liuli-core-' + [guid]::NewGuid().ToString('N') + '.zip')
            [IO.File]::WriteAllBytes($coreTmpZip, $script:CoreBytes)
            Expand-Archive -LiteralPath $coreTmpZip -DestinationPath $tmpCore -Force
            Remove-Item -LiteralPath $coreTmpZip -Force -ErrorAction SilentlyContinue
        } else {
            Expand-Archive -LiteralPath $zipPath -DestinationPath $tmpCore -Force
        }
        New-Item -ItemType Directory -Force -Path $coreDir | Out-Null
        foreach ($item in @(Get-ChildItem -LiteralPath $tmpCore -Force)) {
            $target = Join-Path $coreDir $item.Name
            if ($item.PSIsContainer) { Copy-TreeSafe $item.FullName $target }
            else { Copy-Item -LiteralPath $item.FullName -Destination $target -Force }
        }
        Remove-Item -LiteralPath $tmpCore -Recurse -Force -ErrorAction SilentlyContinue
        $Log.Invoke('LiteLoader core 已写入：' + $coreDir)

        # 2) 兼容 QQ 9.9.36 的 fs.Dirent.path 移除（1.4.1 已知 bug）
        $store = Join-Path $coreDir 'src\main\store.js'
        if (Test-Path -LiteralPath $store -PathType Leaf) {
            $t = Get-Content -LiteralPath $store -Raw -Encoding UTF8
            $t2 = $t.Replace('path.join(dirent.path, "manifest.json")', 'path.join(LiteLoader.path.plugins, dirent.name, "manifest.json")')
            if ($t2 -ne $t) {
                [IO.File]::WriteAllText($store, $t2, (New-Object Text.UTF8Encoding($false)))
                $Log.Invoke('已修复 LiteLoader store.js 的 dirent.path 兼容问题。')
            }
        }

        # 3) QQNT.dll 校验函数补丁（mov eax,1; ret）
        $bytes = [IO.File]::ReadAllBytes($dllFile)
        $pattern = [byte[]](0x41, 0x57, 0x41, 0x56, 0x41, 0x55)
        $replacement = [byte[]](0xB8, 0x01, 0x00, 0x00, 0x00, 0xC3)
        $hits = @(Find-BytePattern $bytes $pattern)
        if ($hits.Count -eq 1) {
            $at = $hits[0]
            for ($i = 0; $i -lt $replacement.Length; $i++) { $bytes[$at + $i] = $replacement[$i] }
            [IO.File]::WriteAllBytes($dllFile, $bytes)
            $Log.Invoke('已给 QQNT.dll 打校验补丁（偏移 0x{0:X}）。' -f $at)
        } elseif ($hits.Count -eq 0) {
            $already = @(Find-BytePattern $bytes $replacement)
            if ($already.Count -ge 1) { $Log.Invoke('QQNT.dll 已经是补丁状态，跳过。') }
            else { throw 'QQNT.dll 里找不到校验函数特征码，当前 QQ 版本可能不支持自动补丁。' }
        } else {
            throw ('QQNT.dll 里找到 ' + $hits.Count + ' 处特征码，无法确定补丁位置，已中止。')
        }

        # 4) 启动入口 + package.json main
        New-Item -ItemType Directory -Force -Path $launcherDir | Out-Null
        $escaped = $coreDir.Replace('`', '``')
        [IO.File]::WriteAllText($launcherFile,
            'require(String.raw`' + $escaped + '`);' + "`r`n",
            (New-Object Text.UTF8Encoding($false)))
        $pkg = Get-Content -LiteralPath $packageFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $pkg.main = './app_launcher/LiteLoader.js'
        [IO.File]::WriteAllText($packageFile,
            ($pkg | ConvertTo-Json -Depth 100),
            (New-Object Text.UTF8Encoding($false)))
        $Log.Invoke('已写入 LiteLoader 启动入口。')

        # 5) 确保 profile 可用；没有用户环境变量时指向 core 目录
        if (-not (Test-Path -LiteralPath (Join-Path $profile 'plugins') -PathType Container)) {
            New-Item -ItemType Directory -Force -Path (Join-Path $profile 'plugins') | Out-Null
        }
        $envExisting = [Environment]::GetEnvironmentVariable('LITELOADERQQNT_PROFILE', 'User')
        if ([string]::IsNullOrWhiteSpace($envExisting) -or -not (Test-Path -LiteralPath $envExisting)) {
            [Environment]::SetEnvironmentVariable('LITELOADERQQNT_PROFILE', $profile, 'User')
            $env:LITELOADERQQNT_PROFILE = $profile
            $envSet = $true
            $Log.Invoke('已设置用户环境变量 LITELOADERQQNT_PROFILE=' + $profile)
        }

        $record = [ordered]@{
            kind = 'liteloader'
            createdAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            versionDir = $versionDir
            packageBackup = 'package.json'
            dllBackup = 'QQNT.dll'
            lljsExisted = [bool]$lljsExisted
            lljsBackup = $(if ($lljsExisted) { 'LiteLoader.js' } else { '' })
            coreExisted = [bool]$coreExisted
            coreBackup = $(if ($coreExisted) { 'core' } else { '' })
            envBefore = [string]$envBefore
            envSet = [bool]$envSet
            installerVersion = '1.3.4'
        }
        $record | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $backup 'record.json') -Encoding UTF8
        return $backup
    } catch {
        try {
            if (Test-Path -LiteralPath $launcherFile -PathType Leaf) { Remove-Item -LiteralPath $launcherFile -Force }
            Copy-Item -LiteralPath (Join-Path $backup 'package.json') -Destination $packageFile -Force
            Copy-Item -LiteralPath (Join-Path $backup 'QQNT.dll') -Destination $dllFile -Force
            if ($lljsExisted -and (Test-Path -LiteralPath (Join-Path $backup 'LiteLoader.js'))) {
                New-Item -ItemType Directory -Force -Path $launcherDir | Out-Null
                Copy-Item -LiteralPath (Join-Path $backup 'LiteLoader.js') -Destination $launcherFile -Force
            }
            if ($coreExisted -and (Test-Path -LiteralPath (Join-Path $backup 'core'))) {
                if (Test-Path -LiteralPath $coreDir) { Remove-Item -LiteralPath $coreDir -Recurse -Force }
                Copy-TreeSafe (Join-Path $backup 'core') $coreDir
            }
            if ($envSet) { [Environment]::SetEnvironmentVariable('LITELOADERQQNT_PROFILE', $null, 'User') }
        } catch { }
        throw
    }
}

function Restore-LiteLoader([string]$qqDir, [string]$backup, [scriptblock]$Log) {
    if (-not $backup -or -not (Test-Path -LiteralPath (Join-Path $backup 'record.json') -PathType Leaf)) {
        return $false
    }
    $record = Get-Content -LiteralPath (Join-Path $backup 'record.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($record.kind -ne 'liteloader') { return $false }
    $versionDir = [string]$record.versionDir
    $appDir = Join-Path $versionDir 'resources\app'
    if (-not (Test-Path -LiteralPath $appDir -PathType Container)) { throw '备份对应的 QQ 版本目录不存在（QQ 可能已升级）' }
    $packageFile = Join-Path $appDir 'package.json'
    $dllFile = Join-Path $versionDir 'QQNT.dll'
    $launcherFile = Join-Path $appDir 'app_launcher\LiteLoader.js'
    $coreDir = Join-Path $qqDir 'LiteLoaderQQNT'

    if (Test-Path -LiteralPath (Join-Path $backup 'package.json')) {
        Copy-Item -LiteralPath (Join-Path $backup 'package.json') -Destination $packageFile -Force
    }
    if (Test-Path -LiteralPath (Join-Path $backup 'QQNT.dll')) {
        Copy-Item -LiteralPath (Join-Path $backup 'QQNT.dll') -Destination $dllFile -Force
    }
    if ($record.lljsExisted) {
        $src = Join-Path $backup 'LiteLoader.js'
        if (Test-Path -LiteralPath $src) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $launcherFile) | Out-Null
            Copy-Item -LiteralPath $src -Destination $launcherFile -Force
        }
    } else {
        if (Test-Path -LiteralPath $launcherFile) { Remove-Item -LiteralPath $launcherFile -Force }
    }
    if ($record.coreExisted) {
        $src = Join-Path $backup 'core'
        if (Test-Path -LiteralPath $src -PathType Container) {
            if (Test-Path -LiteralPath $coreDir) { Remove-Item -LiteralPath $coreDir -Recurse -Force }
            Copy-TreeSafe $src $coreDir
        }
    } else {
        if (Test-Path -LiteralPath $coreDir) { Remove-Item -LiteralPath $coreDir -Recurse -Force }
    }
    if ($record.envSet) {
        $before = [string]$record.envBefore
        if ([string]::IsNullOrWhiteSpace($before)) { [Environment]::SetEnvironmentVariable('LITELOADERQQNT_PROFILE', $null, 'User') }
        else { [Environment]::SetEnvironmentVariable('LITELOADERQQNT_PROFILE', $before, 'User') }
    }
    $Log.Invoke('已复原 LiteLoaderQQNT / QQ 补丁：' + $backup)
    return $true
}






