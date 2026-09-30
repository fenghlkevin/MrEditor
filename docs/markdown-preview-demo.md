---
title: MrEditor Markdown 增强预览
renderer: MrEditor
mode: 离线
---

# Markdown 增强预览

打开这份文件，可以同时编辑源码和查看预览。右上角的目录按钮可以跳转到各节。

## 代码高亮

```swift
struct Document {
    let title: String
    func preview() -> String { "Hello, \(title)" }
}
```

## 数学公式

行内公式：$E=mc^2$。块级公式：

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

## Mermaid 图表

```mermaid
flowchart LR
    A[Markdown 源码] --> B[解析与清洗]
    B --> C[离线预览]
    C --> D[目录导航]
    C --> E[代码与公式]
```

## 表格、任务和提示

| 功能 | 状态 |
| --- | --- |
| 代码高亮 | 已接入 |
| KaTeX / Mermaid | 已接入 |
| 目录与脚注 | 已接入 |

- [x] 保留原生编辑器
- [x] 支持双向滚动同步
- [x] 离线加载脚本与字体

> [!NOTE]
> 这是 GitHub 风格的提示块。预览会过滤可执行 HTML，并限制外部资源。

## 扩展语法

==重点标记==、~~删除线~~、H~2~O、x^2^ 和表情 :smile:。

这段文字带有脚注[^example]。

[^example]: 脚注可以点击跳转，也可以返回正文。
