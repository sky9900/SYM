// The MIT License (MIT)
//
// Copyright (c) 2017 - present zqqf16
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Cocoa

extension NSPopUpButton {
    func reloadItemsWithApps(_ apps: [MDAppInfo]) {
        removeAllItems()
        apps.forEach { app in
            self.addItem(withTitle: "\(app.name)(\(app.identifier))")
        }
    }
}

class FileBrowserViewController: NSViewController, LoadingAble {
    @IBOutlet var exportButton: NSButton!
    @IBOutlet var exportIndicator: NSProgressIndicator!
    @IBOutlet var outlineView: NSOutlineView!

    var loadingIndicator: NSProgressIndicator!

    private var deviceID: String?
    private var appID: String?

    private var rootDir: MDDeviceFile!
    private var afcClient: MDAfcClient!
    private var refreshTimer: DispatchSourceTimer?

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopRefreshTimer()
    }

    deinit {
        stopRefreshTimer()
    }

    private func startRefreshTimer() {
        stopRefreshTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            self?.autoRefresh()
        }
        refreshTimer = timer
        timer.resume()
    }

    private func stopRefreshTimer() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    private func autoRefresh() {
        guard let deviceID = self.deviceID, let appID = self.appID else { return }

        var expandedPaths: Set<String> = []
        collectExpandedPaths(item: nil, into: &expandedPaths)

        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            let lockdown = MDLockdown(udid: deviceID)
            let houseArrest = MDHouseArrest(lockdown: lockdown, appID: appID)
            let afcClient = MDAfcClient.fileClient(with: houseArrest)
            let rootDir = MDDeviceFile(afcClient: afcClient)
            rootDir.path = "."
            rootDir.isDirectory = true
            _ = rootDir.children

            self.preloadExpandedPaths(item: rootDir, expandedPaths: expandedPaths)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.afcClient = afcClient
                self.rootDir = rootDir
                self.outlineView.reloadData()
                self.restoreExpanded(item: nil, expandedPaths: expandedPaths)
            }
        }
    }

    private func collectExpandedPaths(item: Any?, into paths: inout Set<String>) {
        let count: Int
        if let file = item as? MDDeviceFile {
            if !outlineView.isItemExpanded(file) { return }
            paths.insert(file.path)
            count = outlineView.numberOfChildren(ofItem: file)
        } else {
            count = outlineView.numberOfChildren(ofItem: nil)
        }
        for i in 0..<count {
            let child = item == nil
                ? outlineView.child(i, ofItem: nil)
                : outlineView.child(i, ofItem: item)
            collectExpandedPaths(item: child, into: &paths)
        }
    }

    private func preloadExpandedPaths(item: MDDeviceFile, expandedPaths: Set<String>) {
        if item.isDirectory && expandedPaths.contains(item.path) {
            _ = item.children
        }
        if let children = item.children {
            for child in children {
                if child.isDirectory {
                    preloadExpandedPaths(item: child, expandedPaths: expandedPaths)
                }
            }
        }
    }

    private func restoreExpanded(item: Any?, expandedPaths: Set<String>) {
        let count: Int
        if let file = item as? MDDeviceFile {
            count = outlineView.numberOfChildren(ofItem: file)
        } else {
            count = outlineView.numberOfChildren(ofItem: nil)
        }
        for i in 0..<count {
            let child = item == nil
                ? outlineView.child(i, ofItem: nil)
                : outlineView.child(i, ofItem: item)
            if let file = child as? MDDeviceFile, file.isDirectory,
               expandedPaths.contains(file.path) {
                outlineView.expandItem(file)
                restoreExpanded(item: file, expandedPaths: expandedPaths)
            }
        }
    }

    func reloadData(withDeviceID deviceID: String?, appID: String?) {
        if deviceID == self.deviceID && appID == self.appID {
            return
        }

        self.deviceID = deviceID
        self.appID = appID

        if deviceID == nil || appID == nil {
            stopRefreshTimer()
            rootDir = nil
            outlineView.reloadData()
            return
        }

        showLoading()
        DispatchQueue.global().async {
            let lockdown = MDLockdown(udid: deviceID!)
            let houseArrest = MDHouseArrest(lockdown: lockdown, appID: appID!)
            let afcClient = MDAfcClient.fileClient(with: houseArrest)
            let rootDir = MDDeviceFile(afcClient: afcClient)
            rootDir.path = "."
            rootDir.isDirectory = true
            _ = rootDir.children

            DispatchQueue.main.async {
                self.afcClient = afcClient
                self.rootDir = rootDir
                self.outlineView.reloadData()
                self.hideLoading()
                self.startRefreshTimer()
            }
        }
    }

    @IBAction func didClickExportButton(_: NSButton) {
        exportSelectedFiles()
    }

    @IBAction func openFile(_: AnyObject?) {
        exportSelectedFiles()
    }

    private func exportSelectedFiles() {
        let selectedRows = outlineView.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }

        var files: [MDDeviceFile] = []
        for row in selectedRows {
            if let file = outlineView.item(atRow: row) as? MDDeviceFile {
                files.append(file)
            }
        }
        guard !files.isEmpty else { return }

        if files.count == 1 {
            exportFile(atIndex: outlineView.selectedRow)
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.message = "选择导出目录"
        openPanel.beginSheetModal(for: view.window!) { [weak self] result in
            guard result == .OK, let self = self, let url = openPanel.url else { return }
            self.showLoading()
            DispatchQueue.global().async {
                for file in files {
                    let dest = url.appendingPathComponent(file.name)
                    file.copy(dest.path)
                }
                DispatchQueue.main.async {
                    self.hideLoading()
                }
            }
        }
    }

    @IBAction func didDoubleClickCell(_: AnyObject?) {
        let row = outlineView.clickedRow
        openFile(atIndex: row)
    }

    @IBAction func reloadFiles(_: AnyObject?) {
        let deviceID = self.deviceID
        let appID = self.appID
        self.deviceID = nil
        self.appID = nil
        reloadData(withDeviceID: deviceID, appID: appID)
    }

    @IBAction func removeFile(_: AnyObject?) {
        let selectedRows = outlineView.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }

        struct ItemInfo {
            let file: MDDeviceFile
            let parent: MDDeviceFile
            let indexInParent: Int
        }

        var items: [ItemInfo] = []
        for row in selectedRows {
            guard let file = outlineView.item(atRow: row) as? MDDeviceFile,
                  let parent = outlineView.parent(forItem: file) as? MDDeviceFile
            else { continue }
            items.append(ItemInfo(file: file, parent: parent, indexInParent: outlineView.childIndex(forItem: file)))
        }
        guard !items.isEmpty else { return }

        showLoading()
        DispatchQueue.global().async {
            for item in items {
                _ = item.parent.removeChild(item.file)
            }
            DispatchQueue.main.async {
                self.outlineView.reloadData()
                self.hideLoading()
            }
        }
    }

    @IBAction func didClickImportButton(_: NSButton) {
        importFiles()
    }

    private func importFiles() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.beginSheetModal(for: view.window!) { [weak self] result in
            guard result == .OK, let self = self else { return }
            let urls = openPanel.urls
            guard !urls.isEmpty else { return }

            var targetDir: MDDeviceFile?
            let row = self.outlineView.selectedRow
            if row >= 0, let file = self.outlineView.item(atRow: row) as? MDDeviceFile {
                targetDir = file.isDirectory ? file : (self.outlineView.parent(forItem: file) as? MDDeviceFile)
            }
            if targetDir == nil {
                targetDir = self.rootDir
            }

            guard let dir = targetDir else { return }
            self.showLoading()
            DispatchQueue.global().async {
                for url in urls {
                    _ = dir.upload(fromLocalPath: url.path)
                }
                DispatchQueue.main.async {
                    self.hideLoading()
                    self.reloadFiles(nil)
                }
            }
        }
    }

    private func exportFile(atIndex index: Int) {
        guard index >= 0, let file = outlineView.item(atRow: index) as? MDDeviceFile else {
            return
        }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = file.name
        savePanel.beginSheetModal(for: view.window!) { [weak savePanel] result in
            guard result == .OK, let url = savePanel?.url else {
                return
            }
            var name = savePanel?.nameFieldStringValue ?? ""
            if name.isEmpty {
                name = file.name
            }
            let dest = URL(fileURLWithPath: name, relativeTo: url)
            self.exportFile(file, toURL: dest)
        }
    }

    private func exportFile(_ file: MDDeviceFile, toURL url: URL) {
        // self.exportIndicator.startAnimation(nil)
        // self.exportIndicator.isHidden = false
        // self.exportButton.isEnabled = false
        DispatchQueue.global().async {
            file.copy(url.path)
            /*
             DispatchQueue.main.async {
                 self.exportIndicator.stopAnimation(nil)
                 self.exportIndicator.isHidden = true
                 self.exportButton.isEnabled = true
             }
              */
        }
    }

    private func openFile(atIndex index: Int) {
        guard index >= 0, let file = outlineView.item(atRow: index) as? MDDeviceFile else {
            return
        }
        if file.isDirectory {
            exportFile(atIndex: index)
            return
        }
        showLoading()
        DispatchQueue.global().async {
            guard let udid = self.deviceID else {
                self.hideLoading()
                return
            }

            let path = FileManager.default.localCrashDirectory(udid) + "/\(file.name)"
            let url = URL(fileURLWithPath: path)
            file.copy(url.path)
            DispatchQueue.main.async {
                self.hideLoading()
                NSWorkspace.shared.open(url)
            }
        }
    }
}

