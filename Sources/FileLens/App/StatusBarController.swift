import SwiftUI
import AppKit

/// 状态栏控制器：管理 NSStatusItem + NSPopover
class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var eventMonitor: Any?

    override init() {
        super.init()
        // 配置 Popover
        popover.contentSize = NSSize(width: 480, height: 600)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MainView()
        )

        // 创建状态栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "FileLens")
                ?? NSImage(named: NSImage.Name("NSTouchBarSearchTemplate"))
            button.image = image
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
        }

        // 点击外部关闭 Popover
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem?.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // 激活应用以接收键盘事件
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
