//
//  RilinicNetworkClient.swift
//  Squirrel
//
//  API 网络层：登录、文件列表、下载链接
//

import Foundation

// MARK: - 后端配置

enum RilinicAPI {
  static var baseURL: String {
    return ProcessInfo.processInfo.environment["RILINIC_BASE_URL"]
        ?? "https://backend2.beginner.center"
  }

  static var loginURL: URL {
    return URL(string: "\(baseURL)/api/auth/login")!
  }

  static var filesURL: URL {
    return URL(string: "\(baseURL)/api/oss/rilinic/files")!
  }

  static var downloadUrlsURL: URL {
    return URL(string: "\(baseURL)/api/oss/rilinic/downloadUrls")!
  }
}

// MARK: - 错误类型

enum RilinicNetworkError: Error, LocalizedError {
  case invalidResponse
  case httpError(code: Int, message: String)
  case tokenExpired(String)
  case notFound(String)
  case noData
  case parseError(String)
  case serverMessage(String)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "服务器响应无效"
    case .httpError(let code, let message):
      return "服务器错误 (\(code)): \(message)"
    case .tokenExpired(let msg):
      return msg
    case .notFound(let msg):
      return msg
    case .noData:
      return "服务器未返回数据"
    case .parseError(let msg):
      return "数据解析失败: \(msg)"
    case .serverMessage(let msg):
      return msg
    }
  }
}

// MARK: - API 响应模型

struct LoginResponse {
  let success: Bool
  let token: String?
  let message: String?
}

struct FilesResponse {
  let success: Bool
  let files: [[String: Any]]
  let count: Int
  let bucketName: String?
  let prefix: String?
  let message: String?
}

struct DownloadUrlsResponse {
  let success: Bool
  let files: [DownloadFileInfo]
  let message: String?
}

struct DownloadFileInfo {
  let objectKey: String
  let downloadUrl: String
  let fileName: String?
  let hash: String?
}

// MARK: - API Client

final class RilinicNetworkClient {
  private let session: URLSession
  private var token: String?

  init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 30
    self.session = URLSession(configuration: config)
  }

  // MARK: - 登录

  func login(account: String, password: String,
             completion: @escaping (Result<LoginResponse, Error>) -> Void) {
    var request = URLRequest(url: RilinicAPI.loginURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: String] = ["account": account, "password": password]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    session.dataTask(with: request) { data, response, error in
      if let error = error {
        completion(.failure(error))
        return
      }

      guard let httpResponse = response as? HTTPURLResponse else {
        completion(.failure(RilinicNetworkError.invalidResponse))
        return
      }

      guard let data = data else {
        completion(.failure(RilinicNetworkError.noData))
        return
      }

      guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        completion(.failure(RilinicNetworkError.parseError("响应不是有效的 JSON")))
        return
      }

      if httpResponse.statusCode == 200 {
        let success = json["success"] as? Bool ?? false
        let token = json["token"] as? String
        let message = json["message"] as? String
        if success, let token = token {
          self.token = token
        }
        completion(.success(LoginResponse(success: success, token: token, message: message)))
      } else {
        let msg = json["message"] as? String ?? "请检查账号和密码"
        completion(.failure(RilinicNetworkError.serverMessage(msg)))
      }
    }.resume()
  }

  // MARK: - 获取文件列表

  func fetchFiles(token: String,
                  completion: @escaping (Result<FilesResponse, Error>) -> Void) {
    var request = URLRequest(url: RilinicAPI.filesURL)
    request.httpMethod = "GET"
    request.setValue(token, forHTTPHeaderField: "Authorization")

    session.dataTask(with: request) { data, response, error in
      if let error = error {
        completion(.failure(error))
        return
      }

      guard let httpResponse = response as? HTTPURLResponse else {
        completion(.failure(RilinicNetworkError.invalidResponse))
        return
      }

      guard let data = data else {
        completion(.failure(RilinicNetworkError.noData))
        return
      }

      if httpResponse.statusCode == 401 {
        let msg = self.parseMessage(from: data) ?? "您的登录凭证已失效，请重新登录"
        completion(.failure(RilinicNetworkError.tokenExpired(msg)))
        return
      }

      if httpResponse.statusCode == 404 {
        completion(.failure(RilinicNetworkError.notFound("后端未部署 OSS 文件列表接口")))
        return
      }

      guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        completion(.failure(RilinicNetworkError.parseError("响应不是有效的 JSON")))
        return
      }

      if httpResponse.statusCode != 200 {
        let msg = self.parseMessage(from: data) ?? "服务器错误 (\(httpResponse.statusCode))"
        completion(.failure(RilinicNetworkError.httpError(code: httpResponse.statusCode, message: msg)))
        return
      }

      let success = json["success"] as? Bool ?? false
      if !success {
        let msg = json["message"] as? String ?? "获取文件列表失败"
        completion(.failure(RilinicNetworkError.serverMessage(msg)))
        return
      }

      let files = (json["files"] as? [[String: Any]]) ?? []
      let count = json["count"] as? Int ?? files.count
      let bucketName = json["bucketName"] as? String
      let prefix = json["prefix"] as? String

      completion(.success(FilesResponse(
        success: true, files: files, count: count,
        bucketName: bucketName, prefix: prefix, message: nil
      )))
    }.resume()
  }

  // MARK: - 获取下载链接

  func fetchDownloadURLs(token: String, objectKeys: [String],
                         completion: @escaping (Result<DownloadUrlsResponse, Error>) -> Void) {
    var request = URLRequest(url: RilinicAPI.downloadUrlsURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: "Authorization")

    let body: [String: Any] = ["objectKeys": objectKeys, "expireMinutes": 30]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    session.dataTask(with: request) { data, response, error in
      if let error = error {
        completion(.failure(error))
        return
      }

      guard let httpResponse = response as? HTTPURLResponse else {
        completion(.failure(RilinicNetworkError.invalidResponse))
        return
      }

      guard let data = data else {
        completion(.failure(RilinicNetworkError.noData))
        return
      }

      if httpResponse.statusCode == 401 {
        let msg = self.parseMessage(from: data) ?? "登录已过期"
        completion(.failure(RilinicNetworkError.tokenExpired(msg)))
        return
      }

      if httpResponse.statusCode == 404 {
        completion(.failure(RilinicNetworkError.notFound("后端未找到 OSS 下载链接接口")))
        return
      }

      guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        completion(.failure(RilinicNetworkError.parseError("响应不是有效的 JSON")))
        return
      }

      if httpResponse.statusCode != 200 {
        let msg = self.parseMessage(from: data) ?? "服务器错误"
        completion(.failure(RilinicNetworkError.serverMessage(msg)))
        return
      }

      let success = json["success"] as? Bool ?? false
      if !success {
        let msg = json["message"] as? String ?? "无权限下载"
        completion(.failure(RilinicNetworkError.serverMessage(msg)))
        return
      }

      let fileList = json["files"] as? [[String: Any]] ?? []
      let downloadFiles = fileList.map { item -> DownloadFileInfo in
        return DownloadFileInfo(
          objectKey: item["objectKey"] as? String ?? "",
          downloadUrl: item["downloadUrl"] as? String ?? "",
          fileName: item["fileName"] as? String,
          hash: item["hash"] as? String
        )
      }

      completion(.success(DownloadUrlsResponse(
        success: true, files: downloadFiles, message: nil
      )))
    }.resume()
  }

  // MARK: - 辅助

  private func parseMessage(from data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    return json["message"] as? String
  }
}