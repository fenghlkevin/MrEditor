# MrEditor

**简体中文** | [English](README.en.md) | [日本語（历史版本）](README.ja.md)

**面向日志、结构化数据和 Markdown 的 macOS 原生编辑器。**

打开大文件、筛选日志、检查 JSON 和表格、对比文本，也能一边编辑 Markdown，一边查看公式和流程图。MrEditor 将本地文件与 SSH 远程日志放在同一个工作区，提供简体中文、英文和日文界面。

## 截图与演示

![日志、CSV、JSON 和差异比较四种工作场景](docs/img/four-kinds-of-text.jpg)

*工作场景概览：日志阅读、CSV 列对齐、JSON 格式化和逐字符差异比较。此图为项目已有版本截图，当前界面以实际构建为准。*

[![打开 10 GB 日志的实时操作动图，点击查看完整视频](docs/img/10gb-open.gif)](docs/media/mreditor-10gb.mp4)

**[▶ 播放或下载完整演示视频（MP4，约 27 秒）](docs/media/mreditor-10gb.mp4)** · 打开 10 GB 日志、滚动阅读并跳转到末行。动图展示前 10 秒；素材来自原项目 1.14.0，非本次构建的性能测试。

## 最近更新

- **多格式分栏预览**：Markdown、JSON、YAML、CSV、TSV、代码、日志、Mermaid、HTML 和 SVG；支持预览内搜索。
- **Markdown 增强**：代码高亮、KaTeX 公式、Mermaid 图表、可点击目录、表格、任务列表、脚注、GitHub Alerts 和 YAML frontmatter。
- **Finder 快速查看**：内置 Quick Look 扩展，提供源码/预览切换、搜索、缩放、主题与重新加载。
- **数据检查器**：JSON 树和格式化副本、CSV/TSV 原生表格、NDJSON 记录浏览与导出。
- **编辑与搜索**：多光标、矩形列选择、查找全部和可勾选的替换预览。
- **远程工作区**：独立 SSH 连接管理、远程目录选择、跳板机、Keychain 凭据存储，以及本地/服务器侧边栏分区。
- **中文体验**：简体中文界面、语言匹配改进，以及更清晰的空白页操作入口。

## 功能

### Markdown 与多格式预览

![Markdown 预览：代码高亮、公式、Mermaid、提示块与表格](docs/img/markdown-preview.png)

*当前渲染器的真实 WebKit 测试截图（2026-09-30），展示预览内容区域。*

从工具栏的**显示方式 → 预览**打开分栏视图；Markdown 文件可自动显示实时预览。源码与预览按滚动比例双向同步，支持浅色和深色外观。渲染器、字体和样式随应用打包，普通预览无需联网。

| 格式 | 预览能力 |
| --- | --- |
| Markdown | CommonMark/GFM、代码高亮、公式、流程图、目录、任务列表与脚注 |
| JSON / YAML | 可折叠树、全部展开/折叠、解析错误提示、源码切换 |
| CSV / TSV | 表头固定、列宽调整、点击排序、文本过滤，支持带引号与多行字段 |
| 代码 / 配置 / 日志 | 已注册语言高亮、行号、换行、搜索、ERROR/FATAL/WARN 着色 |
| Mermaid | 直接渲染 `.mmd` / `.mermaid` 图表 |
| HTML / SVG | 清理后的文档结构与矢量图预览 |

HTML/SVG 预览会移除脚本、样式与外部资源，不能代替浏览器还原完整网页。远程图片被阻止，本地图片访问限定在文档目录。编辑器分栏预览面向不超过 **8 MiB** 的文件；更大文件继续使用大文件编辑器。表格与文本预览还有行数、列数和字符数限制，达到上限会显示提示；预览搜索只针对已渲染内容，最多高亮 2,000 处。

用 [Markdown 示例](docs/markdown-preview-demo.md) 和 [多格式示例](docs/preview-samples/) 体验；完整范围见 [预览说明](docs/markdown-preview.md)。

