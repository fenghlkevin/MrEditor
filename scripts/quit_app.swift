import AppKit
import Foundation
let apps = NSWorkspace.shared.runningApplications.filter {
    ["/Applications/MrEditor.app", "/Applications/TextStack.app"].contains($0.bundleURL?.path ?? "")
}
for app in apps { app.terminate() }
let deadline = Date().addingTimeInterval(30)
while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
}
if apps.contains(where: { !$0.isTerminated }) {
    fputs("Application is still running; resolve the unsaved document prompt before installation.\n", stderr)
    exit(1)
}
