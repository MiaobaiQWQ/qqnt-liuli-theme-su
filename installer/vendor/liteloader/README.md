# LiteLoaderQQNT core (vendor)

- 项目：https://github.com/LiteLoaderQQNT/LiteLoaderQQNT
- 版本：1.4.1
- 许可证：MIT（见 LICENSE）
- 来源：本机已安装的 LiteLoaderQQNT 1.4.1，复制 `package.json`、`LICENSE`、`src/`
- 本安装器会把 core 安装到 `<QQ>\LiteLoaderQQNT`，并自动修复 `src/main/store.js` 的
  `fs.Dirent.path` 兼容问题（QQ 9.9.36 的 Node 不提供该属性）。
