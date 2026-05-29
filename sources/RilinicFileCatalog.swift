//
//  RilinicFileCatalog.swift
//  Squirrel
//
//  OSS 文件分类、路径标准化、显示名生成
//

import Foundation

// MARK: - 数据常量

/// 重要配置文件的中文显示名映射
let importantConfigFiles: [String: String] = [
  "default.yaml": "默认配置",
  "installation.yaml": "安装信息配置",
  "melt_eng.dict.yaml": "英文混输词典",
  "melt_eng.schema.yaml": "英文混输方案",
  "radical_pinyin.dict.yaml": "部首拼音词典",
  "radical_pinyin.schema.yaml": "部首拼音方案",
  "rilinic.custom.yaml": "医键通自定义配置",
  "rilinic.dict.yaml": "医键通医学词典",
  "rilinic.schema.yaml": "医键通输入方案",
  "symbols_v.yaml": "符号配置",
  "user.yaml": "用户配置",
  "weasel.yaml": "小狼毫配置",
]

/// 更新分类定义
struct UpdateCategory {
  let key: String
  let label: String
  let summary: String
}

let updateCategories: [UpdateCategory] = [
  UpdateCategory(key: "clinic", label: "医学词库设置", summary: "启用或停用 clinic_dicts 医学词库"),
  UpdateCategory(key: "daily", label: "日常词库更新", summary: "cn_dicts、cn_dicts_cell、en_dicts 文件夹"),
  UpdateCategory(key: "important_config", label: "重要配置文件更新", summary: "核心 yaml 配置文件"),
  UpdateCategory(key: "other_config", label: "其他配置文件更新", summary: "lua、opencc、others 文件夹"),
  UpdateCategory(key: "uncategorized", label: "未分类文件", summary: "未匹配到更新规则的 OSS 文件"),
]

/// 文件夹到分类的映射
let folderCategory: [String: String] = [
  "clinic_dicts": "clinic",
  "cn_dicts": "daily",
  "cn_dicts_cell": "daily",
  "en_dicts": "daily",
  "lua": "other_config",
  "opencc": "other_config",
  "others": "other_config",
]

/// 文件夹到显示名前缀的映射
let folderDisplayPrefix: [String: String] = [
  "clinic_dicts": "医学词库",
  "cn_dicts": "日常中文词库",
  "cn_dicts_cell": "细胞词库",
  "en_dicts": "日常英文词库",
  "lua": "Lua 脚本",
  "opencc": "OpenCC 配置",
  "others": "其他配置",
]

/// 分类 key 的排序权重
let categoryOrder: [String: Int] = [
  "clinic": 0,
  "daily": 1,
  "important_config": 2,
  "other_config": 3,
  "uncategorized": 4,
]

// MARK: - 文件信息模型

struct RilinicFileInfo {
  var ossPath: String
  var deployRelativePath: String
  var displayName: String
  var categoryKey: String
  var categoryLabel: String
  var fileName: String
  var size: Int64
  var lastModified: Int64
  var objectKey: String
  var rawData: [String: Any]

  static func empty() -> RilinicFileInfo {
    return RilinicFileInfo(
      ossPath: "", deployRelativePath: "", displayName: "",
      categoryKey: "uncategorized", categoryLabel: "未分类文件",
      fileName: "", size: 0, lastModified: 0, objectKey: "",
      rawData: [:]
    )
  }
}

// MARK: - 路径处理

/// 从后端文件对象中提取 OSS 路径
func getOSSPath(from dict: [String: Any]) -> String {
  return (dict["relativePath"] as? String)
      ?? (dict["objectKey"] as? String)
      ?? (dict["fileName"] as? String)
      ?? ""
}

/// 将 OSS 路径归一到本地 Rime 目录下的相对路径，去除 "rilinic/" 前缀
func normalizeRilinicPath(_ path: String) -> String {
  let decoded = path.removingPercentEncoding ?? path
  var parts = decoded.replacingOccurrences(of: "\\", with: "/")
    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    .components(separatedBy: "/")
    .filter { !$0.isEmpty }
  if parts.first == "rilinic" {
    parts.removeFirst()
  }
  return parts.joined(separator: "/")
}

// MARK: - 显示名生成

private func cleanStem(_ fileName: String) -> String {
  var stem = fileName
  for suffix in [".dict.yaml", ".schema.yaml", ".custom.yaml", ".yaml", ".zip"] {
    if stem.hasSuffix(suffix) {
      stem = String(stem.dropLast(suffix.count))
      break
    }
  }
  stem = stem.replacingOccurrences(of: "_", with: " ")
    .replacingOccurrences(of: "-", with: " ")
    .trimmingCharacters(in: .whitespaces)
  return stem.isEmpty ? fileName : stem
}

func buildDisplayName(relativePath: String, fileName: String) -> String {
  let firstPart = relativePath.components(separatedBy: "/").first ?? ""

  if let name = importantConfigFiles[fileName] {
    return name
  }

  if let prefix = folderDisplayPrefix[firstPart] {
    return "\(prefix) - \(cleanStem(fileName))"
  }

  return cleanStem(fileName)
}

// MARK: - 分类逻辑

func classifyOSSFile(_ fileInfo: [String: Any]) -> RilinicFileInfo {
  let ossPath = getOSSPath(from: fileInfo)
  let relativePath = normalizeRilinicPath(ossPath)
  let fn = (relativePath as NSString).lastPathComponent
  let firstPart = relativePath.components(separatedBy: "/").first ?? ""

  // 确定分类
  var categoryKey = folderCategory[firstPart] ?? ""
  if importantConfigFiles[fn] != nil {
    categoryKey = "important_config"
  }
  if categoryKey.isEmpty {
    categoryKey = "uncategorized"
  }

  let categoryLabel = updateCategories.first { $0.key == categoryKey }?.label ?? "未分类文件"

  return RilinicFileInfo(
    ossPath: ossPath,
    deployRelativePath: relativePath,
    displayName: buildDisplayName(relativePath: relativePath, fileName: fn),
    categoryKey: categoryKey,
    categoryLabel: categoryLabel,
    fileName: fn,
    size: (fileInfo["size"] as? NSNumber)?.int64Value ?? 0,
    lastModified: (fileInfo["lastModified"] as? NSNumber)?.int64Value ?? 0,
    objectKey: (fileInfo["objectKey"] as? String) ?? ossPath,
    rawData: fileInfo
  )
}

/// 对文件列表按分类排序
func sortByCategory(_ files: [RilinicFileInfo]) -> [RilinicFileInfo] {
  return files.sorted { a, b in
    let orderA = categoryOrder[a.categoryKey] ?? 99
    let orderB = categoryOrder[b.categoryKey] ?? 99
    if orderA != orderB { return orderA < orderB }
    return a.deployRelativePath < b.deployRelativePath
  }
}