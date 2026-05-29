//
//  RilinicTokenStorage.swift
//  Squirrel
//
//  Token 持久化存储，使用 UserDefaults
//

import Foundation

final class RilinicTokenStorage {
  private static let tokenKey = "RilinicAuthToken"

  static func save(token: String) {
    UserDefaults.standard.set(token, forKey: tokenKey)
    print("Rilinic: token saved")
  }

  static func load() -> String? {
    return UserDefaults.standard.string(forKey: tokenKey)
  }

  static func delete() {
    UserDefaults.standard.removeObject(forKey: tokenKey)
    print("Rilinic: token deleted")
  }

  static var hasToken: Bool {
    return load() != nil
  }
}