### Finder 快速查看

安装并启动应用后，在系统设置的 **通用 → 登录项与扩展 → 扩展 → 快速查看** 中启用 MrEditor（名称随 macOS 版本可能不同），选中文件后按空格。

扩展支持重新加载、50%–250% 缩放、源码/预览切换和系统/浅色/深色主题。齿轮菜单可设置“双击预览打开文件”，默认关闭。

Finder 决定最终使用哪个预览提供程序：已有测试中 Markdown、JSON、日志使用 MrEditor，而 CSV、SVG 仍可能由系统接管。这些格式在应用内可正常使用新预览。Quick Look 最多读取 **4 MiB**，超限有截断提示；支持 UTF-8 和带 BOM 的 UTF-16，本地图片还受宿主沙箱限制。

### JSON、CSV、TSV 与 NDJSON 检查器

从**显示方式**选择对应数据视图，在源码旁查看结构。此原生检查器与通用 Web 预览是不同入口。

- **JSON**：后台解析、折叠树、每页 500 个子节点；选择节点可定位源码。格式化生成新文档，保留键顺序、重复键和数字原始写法。大 UTF-8 文件采用内存映射与流式格式化，解析前需先保存大文件的待提交修改。
- **CSV / TSV**：首行作为表头开关、调整与重排列、记录过滤和单元格详情；支持引号内分隔符、转义引号和多行字段，列按每组 100 列分页。
- **NDJSON**：按记录浏览 JSON 树；“格式化全部”将记录导出为新的 JSON 数组文件。错误记录会提示序号，导出遇错停止并清理部分输出。

### 大文件与日志

使用 `mmap`、稀疏行索引和仅绘制可见行的视图读取大文件；大文件编辑通过 piece table 保存修改，不需要将全文加载进文本控件。项目已有 10 GB 日志演示，实际速度取决于硬件、文件内容及操作。

- 全文件后台搜索、大小写开关、正则表达式、多词 AND 查询。
- **实时 grep**：只显示匹配行，保留真实行号，并用 `±` 添加上下文。
- **跟随末尾**：增量追踪追加内容；本地文件有未保存修改时暂停，保存后恢复。
- UTF-8、Shift-JIS、EUC-JP 编码检测与保存转换；原子保存、另存为和恢复已保存版本。
- 书签、跳转行、ANSI 日志颜色、自动换行、字体与主题设置。
- gzip/zip 自动识别与展开；命令行标准输入在读取完毕后打开。

![大文件搜索与匹配高亮](docs/img/search-10gb-dark.png)

*已有版本的大文件搜索截图。筛选视图为只读，保存仍写入完整文档。*

### 多光标、列模式与替换预览

在小文件编辑窗格中，使用 `⌘` 点击或 `⌥⌘↑ / ↓` 添加光标，`⌘D` 选择下一个相同文本。通过 **编辑 → 列模式**（`⇧⌥⌘C`）拖出矩形选区，同时编辑多行；短行停在行尾，`Esc` 退出列模式。

搜索栏支持使用选区搜索、查找全部、替换和全部替换。**预览修改**最多列出 500 项，可勾选要应用的替换；文档变化后需重新生成预览。格式化或只读视图中的替换能力受限。

### SSH 远程日志

通过 **文件 → 打开远程…**（`⌃⌘O`）、首页入口或服务器侧边栏连接。

- 快速连接或保存配置；支持密码、私钥、加密私钥、SSH Agent 和独立认证的跳板机。
- 远程目录浏览、文件名过滤、按修改时间排序、刷新与复用连接选择其他文件。
- 按需读取日志片段，在服务器端过滤，并通过 `tail -f` 跟随追加内容。
- 凭据仅在选择记住时存入 macOS Keychain；首次连接确认真实主机指纹，主机密钥变化时拒绝连接。
- 新连接使用应用生成的 SSH 配置，不依赖 `~/.ssh/config`。

