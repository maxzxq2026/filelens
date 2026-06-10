# FileLens 🔍 文件透视镜

macOS 菜单栏文件扫描工具，按安全等级分类显示磁盘文件。

## 功能特性

- 📊 **安全分级** — 文件按 🔴不可动 / 🟠谨慎 / 🟡可清理 / 🟢可整理 四级分类
- 🔍 **快速扫描** — 递归扫描指定目录，自动识别文件类型
- 📁 **类型识别** — 支持系统文件、应用、缓存、文档、图片、视频、音频等 10 种类型
- 🎯 **菜单栏驻留** — 点击图标弹出 Popover，不占 Dock 位
- 🔎 **搜索过滤** — 支持文件名实时搜索
- 🖱️ **右键操作** — 在 Finder 中显示、复制路径

## 构建运行

```bash
cd ~/Desktop/FileLens
swift build
# 运行
.build/debug/FileLens
```

## 系统要求

- macOS 13.0+
- Swift 5.9+

## 项目结构

```
Sources/FileLens/
├── App/
│   ├── FileLensApp.swift          # 应用入口
│   └── StatusBarController.swift  # 状态栏 + Popover 控制
├── Models/
│   ├── FileItem.swift             # 文件信息模型
│   ├── SafetyLevel.swift          # 安全等级枚举
│   └── FileType.swift             # 文件类型枚举
├── Services/
│   └── FileScanService.swift      # 文件扫描服务
├── Views/
│   ├── ContentView.swift          # 主视图
│   ├── ContentViewModel.swift     # 视图模型
│   ├── FileItemRow.swift          # 列表行
│   └── FileDetailView.swift       # 文件详情
└── Resources/
    └── Info.plist
```
