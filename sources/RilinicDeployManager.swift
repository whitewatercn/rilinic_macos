//
//  RilinicDeployManager.swift
//  Squirrel
//
//  文件部署管理：备份 Rime 配置、单文件覆盖、zip 解压
//

import Foundation

final class RilinicDeployManager {

  // MARK: - 路径

  static var rimeDir: URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent("Library/Rime")
  }

  static var backupDir: URL {
    return rimeDir.appendingPathComponent("backup")
  }

  // MARK: - 备份

  /// 备份 Rime 目录下的可见文件到 backup/ 目录（zip 格式）
  /// 返回 nil 表示成功，返回字符串表示警告信息
  static func backupExistingDict(progress: ((Int, Int) -> Void)? = nil) -> String? {
    let fm = FileManager.default
    guard fm.fileExists(atPath: rimeDir.path) else { return nil }

    // 收集可见文件（排除隐藏文件和 backup/downloaded/logs 目录）
    let files = collectVisibleFiles(in: rimeDir, fm: fm)
    if files.isEmpty { return nil }

    do {
      try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

      let formatter = DateFormatter()
      formatter.dateFormat = "yyyyMMddHHmm"
      let timestamp = formatter.string(from: Date())
      let backupPath = backupDir.appendingPathComponent("rime_backup_\(timestamp).zip")

      progress?(0, files.count)

      // 使用系统 zip 命令
      let tempDir = fm.temporaryDirectory.appendingPathComponent("rime_backup_\(timestamp)")
      try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

      for (index, (src, rel)) in files.enumerated() {
        let dst = tempDir.appendingPathComponent(rel)
        try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: src, to: dst)
        progress?(index + 1, files.count)
      }

      // 创建 zip
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
      process.arguments = ["-rq", backupPath.path, "."]
      process.currentDirectoryURL = tempDir
      try process.run()
      process.waitUntilExit()

      // 清理临时目录
      try? fm.removeItem(at: tempDir)

      print("Rilinic: backup created at \(backupPath.path)")
      return nil
    } catch {
      print("Rilinic: backup failed: \(error)")
      return "无法备份旧词库: \(error.localizedDescription)"
    }
  }

  private static func collectVisibleFiles(in dir: URL, fm: FileManager) -> [(URL, String)] {
    var result: [(URL, String)] = []
    let excludeDirs: Set<String> = ["downloaded", "backup", "logs"]

    guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else {
      return result
    }

    for case let fileURL as URL in enumerator {
      let fileName = fileURL.lastPathComponent
      if fileName.hasPrefix(".") { continue }

      let relPath = fileURL.path.replacingOccurrences(of: dir.path + "/", with: "")

      // 跳过排除的目录
      let firstComponent = relPath.components(separatedBy: "/").first ?? ""
      if excludeDirs.contains(firstComponent) {
        enumerator.skipDescendants()
        continue
      }

      var isDir: ObjCBool = false
      if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue {
        result.append((fileURL, relPath))
      }
    }

    return result
  }

  // MARK: - 单文件部署

  /// 将下载文件复制到 Rime 目录下的相对路径
  static func deploySingleFile(source: URL, relativePath: String) throws -> URL {
    let normalized = relativePath
      .replacingOccurrences(of: "\\", with: "/")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    guard !normalized.isEmpty, normalized != "." else {
      throw NSError(domain: "RilinicDeploy", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少可部署的相对路径"])
    }
    guard normalized != ".." && !normalized.hasPrefix("../") else {
      throw NSError(domain: "RilinicDeploy", code: 2, userInfo: [NSLocalizedDescriptionKey: "文件路径不安全，已拒绝部署"])
    }

    let target = rimeDir.appendingPathComponent(normalized)
    let fm = FileManager.default
    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

    if fm.fileExists(atPath: target.path) {
      try fm.removeItem(at: target)
    }
    try fm.copyItem(at: source, to: target)
    print("Rilinic: deployed to \(target.path)")
    return target
  }

  // MARK: - Zip 解压部署

  /// 解压 zip 并将内容映射到 Rime 目录（跳过 "rilinic/" 前缀）
  static func deployZip(source: URL,
                        progress: ((Int, Int) -> Void)? = nil) throws -> (extracted: [URL], failed: [String]) {
    let fm = FileManager.default
    let tempDir = fm.temporaryDirectory.appendingPathComponent("rilinic_extract_\(UUID().uuidString)")
    defer { try? fm.removeItem(at: tempDir) }

    // 使用系统 unzip
    let unzip = Process()
    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    unzip.arguments = ["-qo", source.path, "-d", tempDir.path]
    try unzip.run()
    unzip.waitUntilExit()

    var extracted: [URL] = []
    var failed: [String] = []

    guard let enumerator = fm.enumerator(at: tempDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
      throw NSError(domain: "RilinicDeploy", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法读取解压内容"])
    }

    var allFiles: [URL] = []
    for case let fileURL as URL in enumerator {
      var isDir: ObjCBool = false
      if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue {
        allFiles.append(fileURL)
      }
    }

    let total = allFiles.count
    progress?(0, total)

    for (index, fileURL) in allFiles.enumerated() {
      let relPath = fileURL.path.replacingOccurrences(of: tempDir.path + "/", with: "")
      let parts = relPath.components(separatedBy: "/")
      guard let rilinicIdx = parts.firstIndex(of: "rilinic") else { continue }
      let mappedParts = parts[(rilinicIdx + 1)...]
      guard !mappedParts.isEmpty else { continue }
      let mappedPath = mappedParts.joined(separator: "/")

      do {
        let target = rimeDir.appendingPathComponent(mappedPath)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: target.path) {
          try fm.removeItem(at: target)
        }
        try fm.copyItem(at: fileURL, to: target)
        extracted.append(target)
      } catch {
        failed.append(relPath)
        print("Rilinic: deploy failed for \(relPath): \(error)")
      }

      progress?(index + 1, total)
    }

    return (extracted, failed)
  }
}