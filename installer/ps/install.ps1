param(
    [string]$QqPath = "",
    [string]$ProfilePath = "",
    [switch]$AutoInstall,
    [switch]$AutoRestore,
    [switch]$InstallLiteLoader,
    [switch]$NoRestart,
    [switch]$AutoClose
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'liteloader.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:PluginSlug = 'liuli-dsh-theme'
$script:InstallerVersion = '1.3.4'
$script:Payload = Join-Path $PSScriptRoot 'payload.zip'
$script:LiteLoaderZip = Join-Path $PSScriptRoot 'lite-loader.zip'
$script:Busy = $false
$script:AutoRun = ($AutoInstall -or $AutoRestore)
$script:LogBox = $null
$script:Form = $null
$script:QqBox = $null
$script:ProfileBox = $null
$script:QqInfo = $null
$script:ProfileInfo = $null
$script:InstallBtn = $null
$script:RestoreBtn = $null
$script:InstallLL = $null
$script:CloseQq = $null
$script:RestartQq = $null
$script:Status = $null
$script:Progress = $null

$script:ColBg = [Drawing.Color]::FromArgb(23, 26, 31)
$script:ColPanel = [Drawing.Color]::FromArgb(31, 35, 42)
$script:ColPanel2 = [Drawing.Color]::FromArgb(38, 43, 51)
$script:ColText = [Drawing.Color]::FromArgb(232, 234, 238)
$script:ColMuted = [Drawing.Color]::FromArgb(155, 162, 173)
$script:ColAccent = [Drawing.Color]::FromArgb(92, 160, 255)
$script:ColGreen = [Drawing.Color]::FromArgb(92, 203, 143)
$script:ColRed = [Drawing.Color]::FromArgb(245, 115, 115)

function New-UiFont([float]$size = 9, [Drawing.FontStyle]$style = [Drawing.FontStyle]::Regular) {
    try { return New-Object Drawing.Font('Microsoft YaHei UI', $size, $style) }
    catch { return New-Object Drawing.Font([Drawing.FontFamily]::GenericSansSerif, $size, $style) }
}

function Add-Log([string]$message) {
    if ($null -eq $script:LogBox) { return }
    try {
        $line = '[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $message + "`r`n"
        $script:LogBox.AppendText($line)
        $script:LogBox.SelectionStart = $script:LogBox.TextLength
        $script:LogBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
        try { Add-Content -LiteralPath ('C:\Users\Public\liuli-installer.log') -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
    } catch { }
}

function Normalize-Dir([string]$path) {
    try {
        if ([string]::IsNullOrWhiteSpace($path)) { return '' }
        $path = $path.Trim().Trim('"')
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            if ([IO.Path]::GetFileName($path) -ieq 'QQ.exe') { $path = Split-Path -Parent $path }
        }
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { return '' }
        return (Resolve-Path -LiteralPath $path).Path.TrimEnd('\', '/')
    } catch { return '' }
}

function Test-QqDir([string]$dir) {
    if ([string]::IsNullOrWhiteSpace($dir)) { return $false }
    return Test-Path -LiteralPath (Join-Path $dir 'QQ.exe') -PathType Leaf
}

function Test-Profile([string]$dir) {
    if ([string]::IsNullOrWhiteSpace($dir)) { return $false }
    return Test-Path -LiteralPath (Join-Path $dir 'plugins') -PathType Container
}

function Find-Qq([string]$preferred) {
    $direct = Normalize-Dir $preferred
    if (Test-QqDir $direct) { return $direct }

    foreach ($p in @(Get-Process -Name QQ -ErrorAction SilentlyContinue)) {
        try {
            $d = Normalize-Dir $p.MainModule.FileName
            if (Test-QqDir $d) { return $d }
        } catch { }
    }

    $keys = @(
        'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\QQ',
        'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\QQ',
        'SOFTWARE\Tencent\QQ',
        'SOFTWARE\WOW6432Node\Tencent\QQ'
    )
    foreach ($key in $keys) {
        foreach ($root in @('HKLM:', 'HKCU:')) {
            try {
                $p = Get-ItemProperty -Path ($root + '\' + $key) -ErrorAction SilentlyContinue
                if ($null -eq $p) { continue }
                foreach ($name in @('InstallLocation', 'InstallPath', 'DisplayIcon', 'UninstallString')) {
                    $v = [string]$p.$name
                    if ([string]::IsNullOrWhiteSpace($v)) { continue }
                    $v = $v.Trim().Trim('"')
                    if ($v.Contains(',')) { $v = $v.Split(',')[0].Trim().Trim('"') }
                    $d = Normalize-Dir $v
                    if (Test-QqDir $d) { return $d }
                }
            } catch { }
        }
    }

    $candidates = @(
        (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Tencent\QQNT'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Tencent\QQ'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Tencent\QQNT'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Tencent\QQ'),
        'C:\Tencent\QQNT',
        'D:\Tencent\QQNT',
        'D:\Program Files\Tencent\QQNT'
    )
    foreach ($c in $candidates) {
        $d = Normalize-Dir $c
        if (Test-QqDir $d) { return $d }
    }
    return ''
}

function Find-Profile([string]$qqDir) {
    $candidates = @()
    if ($env:LITELOADERQQNT_PROFILE) { $candidates += $env:LITELOADERQQNT_PROFILE }
    if ($qqDir) {
        $candidates += (Join-Path $qqDir 'LiteLoaderQQNT')
        try {
            $parent = Split-Path -Parent $qqDir
            if ($parent) { $candidates += (Join-Path $parent 'LiteLoaderQQNT') }
        } catch { }
    }
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $user = [Environment]::GetFolderPath('UserProfile')
    if ($docs) { $candidates += (Join-Path $docs 'LiteLoaderQQNT') }
    if ($user) {
        $candidates += (Join-Path $user 'LiteLoaderQQNT')
        $candidates += (Join-Path $user 'Documents\LiteLoaderQQNT')
    }
    $appData = [Environment]::GetFolderPath('ApplicationData'); if ($appData) { $candidates += (Join-Path $appData 'LiteLoaderQQNT') }
    foreach ($c in $candidates) {
        $d = Normalize-Dir $c
        if (Test-Profile $d) { return $d }
    }
    return ''
}

function Get-QqVersion([string]$qqDir) {
    try {
        $versions = Join-Path $qqDir 'versions'
        if (-not (Test-Path -LiteralPath $versions -PathType Container)) { return '' }
        $dirs = @(Get-ChildItem -LiteralPath $versions -Directory | Sort-Object Name -Descending)
        if ($dirs.Count -gt 0) { return $dirs[0].Name }
    } catch { }
    return ''
}

function Get-InstalledVersion([string]$profile) {
    try {
        $m = Join-Path $profile ('plugins\' + $script:PluginSlug + '\manifest.json')
        if (-not (Test-Path -LiteralPath $m -PathType Leaf)) { return '' }
        $j = Get-Content -LiteralPath $m -Raw -Encoding UTF8 | ConvertFrom-Json
        return [string]$j.version
    } catch { return '' }
}

function Get-Backups([string]$profile) {
    $root = Join-Path $profile 'liuli-backups'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $root -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'record.json') -PathType Leaf } |
        Sort-Object Name -Descending |
        ForEach-Object { $_.FullName })
}

function Test-QqRunning([string]$qqDir) {
    foreach ($name in @('QQ', 'QQEX')) {
        foreach ($p in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try {
                $f = $p.MainModule.FileName
                if ([string]::IsNullOrEmpty($qqDir) -or $f.StartsWith($qqDir, [StringComparison]::OrdinalIgnoreCase)) { return $true }
            } catch { return $true }
        }
    }
    return $false
}

function Close-Qq([string]$qqDir) {
    $any = $false
    foreach ($name in @('QQ', 'QQEX')) {
        foreach ($p in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try {
                $f = $p.MainModule.FileName
                if ($qqDir -and -not $f.StartsWith($qqDir, [StringComparison]::OrdinalIgnoreCase)) { continue }
                $any = $true
                if ($p.MainWindowHandle -ne 0) { $p.CloseMainWindow() | Out-Null }
            } catch { }
        }
    }
    if (-not $any) { return $false }
    Add-Log '正在关闭 QQ…'
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 250
        $left = @(Get-Process -Name QQ,QQEX -ErrorAction SilentlyContinue | Where-Object {
            try { [string]::IsNullOrEmpty($qqDir) -or $_.MainModule.FileName.StartsWith($qqDir, [StringComparison]::OrdinalIgnoreCase) } catch { $true }
        })
        if ($left.Count -eq 0) { break }
    }
    foreach ($name in @('QQ', 'QQEX')) {
        foreach ($p in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try {
                $f = $p.MainModule.FileName
                if ($qqDir -and -not $f.StartsWith($qqDir, [StringComparison]::OrdinalIgnoreCase)) { continue }
                if (-not $p.HasExited) { $p.Kill() }
            } catch { }
        }
    }
    Start-Sleep -Milliseconds 800
    Add-Log 'QQ 已关闭。'
    return $true
}

