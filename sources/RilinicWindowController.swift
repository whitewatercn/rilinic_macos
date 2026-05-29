//
//  RilinicWindowController.swift
//  Squirrel
//
//  rilinic 配置窗口：登录 / 词库更新 / 医学词库设置
//

import AppKit

final class RilinicWindowController: NSWindowController {
  // MARK: - 数据
  private let networkClient = RilinicNetworkClient()
  private let downloadManager = RilinicDownloadManager()
  private var currentToken: String?
  private var allFiles: [RilinicFileInfo] = []
  private var filteredFiles: [RilinicFileInfo] = []
  private var clinicEntries: [RilinicClinicSettings.ClinicEntry] = []
  private var filteredClinicEntries: [RilinicClinicSettings.ClinicEntry] = []
  private var selectedCategoryKey = "daily"
  private var pendingDeployPath = ""

  // MARK: - UI 元素
  private let containerView = NSView()
  private let loginView = NSView()
  private let updateView = NSView()

  // 登录视图
  private let accountField = NSTextField()
  private let passwordField = NSSecureTextField()
  private let loginButton = NSButton()
  private let registerButton = NSButton()
  private let loginStatusLabel = NSTextField()

  // 更新视图
  private let categoryTableView = NSTableView()
  private let fileTableView = NSTableView()
  private let refreshButton = NSButton()
  private let actionButton = NSButton()
  private let logoutButton = NSButton()
  private let summaryLabel = NSTextField()
  private let progressIndicator = NSProgressIndicator()
  private let clinicSearchField = NSTextField()

  private let scrollView = NSScrollView()

  // MARK: - 初始化

