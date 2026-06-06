# Translater — 边写边译

macOS 桌面端「边写边译」工具。在任意 app 输入框中打字，实时翻译，按快捷键直接输出译文。

## 功能

- **实时翻译**：打字时浮动面板同步显示译文
- **IME 支持**：完美兼容五笔、拼音、仓颉等所有输入法
- **全局通用**：微信、飞书、浏览器、备忘录……任何输入框都能用
- **语言设置**：支持 14 种语言，可自由切换源语言/目标语言
- **快捷操作**：
  - `Enter` — 发送原文
  - `Alt+Enter` — 删除原文，粘贴译文
  - `Esc` — 取消翻译
  - `Ctrl+Opt+T` — 全局开关翻译

## 系统要求

- macOS 15.0+
- 需授权「辅助功能」权限（用于监听键盘输入）

## 快速开始

```bash
# 编译
make build

# 运行
make run
```

首次运行会提示授权辅助功能权限，在「系统设置 → 隐私与安全性 → 辅助功能」中启用 Translater 即可。

## 翻译引擎

- **MyMemory**（默认）：免费在线翻译，无需 API Key
- **Apple Translation**（备选）：macOS 本地离线翻译，需预装语言模型

## 项目结构

```
Sources/Translater/
├── main.swift              # 入口
├── AppDelegate.swift       # 菜单栏、权限、生命周期
├── EventTap.swift          # CGEvent 键盘 Hook + AX 文本读取
├── FloatingPanel.swift     # 液态玻璃浮动面板
├── TranslationService.swift # 翻译引擎（MyMemory + Apple）
├── LanguageOption.swift    # 语言定义
└── SettingsWindow.swift    # 语言设置窗口
```

## 许可证

MIT
