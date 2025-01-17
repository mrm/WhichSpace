//
//  AppDelegate.swift
//  WhichSpace
//
//  Created by George on 27/10/2015.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Cocoa
import Sparkle

@NSApplicationMain
@objc
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, SUUpdaterDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var application: NSApplication!
    @IBOutlet weak var workspace: NSWorkspace!
    @IBOutlet weak var updater: SUUpdater!

    let mainDisplay = "Main"
    let spacesMonitorFile = "~/Library/Preferences/com.apple.spaces.plist"

    let statusBarItem = NSStatusBar.system.statusItem(withLength: 27)
    let conn = _CGSDefaultConnection()

    var stringAttributes: [NSAttributedString.Key : NSObject] = [:]

    fileprivate func configureApplication() {
        application = NSApplication.shared
        // Specifying `.Accessory` both hides the Dock icon and allows
        // the update dialog to take focus
        application.setActivationPolicy(.accessory)
    }

    fileprivate func configureObservers() {
        workspace = NSWorkspace.shared
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.updateActiveSpaceNumber),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: workspace
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(AppDelegate.updateActiveSpaceNumber),
            name: NSApplication.didUpdateNotification,
            object: nil
        )
    }

    fileprivate func configureMenuBarIcon() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = NSTextAlignment.center

        stringAttributes = [
            NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 11),
            NSAttributedString.Key.paragraphStyle: paragraphStyle
        ]

        let width = statusBarItem.view?.frame.width ?? statusBarItem.image?.size.width ?? 27
        let height = statusBarItem.view?.frame.height ?? statusBarItem.image?.size.height ?? 27

        let outline = NSImage(size: NSSize(width: width, height: height ), flipped: false) { (dstRect) -> Bool in
            let black = NSColor.black.withAlphaComponent(0.85)
            black.setStroke()

            let xStart = (width - 16) / 2 + 2,
                yStart = (height - 16) / 2

            let roundedRectanglePath = NSBezierPath(roundedRect: NSRect(x: xStart - 2, y: yStart, width: 16, height: 16), xRadius: 3, yRadius: 3)
            roundedRectanglePath.lineWidth = 1.5
            roundedRectanglePath.stroke()

            return true
        }

        statusBarItem.button?.attributedTitle = NSAttributedString(string: "?", attributes: stringAttributes)

        statusBarItem.button?.image = outline
        statusBarItem.button?.image?.isTemplate = true

        statusBarItem.menu = statusMenu
    }

    fileprivate func configureSparkle() {
        updater = SUUpdater.shared()
        updater.delegate = self
        // Silently check for updates on launch
        updater.checkForUpdatesInBackground()
    }

    fileprivate func configureSpaceMonitor() {
        let fullPath = (spacesMonitorFile as NSString).expandingTildeInPath
        let queue = DispatchQueue.global(qos: .default)
        let fildes = open(fullPath.cString(using: String.Encoding.utf8)!, O_EVTONLY)
        if fildes == -1 {
            NSLog("Failed to open file: \(spacesMonitorFile)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fildes, eventMask: DispatchSource.FileSystemEvent.delete, queue: queue)

        source.setEventHandler { () -> Void in
            let flags = source.data.rawValue
            if (flags & DispatchSource.FileSystemEvent.delete.rawValue != 0) {
                source.cancel()
                self.updateActiveSpaceNumber()
                self.configureSpaceMonitor()
            }
        }

        source.setCancelHandler { () -> Void in
            close(fildes)
        }

        source.resume()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        PFMoveToApplicationsFolderIfNecessary()
        configureApplication()
        configureObservers()
        configureMenuBarIcon()
        configureSparkle()
        configureSpaceMonitor()
        updateActiveSpaceNumber()
    }

    @objc func updateActiveSpaceNumber() {
        let displays = CGSCopyManagedDisplaySpaces(conn) as! [NSDictionary]
        let activeDisplay = CGSCopyActiveMenuBarDisplayIdentifier(conn) as! String
        let allSpaces: NSMutableArray = []
        var activeSpaceID = -1

        for d in displays {
            guard
                let current = d["Current Space"] as? [String: Any],
                let spaces = d["Spaces"] as? [[String: Any]],
                let dispID = d["Display Identifier"] as? String
                else {
                    continue
            }

            switch dispID {
            case mainDisplay, activeDisplay:
                activeSpaceID = current["ManagedSpaceID"] as! Int
            default:
                break
            }

            for s in spaces {
                let isFullscreen = s["TileLayoutManager"] as? [String: Any] != nil
                if isFullscreen {
                    continue
                }
                allSpaces.add(s)
            }
        }

        if activeSpaceID == -1 {
            DispatchQueue.main.async {
                self.statusBarItem.button?.attributedTitle = NSAttributedString(string: "?", attributes: self.stringAttributes)
            }
            return
        }

        for (index, space) in allSpaces.enumerated() {
            let spaceID = (space as! NSDictionary)["ManagedSpaceID"] as! Int
            let spaceNumber = index + 1
            if spaceID == activeSpaceID {
                DispatchQueue.main.async {
                    self.statusBarItem.button?.attributedTitle = NSAttributedString(string: String("\(spaceNumber)"), attributes: self.stringAttributes)
                }
                return
            }
        }
    }


    @IBAction func checkForUpdatesClicked(_ sender: NSMenuItem) {
        updater.checkForUpdates(sender)
    }

    @IBAction func quitClicked(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }
}
