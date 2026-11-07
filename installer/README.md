# 琉璃主题 + LiteLoaderQQNT 一键安装器

一个 Windows 单文件安装器：用户只需选择 QQ 安装目录，即可一键：

- 安装/更新 **LiteLoaderQQNT 1.4.1**（core、QQ 启动入口、`QQNT.dll` 校验补丁、`store.js` 兼容修复）
- 安装/替换 **琉璃主题** 到 LiteLoader 的 `plugins/liuli-dsh-theme`
- 自动备份旧插件、QQ `package.json`、`QQNT.dll`、`LiteLoader.js`、core
- **一键复原**：回滚插件 + LiteLoader/QQ 文件到安装前状态

## 使用

1. 关闭 QQ（安装器也会提示自动关闭）
2. 右键 `琉璃主题安装器.exe` → **以管理员身份运行**（安装 LiteLoader 需要写 QQ 目录）
3. 选择/自动检测 QQ 目录（如 `C:\Program Files\Tencent\QQNT`）
4. 勾选「自动安装 LiteLoaderQQNT」，点 **一键替换 / 安装**
5. 想撤销时点 **一键复原**

## 限制与风险

- 只支持 **Windows QQ 9.9.36**（LiteLoaderQQNT 1.4.1）。其它版本不做保证。
- 安装 LiteLoader 会修改 `QQNT.dll` 绕过 QQ 文件校验，可能触发腾讯风控；安装器会先把原文件备份到 `<QQ>\liuli-backups\`，可用「一键复原」恢复。
- 目标电脑需要能运行 Windows PowerShell 5.1（Windows 10/11 自带）。
- 安装器不联网，插件与 LiteLoader core 都内嵌在 exe 中。

## 构建

需要 PowerShell 5.1+、[PS2EXE](https://github.com/MScholtes/PS2EXE) 模块。

```powershell
# 生成 payload.zip / lite-loader.zip
powershell -ExecutionPolicy Bypass -File installer\build-payload.ps1

# 编译单文件 exe（默认 requireAdministrator）
powershell -ExecutionPolicy Bypass -File installer\ps\make-ps2exe.ps1
```

产物：`installer\dist\琉璃主题安装器.exe`。

## 目录

```
installer/
  build-payload.ps1          生成插件 payload + LiteLoader core zip
  ps/install.ps1             安装器主界面与插件备份/还原
  ps/liteloader.ps1          LiteLoader/QQ 补丁安装与复原
  ps/make-ps2exe.ps1         合并脚本、编译单文件 exe
  ps/compile-ps2exe.ps1      PS2EXE 编译入口
  vendor/liteloader/         LiteLoaderQQNT 1.4.1 core（MIT）
```

LiteLoaderQQNT 版权归 LiteLoaderQQNT 项目所有，许可证见 `vendor/liteloader/LICENSE`。
