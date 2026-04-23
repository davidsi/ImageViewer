//
//  DropboxService.swift
//  ImageView
//
//  Created by david silver on 2026-03-15.
//

import Foundation
import SwiftyDropbox
import Combine

// Import Dropbox Files module for metadata types
typealias Files = SwiftyDropbox.Files

class DropboxService: ObservableObject {
    static let shared = DropboxService()
    
    private let inspirationFolder = ""  // Root of app's allocated space
    private let keywordsFileName = "keywords.json"
    private let userSettings = UserSettings.shared
    
    // Cached keyword tree to avoid repeated Dropbox calls
    @Published var cachedKeywordTree: KeywordTree?
    @Published var cachedGroups: [[String]] = []
    private var keywordTreeLoadTask: Task<KeywordTree, Error>?
    
    private init() {}

    // MARK: - Local Folder Mode helpers

    var isLocalMode: Bool { userSettings.isLocalMode }

    /// Access the security-scoped local folder URL, starting access if needed.
    /// Callers must call `stopLocalFolderAccess()` when done.
    private func localFolderURL() -> URL? {
        guard let url = userSettings.localFolderURL else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    private func stopLocalFolderAccess() {
        userSettings.localFolderURL?.stopAccessingSecurityScopedResource()
    }

    private var localKeywordsFileURL: URL? {
        localFolderURL()?.appendingPathComponent(keywordsFileName)
    }

    private func localImageURL(filename: String) -> URL? {
        localFolderURL()?.appendingPathComponent(filename)
    }

    // MARK: - Local fetchImageList
    private func localFetchImageList() throws -> [ImageMetadata] {
        guard let folder = localFolderURL() else { throw DropboxError.notAuthenticated }
        defer { stopLocalFolderAccess() }
        let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp", "heic", "heif"]
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: folder,
                                                   includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                                   options: .skipsHiddenFiles)
        return contents.compactMap { url -> ImageMetadata? in
            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { return nil }
            let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return ImageMetadata(
                filename: url.lastPathComponent,
                title: nil,
                dropboxPath: url.path,
                fileSize: Int64(attrs?.fileSize ?? 0),
                lastModified: attrs?.contentModificationDate ?? Date.distantPast,
                contentHash: nil,
                keywords: nil
            )
        }
        .sorted { $0.lastModified > $1.lastModified }
    }

