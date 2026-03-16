//
//  UserSettings.swift
//  ImageView
//
//  Created by david silver on 2026-03-15.
//

import Foundation
import Combine

class UserSettings: ObservableObject {
    private let userDefaults = UserDefaults.standard
    
    // Dropbox credentials keys
    private let dropboxAccessTokenKey = "dropboxAccessToken"
    private let dropboxRefreshTokenKey = "dropboxRefreshToken"
    private let dropboxUserIdKey = "dropboxUserId"
    
    @Published var dropboxAccessToken: String? {
        didSet {
            if let token = dropboxAccessToken {
                userDefaults.set(token, forKey: dropboxAccessTokenKey)
            } else {
                userDefaults.removeObject(forKey: dropboxAccessTokenKey)
            }
        }
    }
    
    @Published var dropboxRefreshToken: String? {
        didSet {
            if let token = dropboxRefreshToken {
                userDefaults.set(token, forKey: dropboxRefreshTokenKey)
            } else {
                userDefaults.removeObject(forKey: dropboxRefreshTokenKey)
            }
        }
    }
    
    @Published var dropboxUserId: String? {
        didSet {
            if let userId = dropboxUserId {
                userDefaults.set(userId, forKey: dropboxUserIdKey)
            } else {
                userDefaults.removeObject(forKey: dropboxUserIdKey)
            }
        }
    }
    
    static let shared = UserSettings()
    
    private init() {
        // Load existing credentials
        loadCredentials()
    }
    
    private func loadCredentials() {
        dropboxAccessToken = userDefaults.string(forKey: dropboxAccessTokenKey)
        dropboxRefreshToken = userDefaults.string(forKey: dropboxRefreshTokenKey)
        dropboxUserId = userDefaults.string(forKey: dropboxUserIdKey)
    }
    
    func hasDropboxCredentials() -> Bool {
        return dropboxAccessToken != nil && !dropboxAccessToken!.isEmpty
    }
    
    func clearDropboxCredentials() {
        print("🗑️ UserSettings: Clearing all Dropbox credentials from UserDefaults")
        dropboxAccessToken = nil
        dropboxRefreshToken = nil
        dropboxUserId = nil
        
        // Also explicitly remove from UserDefaults to be thorough
        userDefaults.removeObject(forKey: dropboxAccessTokenKey)
        userDefaults.removeObject(forKey: dropboxRefreshTokenKey) 
        userDefaults.removeObject(forKey: dropboxUserIdKey)
        userDefaults.synchronize()
        
        print("🗑️ UserSettings: All Dropbox credentials cleared and synchronized")
    }
    
    func saveDropboxCredentials(accessToken: String, refreshToken: String?, userId: String?) {
        dropboxAccessToken = accessToken
        dropboxRefreshToken = refreshToken
        dropboxUserId = userId
    }
}
