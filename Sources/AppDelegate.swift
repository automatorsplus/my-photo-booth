import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var booth: BoothController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        booth = BoothController()
        window = NSWindow(contentViewController: booth)
        window.title = "MyPhotoBooth"
        window.setContentSize(NSSize(width: 1000, height: 680))
        window.contentMinSize = NSSize(width: 640, height: 460)
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.mainMenu = makeMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        booth?.shutdown()
    }

    @objc private func toggleUnmirror(_ sender: NSMenuItem) {
        let on = !UserDefaults.standard.bool(forKey: BoothController.unmirrorKey)
        UserDefaults.standard.set(on, forKey: BoothController.unmirrorKey)
        sender.state = on ? .on : .off
    }

    @objc private func showPhotos() {
        if let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(pictures)
        }
    }

    private func makeMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About MyPhotoBooth", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide MyPhotoBooth", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit MyPhotoBooth", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "MyPhotoBooth")

        let camera = NSMenu(title: "Camera")
        camera.addItem(item("Take Photo", #selector(BoothController.takePhoto), "t", target: booth))
        camera.addItem(item("Show Effects", #selector(BoothController.toggleGrid), "e", target: booth))
        camera.addItem(item("Previous Effects Page", #selector(BoothController.previousPage), "[", target: booth))
        camera.addItem(item("Next Effects Page", #selector(BoothController.nextPage), "]", target: booth))
        camera.addItem(.separator())
        let unmirror = item("Save Photos Unmirrored", #selector(toggleUnmirror(_:)), "", target: self)
        unmirror.state = UserDefaults.standard.bool(forKey: BoothController.unmirrorKey) ? .on : .off
        camera.addItem(unmirror)
        camera.addItem(item("Show Photos in Finder", #selector(showPhotos), "", target: self))
        main.addItem(submenu: camera, title: "Camera")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu
        return main
    }

    private func item(_ title: String, _ action: Selector, _ key: String, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        submenu.title = title
        item.submenu = submenu
        addItem(item)
    }
}