远程窗格用于读取、过滤、复制与跟随日志，不提供本地编辑器的全部功能；所需远程命令缺失时会提示能力限制。详见 [SSH 连接说明](docs/SSH_CONNECTIONS.md)。

### 比较与合并

比较两个文件、已打开文档、剪贴板或 HTTPS URL 内容，显示并排的行级与字符级差异。可将左侧差异采纳到右侧结果，再单独保存合并文件；两个原文件不受影响。格式比较用于检查数据形状，开启时禁用合并。

![并排差异比较](docs/img/diff_vew.png)

*已有版本的差异比较截图。*

### 工作区与外观

侧边栏切换多文档、关闭文件、区分本地与服务器；恢复会话和未保存的新建草稿。支持 Finder“打开方式”、默认应用设置、打印与 PDF 输出，以及等宽字体、行距、插入符、主题和背景透明度调整。

## 常用快捷键

| 操作 | 快捷键 |
| --- | --- |
| 新建 / 打开 / 保存 | `⌘N` / `⌘O` / `⌘S` |
| 另存为 | `⇧⌘S` |
| 搜索 / 下一处 / 上一处 | `⌘F` / `⌘G` / `⇧⌘G` |
| 跳转行 / 切换书签 | `⌘L` / `⌘B` |
| 跟随文件末尾 | `⌥⌘F` |
| 打开远程文件 | `⌃⌘O` |
| 比较两个文件 | `⇧⌘D` |
| 上一处 / 下一处差异 | `⇧⌘[` / `⇧⌘]` |
| 列模式 | `⇧⌥⌘C` |
| 添加上方 / 下方光标 | `⌥⌘↑` / `⌥⌘↓` |
| 选择下一个相同文本 | `⌘D` |

## 构建与运行

需要 **macOS 13+**、Swift 5.9 或更新工具链（Xcode 15+），以及打包脚本使用的 Python 3。当前分支包含新增预览等功能，上游发布包不一定包含这些修改；体验本分支请从源码构建。

```sh
swift build -c release
sh scripts/make_app.sh release
codesign --verify --deep --strict .build/MrEditor.app
open .build/MrEditor.app
```

打包脚本会嵌入本地化资源与 Quick Look 扩展、校验预览资源清单并签名。默认是 ad-hoc 本地签名；这不代表 Developer ID 签名或 Apple 公证。

安装到 `/Applications/MrEditor.app` 前，正常退出应用并处理未保存文档，将旧应用备份到 `.build/backups/` 下独立目录，再替换并启动新包。

渲染资源已提交到仓库，普通 Swift 构建不需要 Node.js；修改 `web-renderer/` 时需先在具备 Node.js/npm 的环境重建：

```sh
sh scripts/build_markdown_renderer.sh
swift test --filter 'Markdown(PreviewIntegration|Renderer|Syntax)Tests|EditableViewerMarkdownHighlightTests'
```

安装可选命令行入口后，可打开文件或传入完整管道输出：

```sh
sh scripts/install-cli.sh
mreditor /path/to/app.log
cat /path/to/app.log | mreditor
```

## 文档与贡献

- [预览功能、限制与验证](docs/markdown-preview.md)
- [SSH 连接与集成测试](docs/SSH_CONNECTIONS.md)
- [初始大文件架构设计](docs/ARCHITECTURE_v0.1.md)
- [贡献指南](CONTRIBUTING.md)

## 许可与致谢

原始 MrEditor 代码采用 [MIT](LICENSE)，© 2026 TABATA Hitoshi。

本分支的增强预览包含 FluxMarkdown 衍生的 [GPL-3.0 组件](web-renderer/LICENSE)，© 2024–2026 xykong，因此不能将组合构建描述为仅使用 MIT 许可。来源、固定版本与改动见 [UPSTREAM.md](web-renderer/UPSTREAM.md)；依赖声明随预览资源中的 `ThirdPartyNotices.txt` 一起打包。