    // MARK: - Local fetchKeywords
    private func localFetchKeywords() throws -> KeywordTree {
        guard let url = localKeywordsFileURL else { throw DropboxError.notAuthenticated }
        defer { stopLocalFolderAccess() }
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Return empty tree if no keywords file yet
            return KeywordTree()
        }
        let data = try Data(contentsOf: url)
        if let keywordData = try? JSONDecoder().decode(KeywordData.self, from: data) {
            DispatchQueue.main.async { self.cachedGroups = keywordData.Groups }
            return keywordData.Keywords
        }
        return try JSONDecoder().decode(KeywordTree.self, from: data)
    }

    // MARK: - Local saveKeywords
    private func localSaveKeywords(_ keywordTree: KeywordTree) throws {
        guard let url = localKeywordsFileURL else { throw DropboxError.notAuthenticated }
        defer { stopLocalFolderAccess() }
        let keywordData = KeywordData(keywordTree: keywordTree, groups: cachedGroups)
        let data = try JSONEncoder().encode(keywordData)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Local uploadImage
    private func localUploadImage(imageData: Data, filename: String) throws -> String {
        guard let folder = localFolderURL() else { throw DropboxError.notAuthenticated }
        defer { stopLocalFolderAccess() }
        let fm = FileManager.default
        var finalFilename = filename
        var counter = 1
        let nameComponents = filename.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let base = String(nameComponents.first ?? "")
        let ext = nameComponents.count > 1 ? ".\(nameComponents[1])" : ""
        while fm.fileExists(atPath: folder.appendingPathComponent(finalFilename).path) {
            finalFilename = "\(base)-\(counter)\(ext)"
            counter += 1
        }
        try imageData.write(to: folder.appendingPathComponent(finalFilename), options: .atomic)
        return finalFilename
    }

    // MARK: - Local downloadImageData
    private func localDownloadImageData(path: String) throws -> Data? {
        // path is the full file path when in local mode
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    // MARK: - Local deleteImages
    private func localDeleteImages(filenames: [String]) throws {
        guard let folder = localFolderURL() else { throw DropboxError.notAuthenticated }
        defer { stopLocalFolderAccess() }
        let fm = FileManager.default
        for filename in filenames {
            let url = folder.appendingPathComponent(filename)
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }
    }
    private func dropboxPath(_ components: String...) -> String {
        let nonEmptyComponents = components.filter { !$0.isEmpty }
        let joinedPath = nonEmptyComponents.joined(separator: "/")
        
        // Dropbox API requires paths to start with "/"
        if joinedPath.isEmpty {
            return "/"
        } else {
            return "/\(joinedPath)"
        }
    }
    
    // MARK: - Token Management
    
    func isAuthenticated() -> Bool {
        if userSettings.isLocalMode { return userSettings.localFolderURL != nil }
        return DropboxClientsManager.authorizedClient != nil
    }
    
    /// Completely clear all Dropbox authentication and force re-authentication
    func forceReauthentication() {
        print("🔄 Dropbox: Forcing complete re-authentication...")
        
        // Clear the client
        DropboxClientsManager.unlinkClients()
        DropboxClientsManager.authorizedClient = nil
        
        // Clear any stored credentials
        userSettings.clearDropboxCredentials()
        
        // Clear any cached tokens from keychain
        if let bundleId = Bundle.main.bundleIdentifier {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: bundleId + ".dropbox"
            ]
            let deleteResult = SecItemDelete(query as CFDictionary)
            print("🔄 Dropbox: Keychain clear result: \(deleteResult)")
        }
        
        // Also clear any SwiftyDropbox specific stored tokens
        UserDefaults.standard.removeObject(forKey: "dropbox_access_token")
        UserDefaults.standard.removeObject(forKey: "dropbox_refresh_token") 
        UserDefaults.standard.removeObject(forKey: "dropbox_token_uid")
        UserDefaults.standard.synchronize()
        
        print("🔄 Dropbox: All authentication data cleared. Please re-authenticate.")
    }
    
    /// Debug method to check what permissions the current token has
    func debugTokenPermissions() async {
        guard let client = DropboxClientsManager.authorizedClient else {
            print("🔍 Token Debug: No authorized client available")
            return
        }
        
        print("🔍 Token Debug: Testing various API endpoints to determine token scope...")
        
        // Test files.metadata.read (should work)
        print("🔍 Token Debug: Testing files.metadata.read scope...")
        client.files.listFolder(path: "").response { result, error in
            if result != nil {
                print("🔍 Token Debug: ✅ files.metadata.read - WORKING")
            } else {
                print("🔍 Token Debug: ❌ files.metadata.read - FAILED: \(String(describing: error))")
            }
        }
        
        // Test files.content.read (should fail based on errors)
        print("🔍 Token Debug: Testing files.content.read scope...")
        client.files.download(path: "/keywords.json").response { result, error in
            if result != nil {
                print("🔍 Token Debug: ✅ files.content.read - WORKING")
            } else {
                print("🔍 Token Debug: ❌ files.content.read - FAILED: \(String(describing: error))")
            }
        }
        
        // Test files.content.write (should work based on successful uploads)
        print("🔍 Token Debug: files.content.write appears to be working (uploads succeed)")
        
        print("🔍 Token Debug: Summary - Your token seems to have files.metadata.* and files.content.write but NOT files.content.read")
    }
    
    private func handleExpiredToken() async throws {
        print("📂 Dropbox: Handling expired token - clearing client and requiring re-authentication")
        
        await MainActor.run {
            // Clear the current authentication state
            userSettings.clearDropboxCredentials()
            DropboxClientsManager.unlinkClients() 
            DropboxClientsManager.authorizedClient = nil
        }
        
        // Throw specific token expired error for better UI handling
        throw DropboxError.tokenExpired
    }
    
    private func isExpiredTokenError(_ error: Error) -> Bool {
        let errorString = String(describing: error)
        return errorString.contains("expired_access_token") || errorString.contains("invalid_access_token")
    }
    
    private func executeWithTokenRefresh<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            if isExpiredTokenError(error) {
                print("📂 Dropbox: Detected expired token, clearing authentication state...")
                try await handleExpiredToken()
                // Re-throw the specific token expired error for the UI to handle
                throw DropboxError.tokenExpired
            } else {
                throw error
            }
        }
    }
    
    // Test basic connectivity to Dropbox
    func testConnectivity() async -> Bool {
        print("📂 Test: Starting connectivity test...")
        print("📂 Test: Current thread: \(Thread.current)")
        
        // Check if DropboxClientsManager is initialized at all
        print("📂 Test: DropboxClientsManager class: \(String(describing: DropboxClientsManager.self))")
        
        // Check if we have an authorized client
        print("📂 Test: Checking DropboxClientsManager.authorizedClient...")
        let authorizedClient = DropboxClientsManager.authorizedClient
        print("📂 Test: DropboxClientsManager.authorizedClient = \(String(describing: authorizedClient))")
        
        guard let client = authorizedClient else {
            print("📂 Test: ❌ No authorized client available")
            print("📂 Test: ❌ DropboxClientsManager.authorizedClient is nil")
            
            // Check if there are any clients at all
            print("📂 Test: Checking if SDK is initialized...")
            
            return false
        }
        
        print("📂 Test: ✅ Authorized client exists: \(String(describing: client))")
        print("📂 Test: Client type: \(type(of: client))")
        
        // Test token scopes by trying to get current account info
        do {
            return try await withCheckedThrowingContinuation { continuation in
                print("📂 Test: About to make getCurrentAccount API call...")
                
                let request = client.users.getCurrentAccount()
                print("📂 Test: Created request: \(String(describing: request))")
                
                request.response { result, error in
                    print("📂 Test: Received response in callback")
                    print("📂 Test: Result: \(String(describing: result))")
                    print("📂 Test: Error: \(String(describing: error))")
                    
                    if let result = result {
                        print("📂 Test: ✅ Connectivity successful - User: \(result.name.displayName)")
                        
                        // Now test if we can download a file to check scopes
                        print("📂 Test: Testing file download capabilities...")
                        let testRequest = client.files.download(path: "/keywords.json")
                        testRequest.response { downloadResult, downloadError in
                            if downloadResult != nil {
                                print("📂 Test: ✅ files.content.read scope confirmed - can download files")
                            } else if let downloadError = downloadError {
                                print("📂 Test: ❌ files.content.read scope issue: \(downloadError)")
                                print("📂 Test: ❌ This confirms the token lacks required scopes")
                            }
                        }
                        
                        continuation.resume(returning: true)
                    } else if let error = error {
                        print("📂 Test: ❌ Connectivity failed with error: \(error)")
                        print("📂 Test: ❌ Error type: \(type(of: error))")
                        print("📂 Test: ❌ Error description: \(error.description)")
                        print("📂 Test: ❌ Localized description: \(error.localizedDescription)")
                        continuation.resume(returning: false)
                    } else {
                        print("📂 Test: ❌ Connectivity failed: Unknown error (no result and no error)")
                        continuation.resume(returning: false)
                    }
                }
                
                print("📂 Test: API call initiated, waiting for response...")
            }
        } catch {
            print("📂 Test: ❌ Exception during connectivity test: \(error)")
            print("📂 Test: ❌ Exception type: \(type(of: error))")
            return false
        }
    }
    
    // Debug method to explore folder structure
    func exploreDropboxStructure() async {
        guard let client = DropboxClientsManager.authorizedClient else {
            print("📂 Explore: No authorized client")
            return
        }
        
        print("📂 Explore: Checking root directory...")
        await listDirectoryContents(client: client, path: "")
        
        print("📂 Explore: Checking /apps directory...")
        await listDirectoryContents(client: client, path: "/apps")
    }
    
    private func listDirectoryContents(client: DropboxClient, path: String) async {
        await withCheckedContinuation { continuation in
            client.files.listFolder(path: path).response { result, error in
                if let result = result {
                    print("📂 Explore: Contents of '\(path)':")
                    for entry in result.entries {
                        if let folderEntry = entry as? Files.FolderMetadata {
                            print("  📁 \(folderEntry.name) (folder)")
                        } else if let fileEntry = entry as? Files.FileMetadata {
                            print("  📄 \(fileEntry.name) (file)")
                        }
                    }
                } else if let error = error {
                    print("📂 Explore: Error listing '\(path)': \(error)")
                }
                continuation.resume()
            }
        }
    }
    
    // MARK: - File Listing
    
    func fetchImageList() async throws -> [ImageMetadata] {
        if userSettings.isLocalMode { return try localFetchImageList() }
        return try await executeWithTokenRefresh {
            guard let client = DropboxClientsManager.authorizedClient else {
                print("❌ Dropbox: No authorized client available")
                throw DropboxError.notAuthenticated
            }
            
            print("📂 Dropbox: Client exists, fetching files from \(self.inspirationFolder)")
            print("📂 Dropbox: Client description: \(String(describing: client))")
            
            // First try to list the folder, if it fails, try to create it
            return try await withCheckedThrowingContinuation { continuation in
                client.files.listFolder(path: self.inspirationFolder.isEmpty ? "" : self.inspirationFolder).response { result, error in
                    if let result = result {
                        let imageMetadata = self.processFileList(result.entries)
                        print("📂 Dropbox: Found \(imageMetadata.count) images")
                        continuation.resume(returning: imageMetadata)
                    } else if let error = error {
                        print("📂 Dropbox: Error listing files: \(error)")
                        print("📂 Dropbox: Error type: \(type(of: error))")
                        print("📂 Dropbox: Error localizedDescription: \(error.localizedDescription)")
                        
                        // Check if it's a "not found" error and try to create the folder
                        let errorString = error.description
                        if errorString.contains("not_found") {
                            print("📂 Dropbox: Folder not found, attempting to create it...")
                            self.createFolderAndRetry(client: client, continuation: continuation)
                        } else {
                            continuation.resume(throwing: DropboxError.apiError(error.description))
                        }
                    } else {
                        print("📂 Dropbox: Unknown error - no result and no error")
                        continuation.resume(throwing: DropboxError.unknown)
                    }
                }
            }
        }
    }
    
    private func createFolderAndRetry(client: DropboxClient, continuation: CheckedContinuation<[ImageMetadata], Error>) {
        // Since we're using the root of the app space, the folder already exists
        // Just return empty list for a clean start
        print("📂 Dropbox: Using app root space, no need to create folder")
        continuation.resume(returning: [])
    }
    
    private func processFileList(_ entries: [Files.Metadata]) -> [ImageMetadata] {
        let supportedExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp", "heic", "heif"]
        
        return entries.compactMap { entry in
            guard let fileMetadata = entry as? Files.FileMetadata else { return nil }
            
            let filename = fileMetadata.name
            let fileExtension = filename.lowercased().split(separator: ".").last?.description ?? ""
            
            // Only process supported image files
            guard supportedExtensions.contains(fileExtension) else { return nil }
            
            return ImageMetadata(
                filename: filename,
                title: extractTitleFromFilename(filename),
                dropboxPath: fileMetadata.pathLower ?? fileMetadata.pathDisplay ?? "",
                fileSize: Int64(fileMetadata.size),
                lastModified: fileMetadata.serverModified,
                contentHash: fileMetadata.contentHash,
                keywords: nil
            )
        }
        .sorted { $0.lastModified > $1.lastModified } // Most recent first
    }
    
    private func extractTitleFromFilename(_ filename: String) -> String? {
        // Remove file extension and clean up common naming patterns
        let nameWithoutExtension = filename.replacingOccurrences(of: "\\.[^.]*$", with: "", options: .regularExpression)
        
        // Skip if it looks like a generic filename (IMG_1234, DSC_5678, etc.)
        if nameWithoutExtension.matches("^(IMG_|DSC_|PHOTO_|IMAGE_)\\d+$") {
            return nil
        }
        
        // Clean up underscores and hyphens
        return nameWithoutExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
    
    // MARK: - Keywords
    
    func fetchKeywords() async throws -> KeywordTree {
        // Check cache first
        if let cached = cachedKeywordTree {
            print("📂 Dropbox: Using cached keyword tree")
            return cached
        }

        if userSettings.isLocalMode {
            let tree = try localFetchKeywords()
            await MainActor.run { cachedKeywordTree = tree }
            return tree
        }

        let keywordTree = try await executeWithTokenRefresh {
            guard let client = DropboxClientsManager.authorizedClient else {
                throw DropboxError.notAuthenticated
            }
            
            let keywordsPath = self.dropboxPath(self.inspirationFolder, self.keywordsFileName)
            print("📂 Dropbox: Fetching keywords from '\(keywordsPath)'")
            
            return try await withCheckedThrowingContinuation { continuation in
                client.files.download(path: keywordsPath).response { result, error in
                    if let result = result {
                        // First, let's examine the raw JSON structure
                        if let jsonString = String(data: result.1, encoding: .utf8) {
                            print("📂 Dropbox: Raw JSON content:")
                            print(jsonString)
                        }
                        
                        do {
                            // Try new KeywordData format first
                            let keywordData = try JSONDecoder().decode(KeywordData.self, from: result.1)
                            print("📂 Dropbox: Successfully loaded keywords with new KeywordData format")
                            
                            // Cache both keywords and groups
                            Task { @MainActor in
                                self.cachedGroups = keywordData.Groups
                                print("📂 Dropbox: Cached \(keywordData.Groups.count) groups")
                            }
                            
                            continuation.resume(returning: keywordData.Keywords)
                        } catch {
                            print("📂 Dropbox: New format failed, trying legacy KeywordTree format: \(error)")
                            do {
                                // Fall back to old KeywordTree format for backward compatibility
                                let keywordTree = try JSONDecoder().decode(KeywordTree.self, from: result.1)
                                print("📂 Dropbox: Successfully loaded keywords with legacy KeywordTree format")
                                
                                // Initialize empty groups for legacy format
                                Task { @MainActor in
                                    self.cachedGroups = []
                                    print("📂 Dropbox: Initialized empty groups for legacy format")
                                }
                                
                                continuation.resume(returning: keywordTree)
                            } catch {
                                print("📂 Dropbox: Error parsing keywords JSON with both formats: \(error)")
                                continuation.resume(throwing: DropboxError.apiError("Invalid keywords file format"))
                            }
                        }
                    } else if let error = error {
                        print("📂 Dropbox: Keywords file not found: \(error)")
                        print("📂 Dropbox: Creating default keywords file with root 'keywords' node")
                        
                        // Create default keywords tree with root "keywords" node
                        var defaultTree = KeywordTree()
                        // The defaultTree already has the correct structure with keywords.children as empty array
                        
                        continuation.resume(returning: defaultTree)
                        
                        // Save the default tree to Dropbox asynchronously (don't wait for it)
                        Task {
                            do {
                                try await self.saveKeywords(defaultTree)
                                print("📂 Dropbox: Successfully created default keywords file with new KeywordData format (Keywords + Groups)")
                            } catch {
                                print("📂 Dropbox: Failed to create default keywords file: \(error)")
                            }
                        }
                    } else {
                        continuation.resume(throwing: DropboxError.unknown)
                    }
                }
            }
        }
        
        // Cache the fetched result
        await MainActor.run {
            cachedKeywordTree = keywordTree
        }
        print("📂 Dropbox: Cached keyword tree")
        
        return keywordTree
    }
    
    // MARK: - Keywords Save
    
    func saveKeywords(_ keywordTree: KeywordTree) async throws {
        if userSettings.isLocalMode {
            try localSaveKeywords(keywordTree)
            await MainActor.run { cachedKeywordTree = keywordTree }
            return
        }
        try await executeWithTokenRefresh {
            guard let client = DropboxClientsManager.authorizedClient else {
                print("📂 Dropbox: Not authenticated, cannot save keywords")
                throw DropboxError.notAuthenticated
            }
            
            let keywordsPath = self.dropboxPath(self.inspirationFolder, self.keywordsFileName)
            print("📂 Dropbox: Attempting to save keywords to path: '\(keywordsPath)'")
            print("📂 Dropbox: Folder: '\(self.inspirationFolder)', Filename: '\(self.keywordsFileName)'")
            
            do {
                // Wrap the keywordTree in the new KeywordData structure with current cached groups
                let keywordData = KeywordData(keywordTree: keywordTree, groups: self.cachedGroups)
                let jsonData = try JSONEncoder().encode(keywordData)
                print("📂 Dropbox: Encoded \(jsonData.count) bytes of keyword data with new KeywordData format (Keywords + Groups)")
                print("📂 Dropbox: Saving \(self.cachedGroups.count) groups with keywords")
                
                // Debug: Show structure of new JSON format
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("📂 Dropbox: New JSON structure preview (first 200 chars):")
                    print(String(jsonString.prefix(200)) + (jsonString.count > 200 ? "..." : ""))
                }
                
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    print("📂 Dropbox: Starting upload to '\(keywordsPath)'...")
                    client.files.upload(
                        path: keywordsPath,
                        mode: Files.WriteMode.overwrite,
                        input: jsonData
                    ).response { result, error in
                        if let result = result {
                            print("📂 Dropbox: Upload completed successfully")
                            print("📂 Dropbox: Result details: \(result)")
                            continuation.resume()
                        } else if let error = error {
                            print("📂 Dropbox: Upload failed with error: \(error)")
                            continuation.resume(throwing: DropboxError.apiError(error.description))
                        } else {
                            print("📂 Dropbox: Upload failed with unknown error")
                            continuation.resume(throwing: DropboxError.unknown)
                        }
                    }
                }
                print("📂 Dropbox: Keywords save operation completed successfully")
                
                // Update the cached keyword tree after successful save
                await MainActor.run {
                    self.cachedKeywordTree = keywordTree
                    print("📂 Dropbox: Updated cached keyword tree after save")
                }
            } catch {
                print("📂 Dropbox: Keywords save failed: \(error.localizedDescription)")
                throw DropboxError.apiError("Failed to encode keywords: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Image Upload
    
    func uploadImage(imageData: Data, filename: String, title: String?) async throws -> String {
        if userSettings.isLocalMode { return try localUploadImage(imageData: imageData, filename: filename) }
        return try await executeWithTokenRefresh {
            guard let client = DropboxClientsManager.authorizedClient else {
                throw DropboxError.notAuthenticated
            }
            
            // Resolve filename conflicts
            let finalFilename = try await self.resolveFilenameConflict(filename: filename)
            let dropboxPath = self.dropboxPath(self.inspirationFolder, finalFilename)
            
            print("📤 Dropbox: Uploading \(finalFilename) (\(imageData.count) bytes)")
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                client.files.upload(
                    path: dropboxPath,
                    mode: Files.WriteMode.overwrite,
                    input: imageData
                ).response { result, error in
                    if let result = result {
                        print("📤 Dropbox: Successfully uploaded \(finalFilename)")
                        continuation.resume()
                    } else if let error = error {
                        print("📤 Dropbox: Error uploading \(finalFilename): \(error)")
                        continuation.resume(throwing: DropboxError.apiError(error.description))
                    } else {
                        continuation.resume(throwing: DropboxError.unknown)
                    }
                }
            }
            
            return finalFilename
        }
    }
    
    private func resolveFilenameConflict(filename: String) async throws -> String {
        let existingFiles = try await fetchImageList()
        let existingFilenames = Set(existingFiles.map { $0.filename })
        
        var finalFilename = filename
        var counter = 1
        
        // Extract name and extension
        let nameComponents = filename.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let baseName = String(nameComponents.first ?? "")
        let fileExtension = nameComponents.count > 1 ? ".\(nameComponents[1])" : ""
        
        // Keep trying with incremented numbers until we find a unique name
        while existingFilenames.contains(finalFilename) {
            finalFilename = "\(baseName)-\(counter)\(fileExtension)"
            counter += 1
        }
        
        return finalFilename
    }
    
    // MARK: - Image Download
    
    func downloadImage(metadata: ImageMetadata, to localURL: URL) async throws {
        if userSettings.isLocalMode {
            // In local mode, dropboxPath is the full local file path — copy it to the cache location
            let sourceURL = URL(fileURLWithPath: metadata.dropboxPath)
            let fm = FileManager.default
            if fm.fileExists(atPath: localURL.path) {
                try fm.removeItem(at: localURL)
            }
            try fm.copyItem(at: sourceURL, to: localURL)
            return
        }
        try await executeWithTokenRefresh {
            guard let client = DropboxClientsManager.authorizedClient else {
                throw DropboxError.notAuthenticated
            }
            
            print("📥 Dropbox: Downloading \(metadata.filename)")
            print("📥 Dropbox: From path: '\(metadata.dropboxPath)'")
            print("📥 Dropbox: To local path: \(localURL.path)")
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                client.files.download(path: metadata.dropboxPath, overwrite: true, destination: localURL)
                    .response { result, error in
                        if let result = result {
                            print("📥 Dropbox: Successfully downloaded \(metadata.filename)")
                            continuation.resume()
                        } else if let error = error {
                            print("📥 Dropbox: Error downloading \(metadata.filename): \(error)")
                            print("📥 Dropbox: Attempted path: '\(metadata.dropboxPath)'")
                            continuation.resume(throwing: DropboxError.downloadFailed(error.description))
                        } else {
                            continuation.resume(throwing: DropboxError.unknown)
                        }
                    }
            }
        }
    }
    
    func downloadImageData(path: String) async throws -> Data? {
        if userSettings.isLocalMode { return try localDownloadImageData(path: path) }
        return try await executeWithTokenRefresh {
            guard let client = DropboxClientsManager.authorizedClient else {
                throw DropboxError.notAuthenticated
            }
            
            print("📥 Dropbox: Downloading image data for path: '\(path)'")
            
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                client.files.download(path: path)
                    .response { result, error in
                        if let result = result {
                            print("📥 Dropbox: Successfully downloaded image data for \(path)")
                            continuation.resume(returning: result.1)
                        } else if let error = error {
                            print("📥 Dropbox: Error downloading image data for \(path): \(error)")
                            continuation.resume(throwing: DropboxError.downloadFailed(error.description))
                        } else {
                            continuation.resume(throwing: DropboxError.unknown)
                        }
                    }
            }
        }
    }
    
    // MARK: - Image Deletion
    
    func deleteImages(filenames: [String]) async throws {
        if userSettings.isLocalMode { try localDeleteImages(filenames: filenames); return }
        try await executeWithTokenRefresh {
            guard let client = DropboxClientsManager.authorizedClient else {
                throw DropboxError.notAuthenticated
            }
            
            print("🗑️ Dropbox: Deleting \(filenames.count) images: \(filenames)")
            
            for filename in filenames {
                let dropboxPath = self.dropboxPath(self.inspirationFolder, filename)
                print("🗑️ Dropbox: Deleting \(filename) at path: \(dropboxPath)")
                
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    client.files.deleteV2(path: dropboxPath).response { result, error in
                        if let result = result {
                            print("🗑️ Dropbox: Successfully deleted \(filename)")
                            continuation.resume()
                        } else if let error = error {
                            print("🗑️ Dropbox: Error deleting \(filename): \(error)")
                            continuation.resume(throwing: DropboxError.apiError(error.description))
                        } else {
                            continuation.resume(throwing: DropboxError.unknown)
                        }
                    }
                }
            }
            
            print("🗑️ Dropbox: All image deletions completed")
        }
    }
    
    // MARK: - Keyword-Image Association Management
    
    func addImageToKeyword(filename: String, keywordPath: [String]) async throws {
        // Use cached tree or fetch if not available
        var keywordTree: KeywordTree
        if let cached = cachedKeywordTree {
            keywordTree = cached
        } else {
            keywordTree = try await fetchKeywords()
        }
        
        // Add the image to the specified keyword path
        keywordTree.addImageToKeyword(filename, keywordPath: keywordPath)
        
        // Update cache immediately for responsive UI
        await MainActor.run {
            cachedKeywordTree = keywordTree
        }
        
        // Save to Dropbox in background
        try await saveKeywords(keywordTree)
        print("📂 Dropbox: Added '\(filename)' to keyword path: \(keywordPath.joined(separator: " > "))")
    }
    
    func removeImageFromKeyword(filename: String, keywordPath: [String]) async throws {
        var keywordTree: KeywordTree
        if let cached = cachedKeywordTree {
            keywordTree = cached
        } else {
            guard let fetched = try? await fetchKeywords() else { return }
            keywordTree = fetched
        }
        
        keywordTree.removeImageFromKeyword(filename, keywordPath: keywordPath)
        
        // Update cache immediately
        await MainActor.run {
            cachedKeywordTree = keywordTree
        }
        
        try await saveKeywords(keywordTree)
        print("📂 Dropbox: Removed '\(filename)' from keyword path: \(keywordPath.joined(separator: " > "))")
    }
    
    func removeImageFromAllKeywords(filename: String) async throws {
        var keywordTree: KeywordTree
        if let cached = cachedKeywordTree {
            keywordTree = cached
        } else {
            guard let fetched = try? await fetchKeywords() else { return }
            keywordTree = fetched
        }
        
        keywordTree.removeImageFromAllKeywords(filename)
        
        // Update cache immediately  
        await MainActor.run {
            cachedKeywordTree = keywordTree
        }
        
        try await saveKeywords(keywordTree)
        print("📂 Dropbox: Removed '\(filename)' from all keywords")
    }
    
    func getImagesForKeyword(keywordPath: [String]) async throws -> [String] {
        let keywordTree: KeywordTree
        if let cached = cachedKeywordTree {
            keywordTree = cached
        } else {
            keywordTree = try await fetchKeywords()
        }
        
        // Use the existing method in KeywordTree to find images
        let fullKeywordPath = keywordPath.joined(separator: "/")
        return keywordTree.getImageFilenamesForKeyword(fullKeywordPath) ?? []
    }
    
    func invalidateKeywordCache() {
        cachedKeywordTree = nil
        keywordTreeLoadTask?.cancel()
        keywordTreeLoadTask = nil
        print("📂 Dropbox: Keyword tree cache invalidated")
    }
    
    // MARK: - Groups Management
    
    /// Add selected images to a new group
    func addImagesToGroup(_ imageFilenames: [String]) async throws {
        // Add the new group to cached groups
        await MainActor.run {
            cachedGroups.append(imageFilenames)
            print("📂 Dropbox: Added new group with \(imageFilenames.count) images")
        }
        
        // Save to Dropbox if we have keywords cached
        if let keywordTree = cachedKeywordTree {
            try await saveKeywords(keywordTree)
        }
    }
    
    /// Remove selected images from all groups they belong to
    func removeImagesFromGroups(_ imageFilenames: [String]) async throws {
        await MainActor.run {
            // Remove images from all groups and remove any empty groups
            cachedGroups = cachedGroups.compactMap { group in
                let filteredGroup = group.filter { !imageFilenames.contains($0) }
                return filteredGroup.isEmpty ? nil : filteredGroup
            }
            print("📂 Dropbox: Removed \(imageFilenames.count) images from groups")
        }
        
        // Save to Dropbox if we have keywords cached
        if let keywordTree = cachedKeywordTree {
            try await saveKeywords(keywordTree)
        }
    }
    
    /// Check if any of the given images are currently in groups
    func areImagesInGroups(_ imageFilenames: [String]) -> Bool {
        let result = cachedGroups.contains { group in
            imageFilenames.contains { filename in
                group.contains(filename)
            }
        }
        print("🔍 DropboxService: areImagesInGroups(\(imageFilenames)) = \(result) (cached groups: \(cachedGroups.count))")
        return result
    }
    
    /// Get all groups that contain any of the given images
    func getGroupsContainingImages(_ imageFilenames: [String]) -> [[String]] {
        let result = cachedGroups.filter { group in
            imageFilenames.contains { filename in
                group.contains(filename)
            }
        }
        print("🔍 DropboxService: getGroupsContainingImages(\(imageFilenames)) returned \(result.count) groups")
        for (index, group) in result.enumerated() {
            print("🔍   Group \(index): \(group.joined(separator: ", "))")
        }
        return result
    }
    
    // MARK: - File Renaming Functions
    
    /// Checks if a filename follows the 5-digit pattern (e.g., 00001.jpg)
    private func isSequentiallyNamed(_ filename: String) -> Bool {
        let components = filename.split(separator: ".")
        guard components.count == 2 else { return false }
        
        let nameComponent = String(components[0])
        return nameComponent.count == 5 && nameComponent.allSatisfy { $0.isNumber }
    }
    
    /// Renames a file in Dropbox from oldPath to newPath
    private func renameFileInDropbox(from oldPath: String, to newPath: String) async throws {
        try await executeWithTokenRefresh {
            guard let client = DropboxClientsManager.authorizedClient else {
                throw DropboxError.notAuthenticated
            }
            
            return try await withCheckedThrowingContinuation { continuation in
                client.files.moveV2(fromPath: oldPath, toPath: newPath).response { result, error in
                    if result != nil {
                        print("📂 Dropbox: Successfully renamed '\(oldPath)' to '\(newPath)'")
                        continuation.resume()
                    } else if let error = error {
                        print("📂 Dropbox: Failed to rename '\(oldPath)': \(error)")
                        continuation.resume(throwing: DropboxError.apiError(error.description))
                    } else {
                        continuation.resume(throwing: DropboxError.unknown)
                    }
                }
            }
        }
    }
    
    /// Processes and renames any files that don't follow the 5-digit naming convention
    func processAndRenameFiles() async throws {
        print("📂 Dropbox: Starting file rename process...")
        
        // Get current images list
        let currentImages = try await fetchImageList()
        var updatedKeywordTree: KeywordTree
        if let cached = cachedKeywordTree {
            updatedKeywordTree = cached
        } else {
            updatedKeywordTree = try await fetchKeywords()
        }
        var hasChanges = false
        
        // Find the highest existing sequential number
        var maxSequentialNumber = 0
        var filesToRename: [(old: String, fileExtension: String)] = []
        
        for image in currentImages {
            if isSequentiallyNamed(image.filename) {
                // Track highest sequential number
                let components = image.filename.split(separator: ".")
                if let numberString = components.first,
                   let number = Int(numberString) {
                    maxSequentialNumber = max(maxSequentialNumber, number)
                }
            } else {
                // This file needs renaming
                let components = image.filename.split(separator: ".")
                let fileExtension = components.count > 1 ? String(components.last!) : "jpg"
                filesToRename.append((old: image.filename, fileExtension: fileExtension))
            }
        }
        
        // Assign new sequential names starting from maxSequentialNumber + 1
        var currentNumber = maxSequentialNumber + 1
        var renameOperations: [(old: String, new: String)] = []
        
        for file in filesToRename {
            let paddedNumber = String(format: "%05d", currentNumber)
            let newFilename = "\(paddedNumber).\(file.fileExtension)"
            renameOperations.append((old: file.old, new: newFilename))
            currentNumber += 1
        }
        
        // Perform the renaming operations
        for (oldFilename, newFilename) in renameOperations {
            let oldPath = dropboxPath(inspirationFolder, oldFilename)
            let newPath = dropboxPath(inspirationFolder, newFilename)
            
            do {
                try await renameFileInDropbox(from: oldPath, to: newPath)
                
                // Update keyword associations
                updatedKeywordTree.updateFilenameInAllKeywords(from: oldFilename, to: newFilename)
                hasChanges = true
                
                print("📂 Dropbox: Renamed '\(oldFilename)' to '\(newFilename)'")
            } catch {
                print("❌ Dropbox: Failed to rename '\(oldFilename)': \(error)")
            }
        }
        
        // Save updated keyword tree if there were changes
        if hasChanges {
            try await saveKeywords(updatedKeywordTree)
            await MainActor.run {
                cachedKeywordTree = updatedKeywordTree
            }
            print("📂 Dropbox: Updated keyword associations for renamed files")
        }
        
        print("📂 Dropbox: File rename process completed. Renamed \(renameOperations.count) files.")
    }
    
    // MARK: - File Upload
    
    func uploadFile(data: Data, filename: String) async throws {
        if userSettings.isLocalMode { _ = try localUploadImage(imageData: data, filename: filename); return }
        try await executeWithTokenRefresh {
            guard let client = DropboxClientsManager.authorizedClient else {
                throw DropboxError.notAuthenticated
            }
            
            let uploadPath = self.dropboxPath(self.inspirationFolder, filename)
            print("📂 Dropbox: Uploading file to '\(uploadPath)'")
            
            return try await withCheckedThrowingContinuation { continuation in
                client.files.upload(
                    path: uploadPath,
                    mode: Files.WriteMode.overwrite,
                    autorename: false,
                    clientModified: Date(),
                    mute: false,
                    input: data
                ).response { result, error in
                    if let result = result {
                        print("📂 Dropbox: Successfully uploaded '\(filename)'")
                        continuation.resume()
                    } else if let error = error {
                        print("📂 Dropbox: Failed to upload '\(filename)': \(error)")
                        continuation.resume(throwing: DropboxError.apiError(error.description))
                    } else {
                        continuation.resume(throwing: DropboxError.unknown)
                    }
                }
            }
        }
    }
}

enum DropboxError: Error, LocalizedError {
    case notAuthenticated
    case apiError(String)
    case downloadFailed(String)
    case unknown
    case tokenExpired
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to Dropbox to continue"
        case .apiError(let message):
            return "Dropbox API error: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .unknown:
            return "An unknown Dropbox error occurred"
        case .tokenExpired:
            return "Your Dropbox session has expired. Please sign in again."
        }
    }
}

extension String {
    func matches(_ regex: String) -> Bool {
        return range(of: regex, options: .regularExpression, range: nil, locale: nil) != nil
    }
}
