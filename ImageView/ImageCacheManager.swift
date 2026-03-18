//
//  ImageCacheManager.swift
//  ImageView
//
//  Created by david silver on 2026-03-15.
//

import Foundation
import SwiftUI
import Combine

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()
    
    private let cacheDirectory: URL
    private let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500 MB
    private let maxCacheAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    
    @Published private var cachedImages: [String: CachedImage] = [:]
    private let fileManager = FileManager.default
    
    private init() {
        // Create cache directory in Documents
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDirectory = documentsPath.appendingPathComponent("ImageCache")
        
        // Create cache directory if it doesn't exist
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        
        loadCacheIndex()
    }
    
    // MARK: - Public Interface
    
    func getCachedImage(for metadata: ImageMetadata) -> PlatformImage? {
        let cacheKey = metadata.contentHash ?? metadata.filename
        
        if let cachedImage = cachedImages[cacheKey] {
            // Update last accessed time
            updateLastAccessed(cacheKey: cacheKey)
            
            // Load image from disk
            return loadImageFromDisk(cachedImage.localPath)
        }
        
        return nil
    }
    
    func cacheImage(_ image: PlatformImage, for metadata: ImageMetadata) {
        let cacheKey = metadata.contentHash ?? metadata.filename
        let fileName = "\(cacheKey).\(getFileExtension(metadata.filename))"
        let localURL = cacheDirectory.appendingPathComponent(fileName)
        
        // Save image to disk
        if saveImageToDisk(image, at: localURL) {
            let cachedImage = CachedImage(
                cacheKey: cacheKey,
                localPath: localURL.path,
                fileSize: getFileSize(at: localURL),
                lastAccessed: Date(),
                originalFilename: metadata.filename
            )
            
            cachedImages[cacheKey] = cachedImage
            saveCacheIndex()
            
            // Clean up cache if needed
            cleanupCacheIfNeeded()
            
            print("💾 Cache: Cached \(metadata.filename)")
        }
    }
    
    func isCached(metadata: ImageMetadata) -> Bool {
        let cacheKey = metadata.contentHash ?? metadata.filename
        return cachedImages[cacheKey] != nil
    }
    
    func downloadAndCacheImage(for metadata: ImageMetadata) async -> PlatformImage? {
        // Check if already downloading
        let cacheKey = metadata.contentHash ?? metadata.filename
        
        print("💾 Cache: Attempting to download and cache \(metadata.filename)")
        print("💾 Cache: Dropbox path: '\(metadata.dropboxPath)'")
        print("💾 Cache: Cache key: '\(cacheKey)'")
        
        do {
            let fileName = "\(cacheKey).\(getFileExtension(metadata.filename))"
            let localURL = cacheDirectory.appendingPathComponent(fileName)
            
            print("💾 Cache: Local cache path: \(localURL.path)")
            
            // Download from Dropbox
            try await DropboxService.shared.downloadImage(metadata: metadata, to: localURL)
            
            // Load and cache the image
            if let image = loadImageFromDisk(localURL.path) {
                print("💾 Cache: Successfully loaded image from disk: \(metadata.filename)")
                await MainActor.run {
                    let cachedImage = CachedImage(
                        cacheKey: cacheKey,
                        localPath: localURL.path,
                        fileSize: getFileSize(at: localURL),
                        lastAccessed: Date(),
                        originalFilename: metadata.filename
                    )
                    
                    cachedImages[cacheKey] = cachedImage
                    saveCacheIndex()
                    cleanupCacheIfNeeded()
                }
                
                return image
            } else {
                print("💾 Cache: Failed to load image from disk after download: \(metadata.filename)")
            }
        } catch {
            print("💾 Cache: Failed to download and cache \(metadata.filename): \(error)")
        }
        
        return nil
    }
    
    // MARK: - Cache Management
    
    private func updateLastAccessed(cacheKey: String) {
        cachedImages[cacheKey]?.lastAccessed = Date()
        saveCacheIndex()
    }
    
    private func cleanupCacheIfNeeded() {
        let totalSize = cachedImages.values.reduce(0) { $0 + $1.fileSize }
        
        if totalSize > maxCacheSize {
            print("💾 Cache: Size limit exceeded (\(totalSize) bytes), cleaning up...")
            cleanupLeastRecentlyUsed()
        }
        
        cleanupExpiredImages()
    }
    
    private func cleanupLeastRecentlyUsed() {
        // Sort by last accessed date (oldest first)
        let sortedImages = cachedImages.values.sorted { $0.lastAccessed < $1.lastAccessed }
        
        var freedSpace: Int64 = 0
        let targetSpace = maxCacheSize / 4 // Free up 25% of cache
        
        for cachedImage in sortedImages {
            if freedSpace >= targetSpace { break }
            
            // Delete from disk
            try? fileManager.removeItem(atPath: cachedImage.localPath)
            
            // Remove from index
            cachedImages.removeValue(forKey: cachedImage.cacheKey)
            freedSpace += cachedImage.fileSize
            
            print("💾 Cache: Removed LRU image \(cachedImage.originalFilename)")
        }
        
        saveCacheIndex()
    }
    
    private func cleanupExpiredImages() {
        let cutoffDate = Date().addingTimeInterval(-maxCacheAge)
        let expiredImages = cachedImages.values.filter { $0.lastAccessed < cutoffDate }
        
        for cachedImage in expiredImages {
            // Delete from disk
            try? fileManager.removeItem(atPath: cachedImage.localPath)
            
            // Remove from index
            cachedImages.removeValue(forKey: cachedImage.cacheKey)
            
            print("💾 Cache: Removed expired image \(cachedImage.originalFilename)")
        }
        
        if !expiredImages.isEmpty {
            saveCacheIndex()
        }
    }
    
    // MARK: - Disk Operations
    
    private func saveImageToDisk(_ image: PlatformImage, at url: URL) -> Bool {
#if os(macOS)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return false }
#else
        guard let data = image.jpegData(compressionQuality: 0.8) else { return false }
#endif
        
        do {
            try data.write(to: url)
            return true
        } catch {
            print("💾 Cache: Failed to save image to disk: \(error)")
            return false
        }
    }
    
    private func loadImageFromDisk(_ path: String) -> PlatformImage? {
#if os(macOS)
        return NSImage(contentsOfFile: path)
#else
        return UIImage(contentsOfFile: path)
#endif
    }
    
    private func getFileSize(at url: URL) -> Int64 {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    private func getFileExtension(_ filename: String) -> String {
        return URL(fileURLWithPath: filename).pathExtension.lowercased()
    }
    
    // MARK: - Cache Index
    
    private var cacheIndexURL: URL {
        return cacheDirectory.appendingPathComponent("cache_index.json")
    }
    
    private func loadCacheIndex() {
        guard let data = try? Data(contentsOf: cacheIndexURL),
              let cachedImageArray = try? JSONDecoder().decode([CachedImage].self, from: data) else {
            print("💾 Cache: No existing cache index found")
            return
        }
        
        // Convert array back to dictionary
        cachedImages = Dictionary(uniqueKeysWithValues: cachedImageArray.map { ($0.cacheKey, $0) })
        
        // Verify files still exist on disk
        var updatedCache: [String: CachedImage] = [:]
        for (key, cached) in cachedImages {
            if fileManager.fileExists(atPath: cached.localPath) {
                updatedCache[key] = cached
            }
        }
        cachedImages = updatedCache
        
        print("💾 Cache: Loaded \(cachedImages.count) cached images from index")
    }
    
    private func saveCacheIndex() {
        let cachedImageArray = Array(cachedImages.values)
        
        do {
            let data = try JSONEncoder().encode(cachedImageArray)
            try data.write(to: cacheIndexURL)
        } catch {
            print("💾 Cache: Failed to save cache index: \(error)")
        }
    }
}

struct CachedImage: Codable {
    let cacheKey: String
    let localPath: String
    let fileSize: Int64
    var lastAccessed: Date
    let originalFilename: String
}
