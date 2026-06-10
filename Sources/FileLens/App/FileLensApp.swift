import SwiftUI

/// FileLens 应用入口
/// 菜单栏文件透视镜 — 扫描磁盘文件，按安全等级分类显示
@main
struct FileLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 菜单栏应用不需要常规窗口
        Settings {
            EmptyView()
        }
    }
}

/// AppDelegate：负责启动状态栏控制器
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[FileLens] 应用启动中...")
        // 隐藏 Dock 图标（替代 Info.plist 中的 LSUIElement）
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
        print("[FileLens] 状态栏控制器已创建")
    }
}
