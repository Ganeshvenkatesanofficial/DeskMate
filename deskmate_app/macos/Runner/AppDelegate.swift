import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Tell the macOS window server the app has finished launching.
    // This stops the Dock icon from bouncing indefinitely.
    super.applicationDidFinishLaunching(notification)

    // Bring app window to front and make it active immediately.
    NSApp.activate(ignoringOtherApps: true)

    // Cancel any pending Dock icon attention request.
    NSApp.requestUserAttention(.informationalRequest)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