extension FileBrowserViewController: NSOutlineViewDelegate, NSOutlineViewDataSource {
    func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let file = item as? MDDeviceFile, file.isDirectory, let children = file.children {
            return children.count
        }

        return rootDir?.children?.count ?? 0
    }

    func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let file = item as? MDDeviceFile, file.isDirectory, let children = file.children {
            return children[index]
        }

        return rootDir!.children![index]
    }

    func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let file = item as? MDDeviceFile, file.isDirectory, let children = file.children {
            return children.count > 0
        }

        return false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var view: NSTableCellView?
        guard let file = item as? MDDeviceFile else {
            return view
        }

        view = outlineView.makeView(withIdentifier: tableColumn!.identifier, owner: nil) as? NSTableCellView
        if tableColumn == outlineView.tableColumns[0] {
            view?.textField?.stringValue = file.name
            if file.isDirectory {
                view?.imageView?.image = NSImage(named: NSImage.folderName as NSImage.Name)
            } else {
                view?.imageView?.image = NSWorkspace.shared.icon(forFileType: file.extension)
            }
        } else if tableColumn == outlineView.tableColumns[1] {
            view?.textField?.stringValue = file.date.formattedString
        } else {
            view?.textField?.stringValue = "\(file.size.readableSize)"
        }

        return view
    }

    func outlineViewSelectionDidChange(_: Notification) {}
}
