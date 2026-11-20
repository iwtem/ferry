# 渡 Ferry

一个原生 **Swift + SwiftUI** 编写的轻量 macOS 大模型翻译工具，不占 Dock 栏，常驻顶部菜单栏。

## 核心功能（V1）

1. **菜单栏常驻快译（无 Dock 图标）**
   - 左键点击顶部菜单栏图标，在菜单栏下方弹出紧凑输入框（类有道词典交互）。
   - 输入文本按 `Enter` 立即流式翻译（`Shift + Enter` 换行），支持一键复制、反向翻译。
   - 右键菜单栏图标可快速切换大窗口、桌面悬浮小窗、设置或退出。

2. **独立大窗口**
   - 左右双栏布局，适合长段落翻译（`⌘ + Enter` 翻译），支持一键「粘贴并翻译」、切换模型服务商和查看最近翻译记录。

3. **桌面悬浮迷你小窗**
   - 可随时打开贴合桌面的毛玻璃小窗，支持自由拖动（自动记住位置）、切换「置顶 / 贴近桌面」以及直接打字翻译。

4. **双击 `⌘ + C` 类 DeepL 悬浮翻译**
   - 在任意应用中选中文字后，快速连按两次 `⌘ + C`，会在鼠标附近弹出悬浮翻译卡片并自动流式翻译。
   - 点击外部自动隐藏（点击图钉可固定在屏幕上），按 `Esc` 立即关闭。

5. **内置大模型支持（OpenAI 兼容流式接口）**
   - **DeepSeek**：默认接入 `https://api.deepseek.com/v1`（`deepseek-chat` / `deepseek-reasoner`）。
   - **阿里百炼 (DashScope)**：默认接入 `https://dashscope.aliyuncs.com/compatible-mode/v1`（`qwen-plus` / `qwen-turbo` / `qwen-max` / `qwen-long`）。
   - **自定义 OpenAI 兼容**：可接入 OpenAI、OpenRouter、本地 Ollama (`http://localhost:11434/v1`) 等。
   - 自动检测 **中 ↔ 英互译**（中文自动翻英文，其他语言自动翻中文），也支持手动选择目标语言。

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

## 后续扩展：macOS 原生桌面小组件（WidgetKit）

本项目的核心模型、设置与最近翻译记录已独立封装在 `Sources/FerryCore/` 中。待电脑安装 Xcode 后，可直接新建一个 Xcode App 工程引入 `FerryCore` 并添加 **Widget Extension (WidgetKit)** 目标，通过 App Group 共享 `recent_translations.json` 即可在 macOS 桌面上展示最近翻译卡片与快捷入口。
