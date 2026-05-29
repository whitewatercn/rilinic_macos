//
//  RilinicDownloadManager.swift
//  Squirrel
//
//  流式下载管理，支持断点续传、SHA256 校验、取消
//

import Foundation
import CommonCrypto

final class RilinicDownloadManager {
  private var downloadTask: URLSessionDataTask?
  private var isCancelled = false

  typealias ProgressHandler = (Double) -> Void
  typealias CompletionHandler = (Result<URL, Error>) -> Void

  func download(from url: URL, to destination: URL,
                expectedHash: String? = nil,
                resume: Bool = true,
                progress: @escaping ProgressHandler,
                completion: @escaping CompletionHandler) {
    isCancelled = false

    var request = URLRequest(url: url)
    request.timeoutInterval = 30

    var downloadedSize: Int64 = 0
    let fileManager = FileManager.default

    // 断点续传
    if resume, fileManager.fileExists(atPath: destination.path) {
      if let attrs = try? fileManager.attributesOfItem(atPath: destination.path) {
        downloadedSize = (attrs[.size] as? Int64) ?? 0
      }
      if downloadedSize > 0 {
        request.setValue("bytes=\(downloadedSize)-", forHTTPHeaderField: "Range")
      }
    }

    let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)

    downloadTask = session.dataTask(with: request) { [weak self] data, response, error in
      guard let self = self else { return }

      if self.isCancelled {
        completion(.failure(NSError(domain: "RilinicDownload", code: -999, userInfo: [NSLocalizedDescriptionKey: "下载已取消"])))
        return
      }

      if let error = error {
        completion(.failure(error))
        return
      }

      guard let httpResponse = response as? HTTPURLResponse else {
        completion(.failure(NSError(domain: "RilinicDownload", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的服务器响应"])))
        return
      }

      guard httpResponse.statusCode == 200 || httpResponse.statusCode == 206 else {
        completion(.failure(NSError(domain: "RilinicDownload", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "服务器返回错误: \(httpResponse.statusCode)"])))
        return
      }

      guard let data = data else {
        completion(.failure(NSError(domain: "RilinicDownload", code: -2, userInfo: [NSLocalizedDescriptionKey: "未收到数据"])))
        return
      }

      // 计算总大小
      var totalSize: Int64 = 0
      if httpResponse.statusCode == 206 {
        // 断点续传: Content-Range: bytes X-Y/Z
        if let contentRange = httpResponse.allHeaderFields["Content-Range"] as? String,
           let totalStr = contentRange.components(separatedBy: "/").last,
           let total = Int64(totalStr) {
          totalSize = total
        }
      } else if let contentLength = (httpResponse.allHeaderFields["Content-Length"] as? String).flatMap(Int64.init) {
        totalSize = contentLength
      }

      // 写入文件
      do {
        if httpResponse.statusCode != 206 || downloadedSize == 0 {
          try data.write(to: destination)
        } else {
          let fileHandle = try FileHandle(forWritingTo: destination)
          fileHandle.seekToEndOfFile()
          fileHandle.write(data)
          fileHandle.closeFile()
        }

        // SHA256 校验
        if let hash = expectedHash {
          let computed = self.sha256(of: destination)
          if computed.lowercased() != hash.lowercased() {
            try? fileManager.removeItem(at: destination)
            completion(.failure(NSError(domain: "RilinicDownload", code: -3, userInfo: [NSLocalizedDescriptionKey: "哈希校验失败: 期望 \(hash), 实际 \(computed)"])))
            return
          }
        }

        completion(.success(destination))
      } catch {
        completion(.failure(error))
      }
    }

    // 进度回调
    let observation = downloadTask?.progress.observe(\.fractionCompleted, options: [.new]) { prog, _ in
      DispatchQueue.main.async {
        progress(prog.fractionCompleted)
      }
    }

    downloadTask?.resume()
  }

  func cancel() {
    isCancelled = true
    downloadTask?.cancel()
  }

  // MARK: - SHA256

  private func sha256(of url: URL) -> String {
    guard let data = try? Data(contentsOf: url) else { return "" }
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { bytes in
      _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
  }
}