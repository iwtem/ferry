# 渡 Ferry

一个原生 **Swift + SwiftUI** 编写的轻量 macOS 大模型翻译工具，不占 Dock 栏，常驻顶部菜单栏。

## 核心功能（V1）

1. **菜单栏常驻快译（无 Dock 图标）**
   - 左键点击顶部菜单栏图标，或随时按下全局快捷键 `⌥ + Space`（可在设置中自定义），在菜单栏下方一键呼出或收起紧凑输入框并自动聚焦。
   - 输入文本按 `Enter` 立即流式翻译（`Shift + Enter` 换行），支持一键复制、反向翻译。
   - 右键菜单栏图标可快速切换大窗口、桌面悬浮小窗、设置或退出。

2. **独立大窗口**
   - 左右双栏布局，适合长段落翻译（`⌘ + Enter` 翻译），支持全局快捷键 `⌥ + ⇧ + F` 一键呼出或隐藏、一键「粘贴并翻译」、切换模型服务商和查看最近翻译记录。

3. **桌面悬浮迷你小窗**
   - 可随时打开贴合桌面的毛玻璃小窗，支持自由拖动（自动记住位置）、切换「置顶 / 贴近桌面」以及直接打字翻译。

4. **双击 `⌘ + C` 类 DeepL 悬浮翻译**
   - 在任意应用中选中文字后，快速连按两次 `⌘ + C`，会在鼠标附近弹出悬浮翻译卡片并自动流式翻译。
   - 点击外部自动隐藏（点击图钉可固定在屏幕上），按 `Esc` 立即关闭。

5. **截图 OCR 翻译（macOS 原生 Vision 离线识别）**
   - 默认按下全局快捷键 `⌥ + ⇧ + S`（可在设置中自定义），或在菜单栏弹窗 / 右键菜单 / 大窗口点击「截图翻译」，拉框截取任意屏幕区域（PDF 扫描件、图片、报错弹窗、视频字幕等）。
   - 使用 macOS 原生 `Vision` 本地离线识别多语种文字并自动整理换行，识别后直接在鼠标附近流式弹出译文；在大窗口点击「粘贴并翻译」也支持直接识别剪贴板里的截图。

6. **翻译 / 写作润色模式切换 & 一键替换回原输入框**
   - 内置 5 种场景预设：**标准翻译**、**地道润色**、**语法纠错**、**职场简洁**、**学术表达**，菜单栏弹窗、大窗口、桌面小窗、悬浮卡片均可一键切换。
   - 在任意 App 输入框选中文字，双击 `⌘C` 或按全局快捷键 `⌥ + ⇧ + R`（不污染原剪贴板）即可预览翻译/润色结果，点击「替换原文」或按 `⌘ + Enter` 直接写回原输入框并自动还原剪贴板。

7. **内置大模型支持、单次切模型重译 & 双模型对比**
   - **DeepSeek**：默认接入 `https://api.deepseek.com/v1`（`deepseek-chat` / `deepseek-reasoner`）。
   - **阿里百炼 (DashScope)**：默认接入 `https://dashscope.aliyuncs.com/compatible-mode/v1`（`qwen-plus` / `qwen-turbo` / `qwen-max` / `qwen-long`）。
   - **自定义 OpenAI 兼容**：可接入 OpenAI、OpenRouter、本地 Ollama (`http://localhost:11434/v1`) 等。
   - 自动检测 **中 ↔ 英互译**（中文自动翻英文，其他语言自动翻中文），也支持手动选择目标语言。
   - **单次快速切模型重译 & 双模型对比**：日常用快模型秒译，遇到难句可在结果卡片一键用强模型重译（不改动默认配置），或直接展开双模型并排流式对比并一键「采用」。

8. **保留文档结构与格式翻译、本地 LRU 缓存 & PDF 断行修复**
   - **保留文档结构与格式**：双击 `⌘C`、划词 `⌥⇧R` 或直接粘贴来自网页、飞书、Notion、Word、备忘录的富文本时，自动保留标题、加粗/斜体、列表、链接、引用、代码块与表格结构；译文自动渲染排版并支持 `</>` 一键切换 Markdown 源码；复制或「替换原文」时自动按来源写回富文本（HTML + RTF）或 Markdown（复制按钮右键可自选格式）。
   - **本地持久化 LRU 缓存**（默认上限 500 条）：重复查询相同词句秒出结果、零额外 Token 消耗，结果卡片标注「⚡ 已缓存」并支持一键跳过缓存重新翻译。
   - **PDF / 论文断行修复**：自动合并复制带来的多余硬回车与 `algo-\nrithm` 连字符断词，保留分段、列表与代码块。

## 本地编译与打包 `.app`

无需安装 Xcode，仅用 macOS 自带的 Swift Command Line Tools 即可一键编译并打包出可直接双击运行的 `Ferry.app`：

```bash
./Scripts/build_app.sh
```

打包完成后，成品位于：

```text
dist/Ferry.app
```

可直接双击运行，或拖入 `/Applications`（应用程序）文件夹使用。

### 本机一键更新重启（开发调试用）

修改代码后，一条命令自动编译签名、退出旧版、替换 `/Applications/Ferry.app` 并重新打开：

```bash
./Scripts/deploy_local.sh
```

### 发布新版本（支持应用内自动下载与一键更新）

Ferry 内置了基于 **GitHub Releases** 的原生自动更新（启动与后台定时检测、自动静默下载并校验 SHA-256、点击「重启更新」自动替换并重新打开新版）。

发版时只需运行：

```bash
# 仅打包生成 dist/Ferry-<version>.zip 与 .sha256
./Scripts/release.sh 0.2.0

# 打包并直接通过 GitHub CLI (gh) 发布到 GitHub Releases
./Scripts/release.sh 0.2.0 --publish --notes "新增截图 OCR 翻译与应用内自动更新"
```

> 使用同一套 `.signing/` 证书签名发布的版本，在应用内自动更新重启后，**辅助功能**与**屏幕录制**权限会自动保留，无需重新勾选。

### 运行核心单元测试

```bash
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

## 开启双击 `⌘ + C` 权限说明

macOS 需要授予 **辅助功能（Accessibility）** 权限，软件才能在其他应用中监听双击 `⌘ + C`：

1. 打开「渡 Ferry 设置 → 双击 ⌘C 与权限」。
2. 点击「打开系统设置 → 辅助功能」。
3. 将 `Ferry.app` 勾选开启（如已拖入 `/Applications`，请选择应用程序目录中的版本）。
4. 回到设置页点击「重新检测」，显示绿色已授权即可使用。

## 产品规划

更多后续功能规划与迭代进度见 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 后续扩展：macOS 原生桌面小组件（WidgetKit）

本项目的核心模型、设置与最近翻译记录已独立封装在 `Sources/FerryCore/` 中。待电脑安装 Xcode 后，可直接新建一个 Xcode App 工程引入 `FerryCore` 并添加 **Widget Extension (WidgetKit)** 目标，通过 App Group 共享 `recent_translations.json` 即可在 macOS 桌面上展示最近翻译卡片与快捷入口。
