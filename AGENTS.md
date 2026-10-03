# 本地开发交付

用户要求：本项目每次修改完成后，都必须构建、替换安装并启动 TextStack。

- 构建 release，使用 `scripts/make_app.sh release` 打包，检查签名和资源完整性。
- 替换 `/Applications/TextStack.app` 前，将已有安装备份到项目 `.build/backups/` 下独立目录。
- 正常退出运行中的应用，保留未保存文档的确认流程；不能强制终止而丢失内容。
- 安装新包、启动 `/Applications/TextStack.app`，确认进程来自该路径。
- 沙箱限制写入 Applications 或控制应用时，使用权限升级执行已获用户授权的安装操作。
- 汇报构建、安装和启动结果；不要把“仅修改源码”当作交付完成。

- 产品名和安装包名统一为 TextStack；首次迁移时备份并移除旧的 `/Applications/MrEditor.app`，避免重复安装。
- 使用 `sh scripts/install_app.sh` 安装并验证启动。
