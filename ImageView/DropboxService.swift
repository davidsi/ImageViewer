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
    
    private let inspirationFolder = "/Apps/InspirationViewer"
    private let keywordsFileName = "keywords.json"
    
    private init() {}
    
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
        guard let client = DropboxClientsManager.authorizedClient else {
            print("❌ Dropbox: No authorized client available")
            throw DropboxError.notAuthenticated
        }
        
        print("📂 Dropbox: Client exists, fetching files from \(self.inspirationFolder)")
        print("📂 Dropbox: Client description: \(String(describing: client))")
        
        // First try to list the folder, if it fails, try to create it
        return try await withCheckedThrowingContinuation { continuation in
            client.files.listFolder(path: self.inspirationFolder).response { result, error in
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
    
    private func createFolderAndRetry(client: DropboxClient, continuation: CheckedContinuation<[ImageMetadata], Error>) {
        client.files.createFolderV2(path: self.inspirationFolder).response { result, error in
            if let result = result {
                print("📂 Dropbox: Successfully created folder: \(result.metadata.pathDisplay ?? self.inspirationFolder)")
                // Folder created, now try listing again (should be empty)
                continuation.resume(returning: [])
            } else if let error = error {
                print("📂 Dropbox: Failed to create folder: \(error)")
                
                // Check if folder already exists (race condition)
                let errorString = error.description
                if errorString.contains("path_already_exists") {
                    print("📂 Dropbox: Folder already exists, returning empty list")
                    continuation.resume(returning: [])
                } else {
                    continuation.resume(throwing: DropboxError.apiError("Failed to access or create folder: \(error.description)"))
                }
            } else {
                continuation.resume(throwing: DropboxError.unknown)
            }
        }
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
        guard let client = DropboxClientsManager.authorizedClient else {
            throw DropboxError.notAuthenticated
        }
        
        let keywordsPath = "\(self.inspirationFolder)/\(self.keywordsFileName)"
        print("📂 Dropbox: Fetching keywords from \(keywordsPath)")
        
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
                    continuation.resume(throwing: DropboxError.apiError("Keywords file not found"))
                } else {
                    continuation.resume(throwing: DropboxError.unknown)
                }
            }
        }
    }
    
    // MARK: - Keywords Save
    
    func saveKeywords(_ keywordTree: KeywordTree) async throws {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw DropboxError.notAuthenticated
        }
        
        let keywordsPath = "\(self.inspirationFolder)/\(self.keywordsFileName)"
        print("📂 Dropbox: Saving keywords to \(keywordsPath)")
        
        do {
            let jsonData = try JSONEncoder().encode(keywordTree)
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                client.files.upload(path: keywordsPath, input: jsonData).response { result, error in
                    if let result = result {
                        print("📂 Dropbox: Successfully saved keywords")
                        continuation.resume()
                    } else if let error = error {
                        print("📂 Dropbox: Error saving keywords: \(error)")
                        continuation.resume(throwing: DropboxError.apiError(error.description))
                    } else {
                        continuation.resume(throwing: DropboxError.unknown)
                    }
                }
            }
        } catch {
            throw DropboxError.apiError("Failed to encode keywords: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Image Download
    
    func downloadImage(metadata: ImageMetadata, to localURL: URL) async throws {
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
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with Dropbox"
        case .apiError(let message):
            return "Dropbox API error: \(message)"
        case .downloadFailed(let message):
            return "Failed to download file: \(message)"
        case .unknown:
            return "Unknown Dropbox error"
        }
    }
}

extension String {
    func matches(_ regex: String) -> Bool {
        return range(of: regex, options: .regularExpression, range: nil, locale: nil) != nil
    }
}
