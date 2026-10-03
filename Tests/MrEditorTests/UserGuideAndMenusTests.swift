import AppKit
import WebKit
import XCTest
@testable import MrEditorCore

@MainActor
final class UserGuideAndMenusTests: XCTestCase {
    func testFeatureEntriesAndShortcutsAreDiscoverable() throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        delegate.buildMenu()
        func items(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { item in [item] + (item.submenu.map(items) ?? []) } }
        let all = items(try XCTUnwrap(NSApp.mainMenu))
        for selector in ["folderSearch:", "logAnalysis:", "characterInspector:", "markdownExport:", "filterTimeRange:", "cleanCSV:", "showPreview:", "previewOnly:", "toggleLineWrap:", "showJSONInspector:", "formatJSON:", "showFilter:", "toggleSidebar:", "remoteReconnect:", "remoteCompanion:", "remoteAnalyze:", "remoteFollow:", "remoteAutoReconnect:", "exportSettings:", "importSettings:", "copySettingsLink:", "importSettingsLink:", "openHelp:"] {
            let item = try XCTUnwrap(all.first { $0.action == NSSelectorFromString(selector) }, "Missing entry: \(selector)")
            XCTAssertTrue((item.target as? NSObject)?.responds(to: NSSelectorFromString(selector)) == true)
        }
        let guideHTML = try String(contentsOf: XCTUnwrap(UserGuideWindowController.guideURL))
        for item in all where item.action != nil && item.submenu == nil {
            let command = NSStringFromSelector(item.action!)
            XCTAssertTrue(guideHTML.contains("data-command=\"\(command)\""), "Undocumented menu: \(item.title) (\(command))")
        }
        XCTAssertFalse(all.contains { $0.action == NSSelectorFromString("aiDiagnoseError:") })
        XCTAssertFalse(ProFeature.analysisMenu.contains(.aiOverview))
        let toolbar = MainToolbarDelegate(controller: MainWindowController())
        let bar = NSToolbar(identifier: "test.noAI")
        XCTAssertFalse(toolbar.toolbarDefaultItemIdentifiers(bar).contains(.mrAIDiagnose))
        XCTAssertFalse(toolbar.toolbarAllowedItemIdentifiers(bar).contains(.mrAIDiagnose))
        XCTAssertNil(toolbar.toolbar(bar, itemForItemIdentifier: .mrAIDiagnose, willBeInsertedIntoToolbar: true))
        let preferences = PreferencesWindowController()
        let tabs = try XCTUnwrap(preferences.window?.contentViewController as? NSTabViewController)
        XCTAssertFalse(tabs.tabViewItems.contains { $0.label == L("prefs.ai.tab") })
        let folder = try XCTUnwrap(all.first { $0.action == NSSelectorFromString("folderSearch:") })
        let format = try XCTUnwrap(all.first { $0.action == NSSelectorFromString("toggleFormatCompare:") })
        XCTAssertNotEqual(folder.keyEquivalentModifierMask, format.keyEquivalentModifierMask)
        for selector in ["remoteReconnect:", "remoteFollow:", "remoteAutoReconnect:"] {
            XCTAssertFalse(delegate.validateMenuItem(try XCTUnwrap(all.first { $0.action == NSSelectorFromString(selector) })))
        }
    }

    func testOfflineGuideLoadsAllImagesAndSupportsFind() async throws {
        _ = NSApplication.shared
        let url = try XCTUnwrap(UserGuideWindowController.guideURL)
        let html = try String(contentsOf: url)
        XCTAssertEqual(html.components(separatedBy: "<h2 ").count - 1, 23)
        XCTAssertGreaterThan(html.components(separatedBy: "<pre><code>").count - 1, 2)
        XCTAssertTrue(html.contains("默认打开程序"))
        XCTAssertTrue(html.contains("保持大小写"))
        XCTAssertTrue(html.contains("恢复所选"))
        XCTAssertFalse(html.contains("&lt;!-- commands:"))
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("AI"))
        XCTAssertFalse(html.contains("API Key"))
        let guide = UserGuideWindowController(); guide.showWindow(nil)
        defer { guide.close() }
        let web = try XCTUnwrap(guide.window?.contentView?.subviews.compactMap { $0 as? WKWebView }.first)
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if !web.isLoading, web.url != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        // Read actual rendered DOM; force lazy images to load before validating every asset.
        _ = try await web.evaluateJavaScript("document.querySelectorAll('img').forEach(i => i.loading='eager')")
        var imagesReady = false
        while Date() < deadline {
            imagesReady = (try await web.evaluateJavaScript("Array.from(document.images).every(i=>i.complete && i.naturalWidth>0)")) as? Bool == true
            if imagesReady { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(imagesReady)
        let anchorCount = try await web.evaluateJavaScript("document.querySelectorAll('nav a').length")
        XCTAssertEqual(anchorCount as? Int, 23)
        let result = await withCheckedContinuation { continuation in
            web.find("SSH", configuration: WKFindConfiguration()) { continuation.resume(returning: $0.matchFound) }
        }
        XCTAssertTrue(result)
    }
}