function Start-Qq([string]$qqDir) {
    $exe = Join-Path $qqDir 'QQ.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw '找不到 QQ.exe' }
    Start-Process -FilePath $exe -WorkingDirectory $qqDir | Out-Null
    Add-Log '已启动 QQ。'
}

function Copy-Tree([string]$src, [string]$dst) {
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $src -Force)) {
        $target = Join-Path $dst $item.Name
        if ($item.PSIsContainer) { Copy-Tree $item.FullName $target }
        else { Copy-Item -LiteralPath $item.FullName -Destination $target -Force }
    }
}

function Get-PluginDir([string]$profile) {
    return (Join-Path $profile ('plugins\' + $script:PluginSlug))
}

function Install-Plugin([string]$profile, [string]$qqDir) {
    if (-not $script:PayloadBytes -and -not (Test-Path -LiteralPath $script:Payload -PathType Leaf)) { throw '安装包损坏：找不到 payload.zip' }
    $plugin = Get-PluginDir $profile
    $backups = Join-Path $profile 'liuli-backups'
    New-Item -ItemType Directory -Force -Path $backups | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $backups $stamp
    New-Item -ItemType Directory -Force -Path $backup | Out-Null

    $had = Test-Path -LiteralPath $plugin -PathType Container
    $oldVersion = if ($had) { Get-InstalledVersion $profile } else { '' }
    if ($had) {
        Add-Log ('备份旧版本到 ' + $backup)
        Copy-Tree $plugin (Join-Path $backup 'plugin')
    } else {
        Add-Log '未检测到已安装的琉璃，首次安装。'
    }
    $record = [ordered]@{
        createdAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        hadPlugin = [bool]$had
        pluginVersion = [string]$oldVersion
        installerVersion = $script:InstallerVersion
    }
    $record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'record.json') -Encoding UTF8

    $staging = Join-Path $profile ('.liuli-installing-' + [guid]::NewGuid().ToString('N'))
    try {
        if ($script:PayloadBytes) { Expand-ZipBytes $script:PayloadBytes $staging } else { Expand-Archive -LiteralPath $script:Payload -DestinationPath $staging -Force }
        if (-not (Test-Path -LiteralPath (Join-Path $staging 'manifest.json') -PathType Leaf)) {
            throw '安装包缺少 manifest.json'
        }
        if (Test-Path -LiteralPath $plugin -PathType Container) { Remove-Item -LiteralPath $plugin -Recurse -Force }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $plugin) | Out-Null
        Move-Item -LiteralPath $staging -Destination $plugin -Force
        Add-Log ('已写入插件目录：' + $plugin)
    } catch {
        try { if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force } } catch { }
        try { if (Test-Path -LiteralPath $plugin) { Remove-Item -LiteralPath $plugin -Recurse -Force } } catch { }
        if ($had) {
            try {
                Copy-Tree (Join-Path $backup 'plugin') $plugin
                Add-Log '安装失败，已回滚到旧版本。'
            } catch { }
        }
        throw
    }
    return $backup
}

