# TextStack 展示官网

独立静态前端，参考 Vibe Island 的深色产品展示节奏，使用 TextStack 自有品牌与文案。没有应用安装包、支付链接、账户系统或数据采集。

## 本地预览与构建

```sh
cd website
npm run dev
# 打开 http://127.0.0.1:4173
npm run build
```

无构建依赖，Node.js 20+ 即可。构建会校验静态资源并检查没有安装包或支付链接，只复制明确列出的公开文件到 `dist/`；不会上传仓库、应用源码或开发文档。

## Cloudflare Pages 免费部署

注册 Cloudflare 并登录后，在 **Workers & Pages → Create application → Pages → Upload assets** 创建 `textstack` 项目。上传 `dist/` 里的文件（不是整个仓库），部署完成后使用 Cloudflare 提供的实际 `pages.dev` 地址。项目名可能已被占用，以平台返回的名称和网址为准。

也可以通过官方 Wrangler CLI：

```sh
npx wrangler login
npm run build
npx wrangler pages project create textstack --production-branch main
npm run deploy
```

创建新项目之前先确认名称未被占用且账号下没有需要保留的同名网站。正式部署前先完成账号授权，不能把本地预览地址当作公网地址。

Git 自动部署时，设置项目根目录 `website`，构建命令 `npm run build`，输出目录 `dist`。

页面文件：`index.html`、`styles.css`、`app.js`。演示区为产品能力的界面示意，明确标注“界面示意”；第二个内容区使用已有 Markdown 渲染器真实测试截图。产品图标来自项目 `art/TextStack.png`，功能与系统要求来自本项目当前 README 和 Package.swift。不包含未经验证的性能数字。
