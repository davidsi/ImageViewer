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

    // Local folder mode keys
    private let localFolderBookmarkKey = "localFolderBookmark"
    private let isLocalModeKey = "isLocalMode"

    /// When true, all storage operations use the local folder instead of Dropbox
    @Published var isLocalMode: Bool {
        didSet { userDefaults.set(isLocalMode, forKey: isLocalModeKey) }
    }

    /// Security-scoped bookmark data for the chosen local folder
    private var localFolderBookmark: Data? {
        didSet {
            if let data = localFolderBookmark {
                userDefaults.set(data, forKey: localFolderBookmarkKey)
            } else {
                userDefaults.removeObject(forKey: localFolderBookmarkKey)
            }
        }
    }

    /// The resolved URL for the local folder (resolved from bookmark each time)
    var localFolderURL: URL? {
        get {
            guard let bookmark = localFolderBookmark else { return nil }
            var isStale = false
            #if os(macOS)
            return try? URL(resolvingBookmarkData: bookmark,
                            options: .withSecurityScope,
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale)
            #else
            return nil
            #endif
        }
    }

    /// Persist a security-scoped bookmark for the chosen URL (macOS only)
    func setLocalFolderURL(_ url: URL) {
        #if os(macOS)
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) else {
            print("⚠️ UserSettings: Failed to create security-scoped bookmark for \(url.path)")
            return
        }
        localFolderBookmark = bookmark
        isLocalMode = true
        #endif
    }

    func clearLocalFolder() {
        localFolderBookmark = nil
        isLocalMode = false
    }

    /// Disable local mode but KEEP the bookmark so the user can re-enable without re-picking
    func disableLocalMode() {
        isLocalMode = false
    }

    /// Re-enable local mode with the previously chosen folder (if still available)
    func enableLocalMode() {
        guard localFolderBookmark != nil else { return }
        isLocalMode = true
    }

    var hasLocalFolder: Bool { localFolderBookmark != nil }
    
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
        isLocalMode = userDefaults.bool(forKey: isLocalModeKey)
        localFolderBookmark = userDefaults.data(forKey: localFolderBookmarkKey)
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