function Restore-Latest([string]$profile) {
    $list = @(Get-Backups $profile)
    if ($list.Count -eq 0) { throw '没有可复原的备份' }
    $backup = $list[0]
    $record = Get-Content -LiteralPath (Join-Path $backup 'record.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $plugin = Get-PluginDir $profile

    $preRoot = Join-Path $profile 'liuli-backups'
    $pre = Join-Path $preRoot ('pre-restore-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    if (Test-Path -LiteralPath $plugin -PathType Container) {
        New-Item -ItemType Directory -Force -Path $pre | Out-Null
        Copy-Tree $plugin (Join-Path $pre 'plugin')
        [ordered]@{
            createdAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            hadPlugin = $true
            pluginVersion = [string](Get-InstalledVersion $profile)
            installerVersion = $script:InstallerVersion
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pre 'record.json') -Encoding UTF8
    }

    if (Test-Path -LiteralPath $plugin -PathType Container) { Remove-Item -LiteralPath $plugin -Recurse -Force }
    if ($record.hadPlugin) {
        $src = Join-Path $backup 'plugin'
        if (-not (Test-Path -LiteralPath $src -PathType Container)) { throw '备份内容不完整' }
        Copy-Tree $src $plugin
        Add-Log ('已还原备份：' + $backup)
    } else {
        Add-Log '原始状态为未安装，已移除琉璃插件。'
    }
}

function Set-Busy([bool]$busy, [string]$text) {
    $script:Busy = $busy
    $script:Progress.Visible = $busy
    $script:InstallBtn.Enabled = -not $busy
    $script:RestoreBtn.Enabled = -not $busy
    $script:Status.Text = $text
    $script:Status.ForeColor = $script:ColMuted
    [System.Windows.Forms.Application]::DoEvents()
}

function Refresh-Info {
    $qq = Normalize-Dir $script:QqBox.Text
    $qqOk = Test-QqDir $qq
    if ($qqOk) {
        $ver = Get-QqVersion $qq
        $script:QqInfo.Text = '已识别 QQ' + $(if ($ver) { '  ·  ' + $ver } else { '' }) + $(if ($ver.StartsWith('9.9.36')) { '  ·  支持' } else { '  ·  建议使用 9.9.36' })
        $script:QqInfo.ForeColor = if ($ver.StartsWith('9.9.36')) { $script:ColGreen } else { [Drawing.Color]::FromArgb(235, 185, 100) }
    } else {
        $script:QqInfo.Text = '未在所选目录找到 QQ.exe。'
        $script:QqInfo.ForeColor = $script:ColRed
    }
    $profile = Normalize-Dir $script:ProfileBox.Text
    $profileOk = Test-Profile $profile
    if ($profileOk) {
        $installed = Get-InstalledVersion $profile
        $backups = @(Get-Backups $profile).Count
        $script:ProfileInfo.Text = 'LiteLoader 数据目录有效' + $(if ($installed) { '  ·  已装琉璃 ' + $installed } else { '  ·  尚未安装琉璃' }) + '  ·  可复原备份 ' + $backups + ' 个'
        $script:ProfileInfo.ForeColor = $script:ColGreen
    } else {
        $script:ProfileInfo.Text = '未找到 plugins 目录。请先安装 LiteLoaderQQNT，或手动选择它的数据目录。'
        $script:ProfileInfo.ForeColor = $script:ColRed
    }
    $script:InstallBtn.Enabled = (-not $script:Busy) -and $qqOk -and $profileOk
    $script:RestoreBtn.Enabled = (-not $script:Busy) -and $profileOk
}

function Install-OneClick {
    if ($script:Busy) { return }
    $qq = Normalize-Dir $script:QqBox.Text
    $profile = Normalize-Dir $script:ProfileBox.Text
    $installLL = [bool]$script:InstallLL.Checked
    if (-not (Test-QqDir $qq)) { [Windows.Forms.MessageBox]::Show('QQ 安装目录无效：需要包含 QQ.exe。', '提示', 'OK', 'Warning') | Out-Null; return }
    if (-not $installLL -and -not (Test-Profile $profile)) {
        [Windows.Forms.MessageBox]::Show('LiteLoader 数据目录无效：需要包含 plugins 文件夹。', '提示', 'OK', 'Warning') | Out-Null
        return
    }
    if ($installLL -and -not (Test-Admin) -and -not $env:LIULI_INSTALLER_TEST_NO_ADMIN) {
        [Windows.Forms.MessageBox]::Show("自动安装 LiteLoaderQQNT 需要管理员权限。`n`n请关闭安装器，右键选择「以管理员身份运行」，再点一键安装。", '需要管理员权限', 'OK', 'Warning') | Out-Null
        return
    }
    if ($installLL -and -not $script:AutoRun) {
        $r = [Windows.Forms.MessageBox]::Show("将自动安装 LiteLoaderQQNT，并修改：`n`n- QQ resources/app/package.json（启动入口）`n- QQNT.dll（校验补丁）`n`n安装前会备份原文件，可用「一键复原」回退。`n修改 QQ 文件可能触发腾讯风控，请自行评估账号风险。`n`n继续吗？", '安装 LiteLoaderQQNT', 'YesNo', 'Warning')
        if ($r -ne [Windows.Forms.DialogResult]::Yes) { return }
    }
    $running = Test-QqRunning $qq
    if ($running -and -not $script:CloseQq.Checked) {
        [Windows.Forms.MessageBox]::Show('QQ 正在运行。请勾选「安装/复原前自动关闭 QQ」，或手动退出 QQ 再安装。', '提示', 'OK', 'Warning') | Out-Null
        return
    }
    if ($running -and -not $script:AutoRun) {
        $r = [Windows.Forms.MessageBox]::Show('安装需要先关闭 QQ，完成后可自动启动。继续吗？', '确认', 'YesNo', 'Question')
        if ($r -ne [Windows.Forms.DialogResult]::Yes) { return }
    }
    Set-Busy $true '正在安装…'
    Add-Log ('开始安装到 ' + $qq)
    try {
        if ($running) { Close-Qq $qq | Out-Null }
        if ($installLL) {
            if (-not (Test-Profile $profile)) { $profile = Join-Path $qq 'LiteLoaderQQNT' }
            $script:ProfileBox.Text = $profile
            Add-Log '开始安装 LiteLoaderQQNT…'
            $llBackup = Install-LiteLoader $qq $profile $script:LiteLoaderZip { param($m) Add-Log $m }
            Add-Log ('LiteLoader 备份：' + $llBackup)
            Refresh-Info
        }
        if (-not (Test-Profile $profile)) { throw 'LiteLoader 数据目录无效：需要包含 plugins 文件夹。' }
        $backup = Install-Plugin $profile $qq
        Add-Log '安装完成。'
        if ($backup) { Add-Log ('旧版本备份：' + $backup) }
        Refresh-Info
        if ($script:RestartQq.Checked -or ($script:AutoRun -and -not $NoRestart -and $running)) {
            try { Start-Qq $qq } catch { Add-Log ('启动 QQ 失败：' + $_.Exception.Message) }
        }
        $script:Status.ForeColor = $script:ColGreen
        $script:Status.Text = '安装完成'
        if (-not $script:AutoRun) {
            [Windows.Forms.MessageBox]::Show("琉璃已安装完成。`n`n" + $(if ($backup) { "旧版本已备份：`n$backup" } else { '这是首次安装。' }), '安装完成', 'OK', 'Information') | Out-Null
        }
    } catch {
        Add-Log ('安装失败：' + $_.Exception.Message)
        $script:Status.ForeColor = $script:ColRed
        $script:Status.Text = '安装失败'
        if (-not $script:AutoRun) { [Windows.Forms.MessageBox]::Show("安装失败：`n" + $_.Exception.Message, '错误', 'OK', 'Error') | Out-Null }
    } finally {
        Set-Busy $false ''
        $script:AutoRun = $false
    }
}

function Restore-OneClick {
    if ($script:Busy) { return }
    $qq = Normalize-Dir $script:QqBox.Text
    $profile = Normalize-Dir $script:ProfileBox.Text
    $llBackup = Get-LatestLiteLoaderBackup $qq
    $backups = @()
    if (Test-Profile $profile) { $backups = @(Get-Backups $profile) }
    if ($backups.Count -eq 0 -and -not $llBackup) {
        [Windows.Forms.MessageBox]::Show('没有可复原的备份。请先安装一次（安装时会自动备份）。', '提示', 'OK', 'Warning') | Out-Null
        return
    }
    if ($llBackup -and -not (Test-Admin) -and -not $env:LIULI_INSTALLER_TEST_NO_ADMIN) {
        [Windows.Forms.MessageBox]::Show("复原 LiteLoaderQQNT / QQ 补丁需要管理员权限。`n`n请关闭安装器，右键选择「以管理员身份运行」，再点一键复原。", '需要管理员权限', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not $script:AutoRun) {
        $what = @()
        if ($backups.Count -gt 0) { $what += ('琉璃插件：' + $backups[0]) }
        if ($llBackup) { $what += ('LiteLoader / QQ 补丁：' + $llBackup) }
        $r = [Windows.Forms.MessageBox]::Show("将回滚到安装前的状态：`n`n" + ($what -join "`n") + "`n`n当前版本会先另存为 pre-restore 备份。继续吗？", '一键复原', 'YesNo', 'Question')
        if ($r -ne [Windows.Forms.DialogResult]::Yes) { return }
    }
    $running = Test-QqRunning $qq
    if ($running -and -not $script:CloseQq.Checked) {
        [Windows.Forms.MessageBox]::Show('QQ 正在运行。请勾选「安装/复原前自动关闭 QQ」，或手动退出 QQ 再复原。', '提示', 'OK', 'Warning') | Out-Null
        return
    }
    Set-Busy $true '正在复原…'
    Add-Log '开始回滚到安装前状态…'
    try {
        if ($running) { Close-Qq $qq | Out-Null }
        if ($backups.Count -gt 0) {
            Add-Log ('复原插件：' + $backups[0])
            Restore-Latest $profile
        }
        if ($llBackup) {
            Add-Log ('复原 LiteLoader / QQ 补丁：' + $llBackup)
            Restore-LiteLoader $qq $llBackup { param($m) Add-Log $m } | Out-Null
        }
        Add-Log '复原完成。'
        Refresh-Info
        if (($script:RestartQq.Checked -or ($script:AutoRun -and -not $NoRestart)) -and (Test-QqDir $qq)) {
            try { Start-Qq $qq } catch { Add-Log ('启动 QQ 失败：' + $_.Exception.Message) }
        }
        $script:Status.ForeColor = $script:ColGreen
        $script:Status.Text = '复原完成'
        if (-not $script:AutoRun) { [Windows.Forms.MessageBox]::Show('已回滚到安装前的插件和 LiteLoader / QQ 文件状态。', '复原完成', 'OK', 'Information') | Out-Null }
    } catch {
        Add-Log ('复原失败：' + $_.Exception.Message)
        $script:Status.ForeColor = $script:ColRed
        $script:Status.Text = '复原失败'
        if (-not $script:AutoRun) { [Windows.Forms.MessageBox]::Show("复原失败：`n" + $_.Exception.Message, '错误', 'OK', 'Error') | Out-Null }
    } finally {
        Set-Busy $false ''
        $script:AutoRun = $false
    }
}

# ---------- UI ----------
$form = New-Object Windows.Forms.Form
$form.Text = '琉璃主题 · 一键安装器'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object Drawing.Size(860, 650)
$form.MinimumSize = New-Object Drawing.Size(780, 630)
$form.BackColor = $script:ColBg
$form.ForeColor = $script:ColText
$form.Font = New-UiFont 9
$form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::None
$script:Form = $form

$title = New-Object Windows.Forms.Label
$title.Text = '琉璃主题 · 一键安装器'
$title.Font = New-UiFont 19 ([Drawing.FontStyle]::Bold)
$title.ForeColor = $script:ColText
$title.AutoSize = $true
$title.Location = New-Object Drawing.Point(26, 20)
$form.Controls.Add($title)

$sub = New-Object Windows.Forms.Label
$sub.Text = '把 liuli-dsh-theme 安装到 LiteLoaderQQNT；自动备份旧版本，支持一键复原。'
$sub.ForeColor = $script:ColMuted
$sub.AutoSize = $true
$sub.Location = New-Object Drawing.Point(28, 58)
$sub.Visible = $false
$form.Controls.Add($sub)

function New-Group([string]$text, [Drawing.Point]$loc, [Drawing.Size]$size) {
    $g = New-Object Windows.Forms.GroupBox
    $g.Text = $text
    $g.Location = $loc
    $g.Size = $size
    $g.ForeColor = $script:ColText
    $g.BackColor = $script:ColPanel
    $g.Font = New-UiFont 9 ([Drawing.FontStyle]::Bold)
    $g.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Left -bor [Windows.Forms.AnchorStyles]::Right
    return $g
}

$qqGroup = New-Group 'QQ' (New-Object Drawing.Point(24, 92)) (New-Object Drawing.Size(812, 126))
$form.Controls.Add($qqGroup)
$lbl = New-Object Windows.Forms.Label; $lbl.Text = '安装目录'; $lbl.AutoSize = $true; $lbl.ForeColor = $script:ColMuted; $lbl.Location = New-Object Drawing.Point(16, 38); $qqGroup.Controls.Add($lbl)
$script:QqBox = New-Object Windows.Forms.TextBox
$script:QqBox.Location = New-Object Drawing.Point(110, 30); $script:QqBox.Size = New-Object Drawing.Size(500, 30)
$script:QqBox.BackColor = $script:ColPanel2; $script:QqBox.ForeColor = $script:ColText; $script:QqBox.BorderStyle = 'FixedSingle'; $script:QqBox.Font = New-UiFont 9
$script:QqBox.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Left -bor [Windows.Forms.AnchorStyles]::Right
$qqGroup.Controls.Add($script:QqBox)
$browseQq = New-Object Windows.Forms.Button; $browseQq.Text = '浏览…'; $browseQq.Location = New-Object Drawing.Point(620, 28); $browseQq.Size = New-Object Drawing.Size(86, 30); $browseQq.FlatStyle = 'Flat'; $browseQq.BackColor = $script:ColPanel2; $browseQq.ForeColor = $script:ColText; $browseQq.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(64, 71, 82)
$qqGroup.Controls.Add($browseQq)
$detectQq = New-Object Windows.Forms.Button; $detectQq.Text = '自动检测'; $detectQq.Location = New-Object Drawing.Point(714, 28); $detectQq.Size = New-Object Drawing.Size(82, 30); $detectQq.FlatStyle = 'Flat'; $detectQq.BackColor = $script:ColPanel2; $detectQq.ForeColor = $script:ColText; $detectQq.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(64, 71, 82)
$qqGroup.Controls.Add($detectQq)
$script:QqInfo = New-Object Windows.Forms.Label; $script:QqInfo.Location = New-Object Drawing.Point(112, 70); $script:QqInfo.Size = New-Object Drawing.Size(680, 38); $script:QqInfo.ForeColor = $script:ColMuted; $script:QqInfo.Font = New-UiFont 8.5
$qqGroup.Controls.Add($script:QqInfo)

$profileGroup = New-Group 'LiteLoaderQQNT 数据目录（plugins 所在目录）' (New-Object Drawing.Point(24, 236)) (New-Object Drawing.Size(812, 126))
$form.Controls.Add($profileGroup)
$lbl2 = New-Object Windows.Forms.Label; $lbl2.Text = '数据目录'; $lbl2.AutoSize = $true; $lbl2.ForeColor = $script:ColMuted; $lbl2.Location = New-Object Drawing.Point(16, 38); $profileGroup.Controls.Add($lbl2)
$script:ProfileBox = New-Object Windows.Forms.TextBox
$script:ProfileBox.Location = New-Object Drawing.Point(110, 30); $script:ProfileBox.Size = New-Object Drawing.Size(500, 30)
$script:ProfileBox.BackColor = $script:ColPanel2; $script:ProfileBox.ForeColor = $script:ColText; $script:ProfileBox.BorderStyle = 'FixedSingle'; $script:ProfileBox.Font = New-UiFont 9
$script:ProfileBox.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Left -bor [Windows.Forms.AnchorStyles]::Right
$profileGroup.Controls.Add($script:ProfileBox)
$browseProfile = New-Object Windows.Forms.Button; $browseProfile.Text = '浏览…'; $browseProfile.Location = New-Object Drawing.Point(620, 28); $browseProfile.Size = New-Object Drawing.Size(86, 30); $browseProfile.FlatStyle = 'Flat'; $browseProfile.BackColor = $script:ColPanel2; $browseProfile.ForeColor = $script:ColText; $browseProfile.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(64, 71, 82)
$profileGroup.Controls.Add($browseProfile)
$detectProfile = New-Object Windows.Forms.Button; $detectProfile.Text = '自动检测'; $detectProfile.Location = New-Object Drawing.Point(714, 28); $detectProfile.Size = New-Object Drawing.Size(82, 30); $detectProfile.FlatStyle = 'Flat'; $detectProfile.BackColor = $script:ColPanel2; $detectProfile.ForeColor = $script:ColText; $detectProfile.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(64, 71, 82)
$profileGroup.Controls.Add($detectProfile)
$script:ProfileInfo = New-Object Windows.Forms.Label; $script:ProfileInfo.Location = New-Object Drawing.Point(112, 70); $script:ProfileInfo.Size = New-Object Drawing.Size(680, 38); $script:ProfileInfo.ForeColor = $script:ColMuted; $script:ProfileInfo.Font = New-UiFont 8.5
$profileGroup.Controls.Add($script:ProfileInfo)

$script:InstallLL = New-Object Windows.Forms.CheckBox; $script:InstallLL.Text = '自动安装 LiteLoaderQQNT（会备份并修改 QQNT.dll / package.json）'; $script:InstallLL.Checked = $true; $script:InstallLL.AutoSize = $true; $script:InstallLL.ForeColor = $script:ColText; $script:InstallLL.Location = New-Object Drawing.Point(28, 366)
$form.Controls.Add($script:InstallLL)
$llWarn = New-Object Windows.Forms.Label; $llWarn.Text = '需要管理员权限；会修改 QQ 文件绕过校验，可能触发腾讯风控，请自行评估账号风险。'; $llWarn.AutoSize = $true; $llWarn.ForeColor = [Drawing.Color]::FromArgb(235, 185, 100); $llWarn.Location = New-Object Drawing.Point(46, 390)
$form.Controls.Add($llWarn)

$script:CloseQq = New-Object Windows.Forms.CheckBox; $script:CloseQq.Text = '安装/复原前自动关闭 QQ'; $script:CloseQq.Checked = $true; $script:CloseQq.AutoSize = $true; $script:CloseQq.ForeColor = $script:ColText; $script:CloseQq.Location = New-Object Drawing.Point(28, 416)
$form.Controls.Add($script:CloseQq)
$script:RestartQq = New-Object Windows.Forms.CheckBox; $script:RestartQq.Text = '完成后自动启动 QQ'; $script:RestartQq.Checked = $true; $script:RestartQq.AutoSize = $true; $script:RestartQq.ForeColor = $script:ColText; $script:RestartQq.Location = New-Object Drawing.Point(246, 416)
$form.Controls.Add($script:RestartQq)

function New-Btn([string]$text, [Drawing.Point]$loc, [Drawing.Size]$size, [bool]$primary) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text; $b.Location = $loc; $b.Size = $size; $b.FlatStyle = 'Flat'; $b.Font = New-UiFont 8.5
    if ($primary) {
        $b.BackColor = $script:ColAccent; $b.ForeColor = [Drawing.Color]::White; $b.FlatAppearance.BorderSize = 0
    } else {
        $b.BackColor = $script:ColPanel2; $b.ForeColor = $script:ColText; $b.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(64, 71, 82); $b.FlatAppearance.BorderSize = 1
    }
    return $b
}

$script:InstallBtn = New-Btn '一键替换 / 安装' (New-Object Drawing.Point(24, 442)) (New-Object Drawing.Size(180, 40)) $true
$form.Controls.Add($script:InstallBtn)
$script:RestoreBtn = New-Btn '一键复原' (New-Object Drawing.Point(216, 442)) (New-Object Drawing.Size(140, 40)) $false
$form.Controls.Add($script:RestoreBtn)
$openBtn = New-Btn '打开插件目录' (New-Object Drawing.Point(368, 442)) (New-Object Drawing.Size(140, 40)) $false
$form.Controls.Add($openBtn)

$script:Progress = New-Object Windows.Forms.ProgressBar
$script:Progress.Location = New-Object Drawing.Point(526, 450); $script:Progress.Size = New-Object Drawing.Size(310, 8)
$script:Progress.Style = 'Marquee'; $script:Progress.MarqueeAnimationSpeed = 24; $script:Progress.Visible = $false
$form.Controls.Add($script:Progress)
$script:Status = New-Object Windows.Forms.Label; $script:Status.Location = New-Object Drawing.Point(526, 464); $script:Status.Size = New-Object Drawing.Size(310, 22); $script:Status.ForeColor = $script:ColMuted; $script:Status.Font = New-UiFont 8.5
$form.Controls.Add($script:Status)

$logLabel = New-Object Windows.Forms.Label; $logLabel.Text = '安装日志'; $logLabel.ForeColor = $script:ColMuted; $logLabel.AutoSize = $true; $logLabel.Location = New-Object Drawing.Point(26, 492)
$form.Controls.Add($logLabel)
$script:LogBox = New-Object Windows.Forms.TextBox
$script:LogBox.Multiline = $true; $script:LogBox.ReadOnly = $true; $script:LogBox.ScrollBars = 'Vertical'
$script:LogBox.BackColor = [Drawing.Color]::FromArgb(17, 19, 24); $script:LogBox.ForeColor = [Drawing.Color]::FromArgb(198, 204, 214)
$script:LogBox.BorderStyle = 'FixedSingle'; $script:LogBox.Font = New-Object Drawing.Font('Consolas', 8.5)
$script:LogBox.Location = New-Object Drawing.Point(24, 514); $script:LogBox.Size = New-Object Drawing.Size(812, 100)
$script:LogBox.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Left -bor [Windows.Forms.AnchorStyles]::Right -bor [Windows.Forms.AnchorStyles]::Bottom
$form.Controls.Add($script:LogBox)

$hint = New-Object Windows.Forms.Label
$hint.Text = '需要目标电脑已安装 LiteLoaderQQNT。安装器只替换插件目录，不修改 QQ 本体；数据目录里的设置会保留。'
$hint.ForeColor = $script:ColMuted; $hint.AutoSize = $false; $hint.Location = New-Object Drawing.Point(24, 612); $hint.Size = New-Object Drawing.Size(812, 18)
$hint.Anchor = [Windows.Forms.AnchorStyles]::Left -bor [Windows.Forms.AnchorStyles]::Right -bor [Windows.Forms.AnchorStyles]::Bottom
$form.Controls.Add($hint)

$browseQq.Add_Click({
    $d = New-Object Windows.Forms.FolderBrowserDialog
    $d.Description = '选择 QQ 安装目录（包含 QQ.exe）'
    if ($d.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        $script:QqBox.Text = $d.SelectedPath
        $p = Find-Profile (Normalize-Dir $script:QqBox.Text)
        if ($p) { $script:ProfileBox.Text = $p }
        Refresh-Info
    }
})
$browseProfile.Add_Click({
    $d = New-Object Windows.Forms.FolderBrowserDialog
    $d.Description = '选择 LiteLoaderQQNT 数据目录（里面应有 plugins 文件夹）'
    if ($d.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        $script:ProfileBox.Text = $d.SelectedPath
        Refresh-Info
    }
})
$detectQq.Add_Click({
    $q = Find-Qq $script:QqBox.Text
    if ($q) { $script:QqBox.Text = $q }
    $p = Find-Profile (Normalize-Dir $script:QqBox.Text)
    if ($p) { $script:ProfileBox.Text = $p }
    Refresh-Info
})
$detectProfile.Add_Click({
    $p = Find-Profile (Normalize-Dir $script:QqBox.Text)
    if ($p) { $script:ProfileBox.Text = $p }
    Refresh-Info
})
$script:InstallBtn.Add_Click({ Install-OneClick })
$script:RestoreBtn.Add_Click({ Restore-OneClick })
$openBtn.Add_Click({
    try {
        $p = Get-PluginDir (Normalize-Dir $script:ProfileBox.Text)
        if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
        Start-Process explorer.exe -ArgumentList ('"' + $p + '"')
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, '提示', 'OK', 'Warning') | Out-Null }
})

$form.Add_Shown({
    if ($QqPath) { $script:QqBox.Text = $QqPath }
    if ($ProfilePath) { $script:ProfileBox.Text = $ProfilePath }
    if (-not $script:QqBox.Text) {
        $q = Find-Qq ''
        if ($q) { $script:QqBox.Text = $q }
    }
    if (-not $script:ProfileBox.Text) {
        $p = Find-Profile (Normalize-Dir $script:QqBox.Text)
        if ($p) { $script:ProfileBox.Text = $p }
    }
    Refresh-Info
    if ($script:AutoRun) {
        $script:CloseQq.Checked = $false
        $script:RestartQq.Checked = $false
        if (-not $InstallLiteLoader) { $script:InstallLL.Checked = $false }
        [System.Windows.Forms.Application]::DoEvents()
        if ($AutoInstall) { Install-OneClick }
        if ($AutoRestore) { Restore-OneClick }
        if ($AutoClose) { $form.Close() }
    }
})

[void]$form.ShowDialog()