  convenience init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 360),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: true
    )
    window.title = NSLocalizedString("医键通", comment: "Rilinic window title")
    window.center()
    self.init(window: window)
    setupUI()
    checkAutoLogin()
  }

  // MARK: - UI 布局

  private func setupUI() {
    guard let window = window else { return }

    window.contentView = containerView

    buildLoginView()
    buildUpdateView()

    containerView.addSubview(loginView)
    containerView.addSubview(updateView)

    loginView.isHidden = false
    updateView.isHidden = true
  }

  // MARK: - 登录视图构建

  private func buildLoginView() {
    loginView.frame = NSRect(x: 0, y: 0, width: 400, height: 360)

    let titleLabel = makeLabel("医学输入法词库管理", fontSize: 14, bold: true)
    titleLabel.frame = NSRect(x: 20, y: 290, width: 360, height: 24)
    loginView.addSubview(titleLabel)

    let accountLabel = makeLabel("账号:", fontSize: 12, bold: false)
    accountLabel.frame = NSRect(x: 50, y: 240, width: 60, height: 20)
    loginView.addSubview(accountLabel)

    accountField.frame = NSRect(x: 120, y: 236, width: 230, height: 24)
    accountField.placeholderString = "请输入账号"
    loginView.addSubview(accountField)

    let passwordLabel = makeLabel("密码:", fontSize: 12, bold: false)
    passwordLabel.frame = NSRect(x: 50, y: 200, width: 60, height: 20)
    loginView.addSubview(passwordLabel)

    passwordField.frame = NSRect(x: 120, y: 196, width: 230, height: 24)
    passwordField.placeholderString = "请输入密码"
    passwordField.target = self
    passwordField.action = #selector(doLogin)
    loginView.addSubview(passwordField)

    loginButton.frame = NSRect(x: 120, y: 150, width: 100, height: 28)
    loginButton.title = NSLocalizedString("登录", comment: "")
    loginButton.bezelStyle = .rounded
    loginButton.target = self
    loginButton.action = #selector(doLogin)
    loginView.addSubview(loginButton)

    registerButton.frame = NSRect(x: 250, y: 150, width: 100, height: 28)
    registerButton.title = NSLocalizedString("注册", comment: "")
    registerButton.bezelStyle = .rounded
    registerButton.target = self
    registerButton.action = #selector(doRegister)
    loginView.addSubview(registerButton)

    loginStatusLabel.frame = NSRect(x: 20, y: 100, width: 360, height: 20)
    loginStatusLabel.isEditable = false
    loginStatusLabel.isBordered = false
    loginStatusLabel.drawsBackground = false
    loginStatusLabel.alignment = .center
    loginStatusLabel.textColor = .secondaryLabelColor
    loginView.addSubview(loginStatusLabel)
  }

  // MARK: - 更新视图构建

  private func buildUpdateView() {
    updateView.frame = NSRect(x: 0, y: 0, width: 860, height: 520)

    // --- 工具栏 ---
    refreshButton.frame = NSRect(x: 15, y: 472, width: 120, height: 28)
    refreshButton.title = NSLocalizedString("刷新列表", comment: "")
    refreshButton.bezelStyle = .rounded
    refreshButton.target = self
    refreshButton.action = #selector(refreshFiles)
    updateView.addSubview(refreshButton)

    actionButton.frame = NSRect(x: 725, y: 472, width: 120, height: 28)
    actionButton.title = NSLocalizedString("更新选中文件", comment: "")
    actionButton.bezelStyle = .rounded
    actionButton.isEnabled = false
    actionButton.target = self
    actionButton.action = #selector(doUpdateAction)
    updateView.addSubview(actionButton)

    logoutButton.frame = NSRect(x: 15, y: 440, width: 80, height: 22)
    logoutButton.title = NSLocalizedString("退出登录", comment: "")
    logoutButton.bezelStyle = .recessed
    logoutButton.target = self
    logoutButton.action = #selector(doLogout)
    updateView.addSubview(logoutButton)

    // --- 搜索框（医学词库模式） ---
    clinicSearchField.frame = NSRect(x: 180, y: 474, width: 200, height: 24)
    clinicSearchField.placeholderString = "搜索词库..."
    clinicSearchField.isHidden = true
    clinicSearchField.target = self
    clinicSearchField.action = #selector(clinicSearchChanged)
    updateView.addSubview(clinicSearchField)

    // --- 进度指示器 ---
    progressIndicator.frame = NSRect(x: 15, y: 410, width: 830, height: 20)
    progressIndicator.isIndeterminate = false
    progressIndicator.minValue = 0
    progressIndicator.maxValue = 100
    progressIndicator.isHidden = true
    updateView.addSubview(progressIndicator)

    // --- 摘要标签 ---
    summaryLabel.frame = NSRect(x: 15, y: 390, width: 830, height: 20)
    summaryLabel.isEditable = false
    summaryLabel.isBordered = false
    summaryLabel.drawsBackground = false
    summaryLabel.textColor = .secondaryLabelColor
    summaryLabel.font = NSFont.systemFont(ofSize: 11)
    updateView.addSubview(summaryLabel)

    // --- 分类列表（左） ---
    let categoryScroll = NSScrollView(frame: NSRect(x: 10, y: 10, width: 160, height: 370))
    categoryScroll.hasVerticalScroller = true
    categoryScroll.autohidesScrollers = true
    categoryScroll.borderType = .bezelBorder
    categoryTableView.frame = categoryScroll.bounds
    categoryTableView.headerView = nil
    let catCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cat"))
    catCol.width = 158
    categoryTableView.addTableColumn(catCol)
    categoryTableView.delegate = self
    categoryTableView.dataSource = self
    categoryScroll.documentView = categoryTableView
    updateView.addSubview(categoryScroll)

    // --- 文件表格（右） ---
    let fileScroll = NSScrollView(frame: NSRect(x: 180, y: 10, width: 665, height: 370))
    fileScroll.hasVerticalScroller = true
    fileScroll.autohidesScrollers = true
    fileScroll.borderType = .bezelBorder
    fileTableView.frame = fileScroll.bounds
    fileTableView.delegate = self
    fileTableView.dataSource = self
    fileTableView.allowsMultipleSelection = false
    fileScroll.documentView = fileTableView
    updateView.addSubview(fileScroll)
  }

  // MARK: - 视图切换

  private func showLoginView() {
    guard let window = window else { return }
    window.setContentSize(NSSize(width: 400, height: 360))
    window.center()
    loginView.isHidden = false
    updateView.isHidden = true
    accountField.stringValue = ""
    passwordField.stringValue = ""
    loginStatusLabel.stringValue = ""
    loginButton.isEnabled = true
  }

  private func showUpdateView() {
    guard let window = window else { return }
    window.setContentSize(NSSize(width: 860, height: 520))
    window.center()
    loginView.isHidden = true
    updateView.isHidden = false
    summaryLabel.stringValue = "点击刷新列表获取云端词库和配置文件"
  }

  // MARK: - 自动登录

  private func checkAutoLogin() {
    if let token = RilinicTokenStorage.load() {
      loginStatusLabel.stringValue = "检测到本地缓存的 Token，正在自动登录..."
      currentToken = token
      showUpdateView()
      refreshFiles()
    }
  }

  // MARK: - 登录

  @objc private func doLogin() {
    let account = accountField.stringValue.trimmingCharacters(in: .whitespaces)
    let password = passwordField.stringValue.trimmingCharacters(in: .whitespaces)

    guard !account.isEmpty, !password.isEmpty else {
      showAlert(message: "账号和密码不能为空")
      return
    }

    loginButton.isEnabled = false
    loginStatusLabel.stringValue = "正在登录..."

    networkClient.login(account: account, password: password) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.loginButton.isEnabled = true

        switch result {
        case .success(let response):
          if response.success, let token = response.token {
            let fullToken = "Bearer \(token)"
            RilinicTokenStorage.save(token: fullToken)
            self.currentToken = fullToken
            self.showUpdateView()
            self.refreshFiles()
          } else {
            self.loginStatusLabel.stringValue = response.message ?? "登录失败"
          }
        case .failure(let error):
          self.loginStatusLabel.stringValue = error.localizedDescription
        }
      }
    }
  }

  @objc private func doRegister() {
    showAlert(message: "注册功能开发中，请联系客服")
  }

  @objc private func doLogout() {
    RilinicTokenStorage.delete()
    currentToken = nil
    allFiles = []
    filteredFiles = []
    clinicEntries = []
    categoryTableView.reloadData()
    fileTableView.reloadData()
    showLoginView()
  }

  // MARK: - 刷新文件列表

  @objc private func refreshFiles() {
    guard let token = currentToken else {
      showLoginView()
      return
    }

    refreshButton.isEnabled = false
    actionButton.isEnabled = false
    summaryLabel.stringValue = "正在获取 OSS 文件列表..."

    networkClient.fetchFiles(token: token) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.refreshButton.isEnabled = true

        switch result {
        case .success(let response):
          self.allFiles = sortByCategory(response.files.map { classifyOSSFile($0) })
          self.selectedCategoryKey = "daily"
          self.populateCategoryList()
          self.populateFilesForCategory()
          self.summaryLabel.stringValue = "已获取 \(response.count) 个文件，请选择左侧分类和右侧文件"
        case .failure(let error):
          if case RilinicNetworkError.tokenExpired = error {
            self.doLogout()
          }
          self.summaryLabel.stringValue = error.localizedDescription
          self.showAlert(message: error.localizedDescription)
        }
      }
    }
  }

  // MARK: - 分类列表

  private func populateCategoryList() {
    let counts: [String: Int] = {
      var dict: [String: Int] = [:]
      for file in allFiles {
        dict[file.categoryKey, default: 0] += 1
      }
      return dict
    }()

    categoryTableView.reloadData()

    // 选中第一个有效分类
    for (i, cat) in updateCategories.enumerated() {
      if cat.key == "uncategorized" && counts[cat.key, default: 0] == 0 { continue }
      categoryTableView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
      selectedCategoryKey = cat.key
      break
    }
  }

  private func populateFilesForCategory() {
    clinicSearchField.isHidden = true
    actionButton.title = "更新选中文件"
    actionButton.isEnabled = false
    setupFileTableColumns()

    if selectedCategoryKey == "clinic" {
      // 医学词库模式
      clinicSearchField.isHidden = false
      actionButton.title = "保存医学词库设置"
      setupClinicTableColumns()
      let cloudClinicFiles = allFiles.filter { $0.categoryKey == "clinic" }
      clinicEntries = RilinicClinicSettings.loadEntries(cloudFiles: cloudClinicFiles)
      applyClinicSearch()
      actionButton.isEnabled = currentToken != nil && !clinicEntries.isEmpty
      fileTableView.reloadData()
      return
    }

    filteredFiles = allFiles.filter { $0.categoryKey == selectedCategoryKey }
    fileTableView.reloadData()
    if !filteredFiles.isEmpty {
      fileTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }
    actionButton.isEnabled = currentToken != nil && !filteredFiles.isEmpty
  }

  // MARK: - 文件表格列

  private func setupFileTableColumns() {
    fileTableView.tableColumns.forEach { fileTableView.removeTableColumn($0) }
    let cols = [("文件名称", 280), ("文件位置", 230), ("大小", 70), ("更新时间", 85)]
    for (title, width) in cols {
      let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(title))
      col.title = title
      col.width = CGFloat(width)
      if title == "大小" { col.headerCell.alignment = .right }
      fileTableView.addTableColumn(col)
    }
  }

  private func setupClinicTableColumns() {
    fileTableView.tableColumns.forEach { fileTableView.removeTableColumn($0) }
    let cols = [("启用", 40), ("词库名称", 280), ("大小", 70), ("配置项", 275)]
    for (title, width) in cols {
      let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(title))
      col.title = title
      col.width = CGFloat(width)
      fileTableView.addTableColumn(col)
    }
  }

  // MARK: - 医学词库搜索

  @objc private func clinicSearchChanged() {
    applyClinicSearch()
    fileTableView.reloadData()
  }

  private func applyClinicSearch() {
    let keyword = clinicSearchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
    if keyword.isEmpty {
      filteredClinicEntries = clinicEntries
    } else {
      filteredClinicEntries = clinicEntries.filter {
        $0.displayName.lowercased().contains(keyword) || $0.importPath.lowercased().contains(keyword)
      }
    }
  }

  // MARK: - 更新/保存操作

  @objc private func doUpdateAction() {
    guard let token = currentToken else { return }

    if selectedCategoryKey == "clinic" {
      saveClinicSettings()
      return
    }

    downloadSelectedFile(token: token)
  }

  private func saveClinicSettings() {
    do {
      let backupPath = try RilinicClinicSettings.saveEnabledStates(clinicEntries)
      showAlert(message: "医学词库设置已更新\n\n配置文件: \(RilinicClinicSettings.configPath.path)\n\n备份文件: \(backupPath.path)")
    } catch {
      showAlert(message: "保存失败: \(error.localizedDescription)")
    }
  }

  private func downloadSelectedFile(token: String) {
    guard let selectedFile = selectedFileInfo() else {
      showAlert(message: "请先在列表中选择一个要更新的文件")
      return
    }

    let objectKey = selectedFile.objectKey
    guard !objectKey.isEmpty else {
      showAlert(message: "选中文件缺少 objectKey")
      return
    }

    refreshButton.isEnabled = false
    actionButton.isEnabled = false
    progressIndicator.isHidden = false
    progressIndicator.doubleValue = 5
    summaryLabel.stringValue = "正在获取下载链接..."

    networkClient.fetchDownloadURLs(token: token, objectKeys: [objectKey]) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        switch result {
        case .success(let response):
          guard let downloadFile = response.files.first(where: { $0.objectKey == objectKey }) ?? response.files.first,
                !downloadFile.downloadUrl.isEmpty else {
            self.showAlert(message: "服务器未返回下载地址")
            self.resetProgress()
            return
          }

          let tempDir = FileManager.default.temporaryDirectory
          let safeName = selectedFile.deployRelativePath.replacingOccurrences(of: "/", with: "__")
          let destination = tempDir.appendingPathComponent(safeName.isEmpty ? "rilinic_file" : safeName)

          self.pendingDeployPath = selectedFile.deployRelativePath
          self.summaryLabel.stringValue = "正在下载..."
          self.progressIndicator.doubleValue = 10

          self.downloadManager.download(
            from: URL(string: downloadFile.downloadUrl)!,
            to: destination,
            expectedHash: downloadFile.hash,
            progress: { fraction in
              DispatchQueue.main.async {
                self.progressIndicator.doubleValue = 10 + fraction * 70
              }
            },
            completion: { result in
              DispatchQueue.main.async {
                switch result {
                case .success(let fileURL):
                  self.deployDownloadedFile(fileURL)
                case .failure(let error):
                  self.showAlert(message: "下载失败: \(error.localizedDescription)")
                  self.resetProgress()
                }
              }
            }
          )
        case .failure(let error):
          self.showAlert(message: error.localizedDescription)
          self.resetProgress()
        }
      }
    }
  }

  private func deployDownloadedFile(_ fileURL: URL) {
    summaryLabel.stringValue = "正在部署..."
    progressIndicator.doubleValue = 85

    do {
      // 备份
      let warning = RilinicDeployManager.backupExistingDict()
      progressIndicator.doubleValue = 90

      // 部署
      let target = try RilinicDeployManager.deploySingleFile(source: fileURL, relativePath: pendingDeployPath)
      progressIndicator.doubleValue = 100
      summaryLabel.stringValue = "部署完成: \(target.lastPathComponent)"

      // 清理临时文件
      try? FileManager.default.removeItem(at: fileURL)

      var msg = "更新完成！文件已部署到:\n\(target.path)"
      if let warn = warning { msg += "\n\n警告: \(warn)" }
      showAlert(message: msg)
    } catch {
      showAlert(message: "部署失败: \(error.localizedDescription)")
    }

    resetProgress()
  }

  private func selectedFileInfo() -> RilinicFileInfo? {
    let row = fileTableView.selectedRow
    guard row >= 0, row < filteredFiles.count else { return nil }
    return filteredFiles[row]
  }

  private func resetProgress() {
    refreshButton.isEnabled = true
    actionButton.isEnabled = true
    progressIndicator.isHidden = true
    progressIndicator.doubleValue = 0
  }

  // MARK: - 辅助

  private func makeLabel(_ text: String, fontSize: CGFloat, bold: Bool) -> NSTextField {
    let label = NSTextField()
    label.stringValue = text
    label.isEditable = false
    label.isBordered = false
    label.drawsBackground = false
    label.font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
    return label
  }

  private func showAlert(message: String) {
    let alert = NSAlert()
    alert.messageText = "医键通"
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: "确定")
    alert.beginSheetModal(for: window!)
  }

  private func formatSize(_ size: Int64) -> String {
    if size <= 0 { return "-" }
    let units = ["B", "KB", "MB", "GB"]
    var value = Double(size)
    var idx = 0
    while value >= 1024 && idx < units.count - 1 {
      value /= 1024; idx += 1
    }
    return idx == 0 ? "\(Int(value)) \(units[idx])" : String(format: "%.1f \(units[idx])", value)
  }

  private func formatTime(_ ms: Int64) -> String {
    if ms <= 0 { return "-" }
    let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
  }
}

