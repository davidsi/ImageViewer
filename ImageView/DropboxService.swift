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
    
    private init() {}
    
    /// Constructs a proper Dropbox path by joining components
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
        guard let client = DropboxClientsManager.authorizedClient else {
            print("📂 Test: No authorized client")
            return false
        }
        
        return await withCheckedContinuation { continuation in
            client.users.getCurrentAccount().response { result, error in
                if result != nil {
                    print("📂 Test: Connectivity successful")
                    continuation.resume(returning: true)
                } else {
                    print("📂 Test: Connectivity failed: \(error?.localizedDescription ?? "unknown")")
                    continuation.resume(returning: false)
                }
            }
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
        return try await executeWithTokenRefresh {
            guard let client = DropboxClientsManager.authorizedClient else {
                throw DropboxError.notAuthenticated
            }
            
            let keywordsPath = self.dropboxPath(self.inspirationFolder, self.keywordsFileName)
            print("📂 Dropbox: Fetching keywords from '\(keywordsPath)'")
            
            return try await withCheckedThrowingContinuation { continuation in
                client.files.download(path: keywordsPath).response { result, error in
                    if let result = result {
                        do {
                            let keywords = try JSONDecoder().decode(KeywordTree.self, from: result.1)
                            print("📂 Dropbox: Successfully loaded keywords")
                            continuation.resume(returning: keywords)
                        } catch {
                            print("📂 Dropbox: Error parsing keywords JSON: \(error)")
                            continuation.resume(throwing: DropboxError.apiError("Invalid keywords file format"))
                        }
                    } else if let error = error {
                        print("📂 Dropbox: Keywords file not found: \(error)")
                        print("📂 Dropbox: Creating default keywords file with root 'keywords' node")
                        
                        // Create default keywords tree with root "keywords" node
                        var defaultTree = KeywordTree()
                        defaultTree.children["keywords"] = KeywordTreeNode()
                        
                        continuation.resume(returning: defaultTree)
                        
                        // Save the default tree to Dropbox asynchronously (don't wait for it)
                        Task {
                            do {
                                try await self.saveKeywords(defaultTree)
                                print("📂 Dropbox: Successfully created default keywords file")
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
    }
    
    // MARK: - Keywords Save
    
    func saveKeywords(_ keywordTree: KeywordTree) async throws {
        try await executeWithTokenRefresh {
            guard let client = DropboxClientsManager.authorizedClient else {
                print("📂 Dropbox: Not authenticated, cannot save keywords")
                throw DropboxError.notAuthenticated
            }
            
            let keywordsPath = self.dropboxPath(self.inspirationFolder, self.keywordsFileName)
            print("📂 Dropbox: Attempting to save keywords to path: '\(keywordsPath)'")
            print("📂 Dropbox: Folder: '\(self.inspirationFolder)', Filename: '\(self.keywordsFileName)'")
            
            do {
                let jsonData = try JSONEncoder().encode(keywordTree)
                print("📂 Dropbox: Encoded \(jsonData.count) bytes of keyword data")
                
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
            } catch {
                print("📂 Dropbox: Keywords save failed: \(error.localizedDescription)")
                throw DropboxError.apiError("Failed to encode keywords: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Image Upload
    
    func uploadImage(imageData: Data, filename: String, title: String?) async throws -> String {
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
        try await executeWithTokenRefresh {
            guard let client = DropboxClientsManager.authorizedClient else {
                throw DropboxError.notAuthenticated
            }
            
            print("📥 Dropbox: Downloading \(metadata.filename)")
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                client.files.download(path: metadata.dropboxPath, overwrite: true, destination: localURL)
                    .response { result, error in
                        if let result = result {
                            print("📥 Dropbox: Successfully downloaded \(metadata.filename)")
                            continuation.resume()
                        } else if let error = error {
                            print("📥 Dropbox: Error downloading \(metadata.filename): \(error)")
                            continuation.resume(throwing: DropboxError.downloadFailed(error.description))
                        } else {
                            continuation.resume(throwing: DropboxError.unknown)
                        }
                    }
            }
        }
    }
    
    // MARK: - Keyword-Image Association Management
    
    func addImageToKeyword(filename: String, keywordPath: [String]) async throws {
        // Load current keywords
        var keywordTree: KeywordTree
        do {
            keywordTree = try await fetchKeywords()
        } catch {
            // If no keywords file exists, create a new tree
            keywordTree = KeywordTree()
        }
        
        // Add the image to the specified keyword path
        keywordTree.addImageToKeyword(filename, keywordPath: keywordPath)
        
        // Save back to Dropbox
        try await saveKeywords(keywordTree)
        print("📂 Dropbox: Added '\(filename)' to keyword path: \(keywordPath.joined(separator: " > "))")
    }
    
    func removeImageFromKeyword(filename: String, keywordPath: [String]) async throws {
        var keywordTree = try await fetchKeywords()
        keywordTree.removeImageFromKeyword(filename, keywordPath: keywordPath)
        try await saveKeywords(keywordTree)
        print("📂 Dropbox: Removed '\(filename)' from keyword path: \(keywordPath.joined(separator: " > "))")
    }
    
    func removeImageFromAllKeywords(filename: String) async throws {
        var keywordTree = try await fetchKeywords()
        keywordTree.removeImageFromAllKeywords(filename)
        try await saveKeywords(keywordTree)
        print("📂 Dropbox: Removed '\(filename)' from all keywords")
    }
    
    func getImagesForKeyword(keywordPath: [String]) async throws -> [String] {
        let keywordTree = try await fetchKeywords()
        
        // Navigate to the target keyword
        var currentChildren = keywordTree.children
        for keyword in keywordPath {
            guard let node = currentChildren[keyword] else {
                return [] // Keyword path doesn't exist
            }
            if keyword == keywordPath.last {
                return node.imageFilenames ?? []
            }
            currentChildren = node.children
        }
        return []
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
