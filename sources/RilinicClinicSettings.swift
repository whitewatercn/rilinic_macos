//
//  RilinicClinicSettings.swift
//  Squirrel
//
//  医学词库设置：解析/修改 rilinic.dict.yaml 中的 clinic_dicts 启用状态
//

import Foundation

final class RilinicClinicSettings {
  private static let clinicDictPrefix = "clinic_dicts/"
  private static let dictSuffix = ".dict.yaml"
  /// 匹配 `  - clinic_dicts/xxx.dict.yaml` 或 `  # - clinic_dicts/xxx.dict.yaml` 行
  private static let linePattern = try! NSRegularExpression(
    pattern: "^(\\s*)(#\\s*)?-\\s+(\\S+)(.*)$",
    options: [.anchorsMatchLines]
  )

  // MARK: - 路径

  static var configPath: URL {
    return RilinicDeployManager.rimeDir.appendingPathComponent("rilinic.dict.yaml")
  }

  // MARK: - 数据模型

  struct ClinicEntry {
    let importPath: String
    let displayName: String
    var enabled: Bool
    let size: Int64?
  }

  // MARK: - 加载

  /// 从 rilinic.dict.yaml 加载医学词库条目，与云端文件合并
  static func loadEntries(cloudFiles: [RilinicFileInfo]) -> [ClinicEntry] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: configPath.path) else {
      print("Rilinic: clinic config not found at \(configPath.path)")
      return []
    }

    guard let content = try? String(contentsOf: configPath, encoding: .utf8) else {
      return []
    }

    let lines = content.components(separatedBy: "\n")
    var enabledByPath: [String: Bool] = [:]
    var orderedPaths: [String] = []

    for line in lines {
      guard let match = linePattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
        continue
      }
      let importPath = substring(of: line, at: match.range(at: 3))
      guard importPath.hasPrefix(clinicDictPrefix) else { continue }

      if enabledByPath[importPath] == nil {
        orderedPaths.append(importPath)
      }
      // group(2) 为 nil 表示启用（没有被注释掉）
      let isCommentedOut = match.range(at: 2).location != NSNotFound
      enabledByPath[importPath] = !isCommentedOut
    }

    // 合并云端文件（云端有但本地没有的）
    let cloudByPath: [String: RilinicFileInfo] = {
      var dict: [String: RilinicFileInfo] = [:]
      for file in cloudFiles {
        let path = clinicImportPath(from: file)
        if !path.isEmpty { dict[path] = file }
      }
      return dict
    }()

    for importPath in cloudByPath.keys.sorted() {
      if enabledByPath[importPath] == nil {
        enabledByPath[importPath] = false
        orderedPaths.append(importPath)
      }
    }

    return orderedPaths.map { importPath in
      let name = displayName(from: importPath)
      return ClinicEntry(
        importPath: importPath,
        displayName: name,
        enabled: enabledByPath[importPath] ?? false,
        size: cloudByPath[importPath]?.size
      )
    }
  }

  // MARK: - 保存

  /// 保存启用状态到 rilinic.dict.yaml
  static func saveEnabledStates(_ entries: [ClinicEntry]) throws -> URL {
    let fm = FileManager.default
    guard fm.fileExists(atPath: configPath.path) else {
      throw NSError(domain: "RilinicClinic", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到配置文件: \(configPath.path)"])
    }

    // 备份
    let backupDir = configPath.deletingLastPathComponent().appendingPathComponent("backup")
    try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMddHHmmss"
    let backupPath = backupDir.appendingPathComponent("\(configPath.lastPathComponent).\(formatter.string(from: Date())).bak")
    try fm.copyItem(at: configPath, to: backupPath)

    // 读取并重写
    guard let content = try? String(contentsOf: configPath, encoding: .utf8) else {
      throw NSError(domain: "RilinicClinic", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法读取配置文件"])
    }

    let enabledSet = Set(entries.filter { $0.enabled }.map { $0.importPath })
    var lines = content.components(separatedBy: "\n")
    var seenPaths: Set<String> = []
    let keepNewline = content.hasSuffix("\n")

    for i in 0..<lines.count {
      guard let match = linePattern.firstMatch(in: lines[i], range: NSRange(lines[i].startIndex..., in: lines[i])) else {
        continue
      }
      let importPath = substring(of: lines[i], at: match.range(at: 3))
      guard importPath.hasPrefix(clinicDictPrefix) else { continue }

      let indent = substring(of: lines[i], at: match.range(at: 1))
      let trailing = substring(of: lines[i], at: match.range(at: 4))
      let marker = enabledSet.contains(importPath) ? "- " : "# - "
      lines[i] = "\(indent)\(marker)\(importPath)\(trailing)"
      seenPaths.insert(importPath)
    }

    // 追加新启用的条目
    let missing = entries.filter { $0.enabled && !seenPaths.contains($0.importPath) }
    if !missing.isEmpty {
      var insertIdx = findInsertIndex(lines)
      for entry in missing {
        lines.insert("  - \(entry.importPath)", at: insertIdx)
        insertIdx += 1
      }
    }

    let newContent = lines.joined(separator: "\n") + (keepNewline ? "\n" : "")
    try newContent.write(to: configPath, atomically: true, encoding: .utf8)

    print("Rilinic: clinic settings saved, backup at \(backupPath.path)")
    return backupPath
  }

  // MARK: - 辅助

  private static func substring(of string: String, at range: NSRange) -> String {
    guard range.location != NSNotFound,
          let strRange = Range(range, in: string) else { return "" }
    return String(string[strRange])
  }

  private static func clinicImportPath(from file: RilinicFileInfo) -> String {
    let path = file.deployRelativePath
    guard path.hasPrefix(clinicDictPrefix) else { return "" }
    if path.hasSuffix(dictSuffix) {
      return String(path.dropLast(dictSuffix.count))
    }
    return path
  }

  private static func displayName(from importPath: String) -> String {
    var name = importPath.components(separatedBy: "/").last ?? importPath
    for suffix in ["_full", "_short_sentence"] {
      if name.hasSuffix(suffix) {
        name = String(name.dropLast(suffix.count))
      }
    }
    return name.replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
      .trimmingCharacters(in: .whitespaces)
  }

  private static func findInsertIndex(_ lines: [String]) -> Int {
    var lastClinicIdx = -1
    var clinicHeaderIdx = -1
    var importTablesIdx = -1

    for (index, line) in lines.enumerated() {
      let stripped = line.trimmingCharacters(in: .whitespaces)
      if stripped == "import_tables:" { importTablesIdx = index }
      if stripped.contains("医学词库") { clinicHeaderIdx = index }
      if let match = linePattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
        let path = substring(of: line, at: match.range(at: 3))
        if path.hasPrefix(clinicDictPrefix) { lastClinicIdx = index }
      }
    }

    if lastClinicIdx >= 0 { return lastClinicIdx + 1 }
    if clinicHeaderIdx >= 0 { return clinicHeaderIdx + 1 }
    if importTablesIdx >= 0 { return importTablesIdx + 1 }
    return lines.count
  }
}