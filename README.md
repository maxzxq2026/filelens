# FileLens 🔍 文件透视镜

> macOS 菜单栏文件扫描工具 — 一眼看清磁盘里哪些能删、哪些别动

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0+-blue?logo=apple" />
  <img src="https://img.shields.io/badge/Swift-5.9+-orange?logo=swift" />
  <img src="https://img.shields.io/badge/License-MIT-green" />
  <img src="https://img.shields.io/badge/Size-1.4MB-lightgrey" />
</p>

---

## ✨ 为什么需要它？

你的 Mac 用了几年，Downloads 堆了几千个文件，Desktop 乱成一团。哪些是系统文件不能删？哪些是缓存可以清？哪些是你自己的文件可以整理？

**FileLens 帮你一秒看清。**

## 🎯 核心功能

| 功能 | 说明 |
|------|------|
| 🔒 四级安全分类 | 🔴 不可动 → 🟠 谨慎 → 🟡 可清理 → 🟢 可整理 |
| 📂 9 种文件类型 | 文档、图片、视频、音频、代码、压缩包、安装包、未知文件 |
| 🎯 菜单栏驻留 | 不占 Dock 位，点图标即用，点外面即关 |
| 🔎 实时搜索 | 文件名、路径、扩展名全局搜索 |
| 🗑 悬停删除 | 鼠标移到文件行，一键移到废纸篓 |
| 📁 快速定位 | 点击文件夹名直接在 Finder 打开 |
| ⚡ 一键整理 | 自动把桌面文件按类型归类到子文件夹 |
| ↩️ 可撤销 | 整理后悔了？一键撤销所有操作 |
| 👁 文件监控 | 实时监控 Downloads 和 Desktop 变化 |
| 📏 自定义规则 | 导入 JSON 规则文件，自定义分类和识别逻辑 |

## 📸 界面预览

```
┌─────────────────────────────────────┐
│  🔍 FileLens 文件透视镜       ⋯ [扫描] │
│─────────────────────────────────────│
│  [搜索文件...]                        │
│─────────────────────────────────────│
│  🔒23  ⚠️45  🧹128  ✅512            │
│─────────────────────────────────────│
│  [全部][文档][图片][视频]              │
│  [代码][压缩包][安装包][未知文件]       │
│─────────────────────────────────────│
│  📄 report.pdf     📁 Documents      │
│     🟢 可整理 · 2.3MB            🗑 ❯│
│  📦 backup.zip     📁 Downloads      │
│     🟡 可清理 · 156MB           🗑 ❯│
│  ⚙️ kernel.sys     📁 System         │
│     🔴 不可动 · 8.1MB                │
│─────────────────────────────────────│
│  688 个文件 · 1.2s          ⚡ 实时监控 │
└─────────────────────────────────────┘
```

## 🚀 安装

### 方式一：直接下载

1. 下载 [FileLens.app](https://github.com/maxzxq2026/filelens/releases)
2. 拖到 `/Applications` 文件夹
3. 打开即可使用

### 方式二：源码编译

```bash
git clone https://github.com/maxzxq2026/filelens.git
cd filelens
swift build -c release
cp -R FileLens.app /Applications/
open /Applications/FileLens.app
```

## 🛠 技术栈

- **语言**：Swift 5.9+
- **框架**：SwiftUI + AppKit
- **构建**：Swift Package Manager（零依赖）
- **架构**：MVVM
- **适配**：macOS 13.0+，自动适配暗色模式

## 📁 项目结构

```
Sources/FileLens/
├── App/                    # 应用入口
│   ├── FileLensApp.swift
│   └── StatusBarController.swift
├── Models/                 # 数据模型
│   ├── FileItem.swift
│   ├── FileType.swift
│   ├── SafetyLevel.swift
│   └── ...
├── Services/               # 核心服务
│   ├── FileScanService.swift      # 递归扫描
│   ├── FileIdentifier.swift       # 类型识别
│   ├── SafetyClassifier.swift     # 安全分类
│   └── FileOrganizer.swift        # 一键整理
├── Views/                  # UI 视图
│   ├── MainView.swift
│   ├── FileListItem.swift
│   ├── FilterBar.swift
│   └── ...
└── Resources/              # 规则配置
    ├── classification_rules.json
    └── identification_rules.json
```

## 📋 安全等级说明

| 等级 | 图标 | 含义 | 示例 |
|------|------|------|------|
| 🔴 不可动 | `lock.fill` | 系统核心文件，删除会导致系统异常 | `.dylib`, `.kext`, 系统 plist |
| 🟠 谨慎 | `exclamationmark.triangle.fill` | 应用运行依赖，删除可能影响 App | `.framework`, `.bundle`, 缓存 |
| 🟡 可清理 | `trash.fill` | 临时文件，可以安全删除 | `.log`, `.tmp`, `.cache` |
| 🟢 可整理 | `checkmark.circle.fill` | 用户文件，建议整理归类 | 文档、图片、视频、音频 |

## ⚙️ 自定义规则

支持导入 JSON 规则文件自定义分类和识别逻辑：

```json
{
  "rules": [
    {
      "pattern": "*.log",
      "safety": "cleanable",
      "description": "日志文件"
    }
  ]
}
```

通过菜单栏 ⋯ → 导入规则 加载。

## 📄 License

MIT License

---

<p align="center">
  如果觉得有用，点个 ⭐ 支持一下！
</p>
