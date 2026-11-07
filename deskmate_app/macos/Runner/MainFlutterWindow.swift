import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // FilDOS unified header style:
    // Window title is hidden, titlebar is transparent, content extends to top edge,
    // and traffic lights (close, minimize, zoom) sit cleanly inside the app's top bar.
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    let toolbar = NSToolbar(identifier: "MainToolbar")
    self.toolbar = toolbar
    if #available(macOS 11.0, *) {
      self.toolbarStyle = .unified
      self.titlebarSeparatorStyle = .none
    }

    // Make the window key and visible immediately so macOS knows
    // the window is ready — this prevents indefinite Dock bouncing.
    self.makeKeyAndOrderFront(nil)
  }
}