// MARK: - NSTableViewDataSource & Delegate

extension RilinicWindowController: NSTableViewDataSource, NSTableViewDelegate {

  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == categoryTableView {
      return updateCategories.count
    }

    if selectedCategoryKey == "clinic" {
      return filteredClinicEntries.count
    }
    return filteredFiles.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    if tableView == categoryTableView {
      return makeCategoryCell(row: row)
    }

    if selectedCategoryKey == "clinic" {
      return makeClinicCell(row: row, column: tableColumn)
    }
    return makeFileCell(row: row, column: tableColumn)
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    if tableView == categoryTableView {
      guard row < updateCategories.count else { return false }
      let cat = updateCategories[row]
      if cat.key == "uncategorized" && allFiles.filter({ $0.categoryKey == "uncategorized" }).isEmpty {
        return false
      }
      return true
    }
    return selectedCategoryKey != "clinic"
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard let tableView = notification.object as? NSTableView else { return }

    if tableView == categoryTableView {
      let row = tableView.selectedRow
      guard row >= 0, row < updateCategories.count else { return }
      selectedCategoryKey = updateCategories[row].key
      populateFilesForCategory()
    } else if tableView == fileTableView {
      actionButton.isEnabled = tableView.selectedRow >= 0 && currentToken != nil
    }
  }

  // MARK: - 分类单元格

  private func makeCategoryCell(row: Int) -> NSView? {
    guard row < updateCategories.count else { return nil }
    let cat = updateCategories[row]

    let count = cat.key == "clinic"
      ? clinicEntries.count
      : allFiles.filter { $0.categoryKey == cat.key }.count

    let id = NSUserInterfaceItemIdentifier("catCell")
    if let cell = categoryTableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
      cell.textField?.stringValue = "\(cat.label)\n\(count) 个文件"
      return cell
    }

    let cell = NSTableCellView()
    cell.identifier = id
    let tf = NSTextField()
    tf.isEditable = false
    tf.isBordered = false
    tf.drawsBackground = false
    tf.font = NSFont.systemFont(ofSize: 12)
    tf.frame = NSRect(x: 5, y: 5, width: 148, height: 36)
    tf.stringValue = "\(cat.label)\n\(count) 个文件"
    cell.addSubview(tf)
    cell.textField = tf
    return cell
  }

  // MARK: - 文件单元格

  private func makeFileCell(row: Int, column: NSTableColumn?) -> NSView? {
    guard row < filteredFiles.count, let col = column else { return nil }
    let file = filteredFiles[row]

    let text: String
    switch col.title {
    case "文件名称": text = file.displayName
    case "文件位置": text = file.deployRelativePath
    case "大小": text = formatSize(file.size)
    case "更新时间": text = formatTime(file.lastModified)
    default: text = ""
    }

    let id = NSUserInterfaceItemIdentifier("file_\(col.title)")
    if let cell = fileTableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
      cell.textField?.stringValue = text
      return cell
    }

    let cell = NSTableCellView()
    cell.identifier = id
    let tf = NSTextField()
    tf.isEditable = false
    tf.isBordered = false
    tf.drawsBackground = false
    tf.font = NSFont.systemFont(ofSize: 12)
    tf.frame = NSRect(x: 4, y: 2, width: col.width - 8, height: 18)
    tf.stringValue = text
    if col.title == "大小" { tf.alignment = .right }
    cell.addSubview(tf)
    cell.textField = tf
    return cell
  }

  // MARK: - 医学词库单元格

  private func makeClinicCell(row: Int, column: NSTableColumn?) -> NSView? {
    guard row < filteredClinicEntries.count, let col = column else { return nil }
    let entry = filteredClinicEntries[row]

    switch col.title {
    case "启用":
      let id = NSUserInterfaceItemIdentifier("clinic_check")
      if let cell = fileTableView.makeView(withIdentifier: id, owner: nil) as? NSButton {
        cell.state = entry.enabled ? .on : .off
        cell.tag = row
        return cell
      }
      let btn = NSButton(checkboxWithTitle: "", target: self, action: #selector(clinicCheckboxToggled(_:)))
      btn.identifier = id
      btn.state = entry.enabled ? .on : .off
      btn.tag = row
      return btn

    case "词库名称":
      return makeTextCell(text: entry.displayName, id: "clinic_name")

    case "大小":
      return makeTextCell(text: formatSize(entry.size ?? 0), id: "clinic_size", align: .right)

    case "配置项":
      return makeTextCell(text: entry.importPath, id: "clinic_path")

    default:
      return nil
    }
  }

  private func makeTextCell(text: String, id: String, align: NSTextAlignment = .left) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier(id)
    if let cell = fileTableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
      cell.textField?.stringValue = text
      return cell
    }
    let cell = NSTableCellView()
    cell.identifier = identifier
    let tf = NSTextField()
    tf.isEditable = false
    tf.isBordered = false
    tf.drawsBackground = false
    tf.font = NSFont.systemFont(ofSize: 12)
    tf.frame = NSRect(x: 4, y: 2, width: 250, height: 18)
    tf.stringValue = text
    tf.alignment = align
    cell.addSubview(tf)
    cell.textField = tf
    return cell
  }

  @objc private func clinicCheckboxToggled(_ sender: NSButton) {
    let row = sender.tag
    guard row < clinicEntries.count else { return }
    clinicEntries[row].enabled = (sender.state == .on)
  }
}