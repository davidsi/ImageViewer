//
//  iCloudPhotosView.swift
//  ImageView
//
//  Created by GitHub Copilot on 2026-03-16.
//

import SwiftUI
import Photos
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct iCloudPhotosView: View {
    @State private var albums: [PHAssetCollection] = []
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var isLoading = true
    @State private var selectedAlbumId: String?
    
    private var selectedAlbum: PHAssetCollection? {
        guard let selectedAlbumId = selectedAlbumId else { return nil }
        return albums.first { $0.localIdentifier == selectedAlbumId }
    }
    
    var body: some View {
        Group {
#if os(macOS)
            GeometryReader { geometry in
                HSplitView {
                    // Left side: Albums list
                    albumsListView
                        .frame(minWidth: 200, idealWidth: geometry.size.width * 0.25, maxWidth: 400)
                    
                    // Right side: Photos in selected album  
                    Group {
                        if let selectedAlbum = selectedAlbum {
                            AlbumPhotosView(album: selectedAlbum)
                        } else {
                            Text("Select an album to view photos")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(minWidth: 400)
                }
            }
#else
            NavigationSplitView {
                // Left side: Albums list
                albumsListView
                    .navigationTitle("Albums")
            } detail: {
                // Right side: Photos in selected album
                if let selectedAlbum = selectedAlbum {
                    AlbumPhotosView(album: selectedAlbum)
                } else {
                    Text("Select an album to view photos")
                        .foregroundStyle(.secondary)
                }
            }
#endif
        }
        .onAppear {
            requestPhotoAccess()
        }
    }
    
    private var albumsListView: some View {
#if os(macOS)
        NavigationStack {
            albumsContentView
                .navigationTitle("Albums")
        }
#else
        albumsContentView
#endif
    }
    
    private var albumsContentView: some View {
        Group {
            switch authorizationStatus {
            case .authorized, .limited:
                if isLoading {
                    ProgressView("Loading albums...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(albums, id: \.localIdentifier, selection: $selectedAlbumId) { album in
                        AlbumRowView(album: album)
                            .tag(album.localIdentifier)
                    }
                }
            case .denied, .restricted:
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("Photo Access Required")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 8) {
                        Text("This app needs access to your Photo Library to display iCloud Photos.")
                            .multilineTextAlignment(.center)
                        Text("Go to System Settings > Privacy & Security > Photos to enable access.")
                            .font(.caption)
                            .foregroundStyle(.secondary) 
                            .multilineTextAlignment(.center)
                    }
                    
                    Button("Open System Settings") {
                        #if os(macOS)
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
                        #endif
                    }
                    .buttonStyle(.borderedProminent)
                    
#if os(iOS)
                    Text("Please allow access to your photo library in Settings to view your albums.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    
                    Button("Open Settings") {
                        openAppSettings()
                    }
                    .buttonStyle(.borderedProminent)
#elseif os(macOS)
                    Text("Please allow access to your photo library in System Settings > Privacy & Security > Photos to view your albums.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Button("Open System Settings") {
                            openAppSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Text("Then restart the app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
#endif
                }
                .padding()
            case .notDetermined:
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Requesting Photo Access")
                        .font(.headline)
                    VStack(spacing: 8) {
                        Text("This will access your local Photo Library, including any iCloud Photos that are synced to this device.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Text("Note: Photos stored only in iCloud (not downloaded) won't appear until synced locally.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            @unknown default:
                Text("Unknown authorization status")
            }
        }
    }
    
    private func requestPhotoAccess() {
        print("Requesting photo access...")
        
        // Define authorization level - request readWrite to allow deletion
#if os(iOS)
        let authLevel: PHAccessLevel = .readWrite
#else
        let authLevel: PHAccessLevel = .readWrite  // Changed from .addOnly to support deletion
#endif
        
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: authLevel)
        authorizationStatus = currentStatus
        print("Current photo access status: \(currentStatus.rawValue)")
        
        if currentStatus == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: authLevel) { status in
                DispatchQueue.main.async {
                    print("Photo access authorization result: \(status.rawValue)")
                    self.authorizationStatus = status
                    if status == .authorized || status == .limited {
                        self.loadAlbums()
                    }
                }
            }
        } else if currentStatus == .authorized || currentStatus == .limited {
            loadAlbums()
        }
    }
    
    private func loadAlbums() {
        print("Starting to load albums...")
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            var albumList: [PHAssetCollection] = []
            
            do {
                // Fetch user-created albums
                let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
                userAlbums.enumerateObjects { collection, _, _ in
                    albumList.append(collection)
                }
                print("Found \(userAlbums.count) user albums")
                
                // Fetch smart albums (Camera Roll, Favorites, etc.)
                let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
                smartAlbums.enumerateObjects { collection, _, _ in
                    // Filter out empty albums and some system albums we don't want
                    let fetchOptions = PHFetchOptions()
                    fetchOptions.fetchLimit = 1
                    let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
                    
                    if assets.count > 0 {
                        // Include popular smart albums
                        switch collection.assetCollectionSubtype {
                        case .smartAlbumUserLibrary, .smartAlbumFavorites, .smartAlbumRecentlyAdded, 
                             .smartAlbumScreenshots, .smartAlbumSelfPortraits, .smartAlbumPanoramas,
                             .smartAlbumVideos, .smartAlbumTimelapses:
                            albumList.append(collection)
                            print("Added smart album: \(collection.localizedTitle ?? "Unknown")")
                        default:
                            print("Skipped smart album: \(collection.localizedTitle ?? "Unknown") (subtype: \(collection.assetCollectionSubtype.rawValue))")
                        }
                    }
                }
                print("Found \(smartAlbums.count) smart albums, \(albumList.count) total albums")
                
            } catch {
                print("Error loading albums: \(error)")
            }
            
            DispatchQueue.main.async {
                self.albums = albumList.sorted { album1, album2 in
                    // Sort with Camera Roll first, then by title
                    if album1.assetCollectionSubtype == .smartAlbumUserLibrary {
                        return true
                    } else if album2.assetCollectionSubtype == .smartAlbumUserLibrary {
                        return false
                    } else {
                        return album1.localizedTitle ?? "" < album2.localizedTitle ?? ""
                    }
                }
                self.isLoading = false
                print("Albums loaded successfully: \(self.albums.count) albums")
            }
        }
    }
    
    private func openAppSettings() {
#if os(iOS)
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
#elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback to general Privacy settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(url)
            }
        }
#endif
    }
}

struct AlbumRowView: View {
    let album: PHAssetCollection
#if os(iOS)
    @State private var thumbnail: UIImage?
#elseif os(macOS)
    @State private var thumbnail: NSImage?
#endif
    @State private var assetCount: Int = 0
    
    var body: some View {
        HStack {
            // Album thumbnail
            Group {
                if let thumbnail = thumbnail {
#if os(iOS)
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
#elseif os(macOS)
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
#endif
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(album.localizedTitle ?? "Untitled Album")
                    .font(.headline)
                    .lineLimit(1)
                
                Text("^[\(assetCount) photo](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .onAppear {
            loadThumbnailAndCount()
        }
    }
    
    private func loadThumbnailAndCount() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Get asset count
            let assets = PHAsset.fetchAssets(in: album, options: nil)
            let count = assets.count
            
            // Get thumbnail from first asset
            if count > 0, let firstAsset = assets.firstObject {
                let imageManager = PHImageManager.default()
                let options = PHImageRequestOptions()
                options.deliveryMode = .fastFormat
                options.resizeMode = .fast
                
                imageManager.requestImage(
                    for: firstAsset,
                    targetSize: CGSize(width: 120, height: 120),
                    contentMode: .aspectFill,
                    options: options
                ) { image, _ in
                    DispatchQueue.main.async {
                        thumbnail = image
                        assetCount = count
                    }
                }
            } else {
                DispatchQueue.main.async {
                    assetCount = count
                }
            }
        }
    }
}

struct AlbumPhotosView: View {
    let album: PHAssetCollection
    @State private var assets: [PHAsset] = []
    @State private var isLoading = false  // Start as false, not true
    @State private var selectedAssets: Set<String> = []
    @State private var hasLoaded = false
    @State private var importingCount = 0
    @State private var importProgress: Float = 0.0
    @State private var deleteAfterImport = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 150))
    ]
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading photos...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if assets.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("No Photos")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("This album doesn't contain any photos.")
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                VStack(spacing: 0) {
                    // Button bar
                    HStack(spacing: 12) {
                        Button("Select All") {
                            selectedAssets = Set(assets.map { $0.localIdentifier })
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Clear All") {
                            selectedAssets.removeAll()
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        // Delete after import checkbox
                        HStack(spacing: 6) {
                            Toggle("Delete after import", isOn: $deleteAfterImport)
#if os(macOS)
                                .toggleStyle(.checkbox)
#endif
                            Text("Delete from iCloud Photos after import")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .help("Remove photos from iCloud Photos album after successful import to Dropbox")
                        
                        if importingCount > 0 {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Importing \(importingCount) photos...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Button("Import (\(selectedAssets.count))") {
                            Task {
                                await importSelectedPhotos()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedAssets.isEmpty || importingCount > 0)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
#if os(macOS)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
#elseif os(iOS)
                    .background(Color(UIColor.systemBackground).opacity(0.9))
#endif
                    
                    // Photos grid
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                PhotoThumbnailView(
                                    asset: asset,
                                    isSelected: selectedAssets.contains(asset.localIdentifier),
                                    onSelectionChange: { isSelected in
                                        if isSelected {
                                            selectedAssets.insert(asset.localIdentifier)
                                        } else {
                                            selectedAssets.remove(asset.localIdentifier)
                                        }
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle(album.localizedTitle ?? "Photos")
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .onAppear {
            print("AlbumPhotosView appeared for album: \(album.localizedTitle ?? "Unknown"), hasLoaded: \(hasLoaded), isLoading: \(isLoading)")
            if !hasLoaded {
                loadPhotos()
            }
        }
        .onChange(of: album.localIdentifier) { newAlbumId in
            print("Album changed to: \(newAlbumId), resetting state")
            hasLoaded = false
            isLoading = false
            assets = []
            selectedAssets.removeAll()
            loadPhotos()
        }
    }
    
    private func importSelectedPhotos() async {
        let selectedPhotoIds = selectedAssets
        let selectedPhotos = assets.filter { selectedAssets.contains($0.localIdentifier) }
        
        print("Starting import of \(selectedPhotos.count) photos")
        
        await MainActor.run {
            importingCount = selectedPhotos.count
            importProgress = 0.0
        }
        
        var successCount = 0
        var successfullyImportedAssets: [PHAsset] = []
        let totalCount = selectedPhotos.count
        
        for (index, asset) in selectedPhotos.enumerated() {
            do {
                let imageData = try await getImageData(from: asset)
                let metadata = await extractMetadata(from: asset)
                
                let filename = await generateFilename(from: asset, metadata: metadata)
                
                _ = try await DropboxService.shared.uploadImage(
                    imageData: imageData, 
                    filename: filename, 
                    title: metadata.title
                )
                
                successCount += 1
                successfullyImportedAssets.append(asset)
                print("Successfully imported photo \(index + 1)/\(totalCount): \(filename)")
                
            } catch {
                print("Failed to import photo \(asset.localIdentifier): \(error)")
            }
            
            await MainActor.run {
                importProgress = Float(index + 1) / Float(totalCount)
            }
        }
        
        // Delete successfully imported photos from iCloud Photos if checkbox is enabled
        if deleteAfterImport && !successfullyImportedAssets.isEmpty {
            await deletePhotosFromICloud(successfullyImportedAssets)
        }
        
        await MainActor.run {
            importingCount = 0
            selectedAssets.removeAll()
        }
        
        print("Import completed: \(successCount)/\(totalCount) photos successfully imported")
        if deleteAfterImport {
            print("Deleted \(successfullyImportedAssets.count) photos from iCloud Photos")
        }
        
        // Refresh the images view if it exists
        NotificationCenter.default.post(name: .imagesDidUpdate, object: nil)
        
        // Refresh the current album view to reflect deleted photos
        if deleteAfterImport && !successfullyImportedAssets.isEmpty {
            await MainActor.run {
                // Remove deleted assets from the current view
                let deletedIdentifiers = Set(successfullyImportedAssets.map { $0.localIdentifier })
                assets.removeAll { deletedIdentifiers.contains($0.localIdentifier) }
            }
        }
    }
    
    private func deletePhotosFromICloud(_ assets: [PHAsset]) async {
        print("Attempting to delete \\(assets.count) photos from iCloud Photos...")
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                // Create the delete request inside the performChanges block
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
            print("Successfully deleted \\(assets.count) photos from iCloud Photos")
        } catch {
            print("Failed to delete photos from iCloud Photos: \\(error)")
            
            // Show an alert to the user about the deletion failure
            await MainActor.run {
                // Note: In a real app, you might want to show a proper alert dialog
                print("Error: Could not delete photos from iCloud Photos. They may be protected or the app may not have sufficient permissions.")
            }
        }
    }
    
    private func getImageData(from asset: PHAsset) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, dataUTI, orientation, info in
                if let data = data {
                    continuation.resume(returning: data)
                } else if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: NSError(domain: "PhotoImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get image data"]))
                }
            }
        }
    }
    
    private func extractMetadata(from asset: PHAsset) async -> (title: String?, creationDate: Date?) {
        // Extract IPTC/EXIF metadata if available
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.isNetworkAccessAllowed = false // Use local data only for metadata
            
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, dataUTI, orientation, info in
                var title: String? = nil
                let creationDate = asset.creationDate
                
                if let data = data {
                    // Try to extract IPTC/EXIF metadata
                    if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                            // Check IPTC metadata for title
                            if let iptc = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any] {
                                title = iptc[kCGImagePropertyIPTCObjectName as String] as? String ??
                                       iptc[kCGImagePropertyIPTCHeadline as String] as? String ??
                                       iptc[kCGImagePropertyIPTCCaptionAbstract as String] as? String
                            }
                            
                            // Check EXIF metadata for user comment
                            if title == nil, let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                                title = exif[kCGImagePropertyExifUserComment as String] as? String
                            }
                            
                            // Check TIFF metadata for image description
                            if title == nil, let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                                title = tiff[kCGImagePropertyTIFFImageDescription as String] as? String
                            }
                        }
                    }
                }
                
                continuation.resume(returning: (title: title, creationDate: creationDate))
            }
        }
    }
    
    private func generateFilename(from asset: PHAsset, metadata: (title: String?, creationDate: Date?)) async -> String {
        var filename: String
        
        if let title = metadata.title, !title.isEmpty {
            // Use title, sanitized for filename
            filename = sanitizeFilename(title)
        } else if let creationDate = metadata.creationDate {
            // Use creation date/time
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            filename = "IMG_\(formatter.string(from: creationDate))"
        } else {
            // Fallback to asset identifier
            filename = "IMG_\(asset.localIdentifier.prefix(8))"
        }
        
        // Add appropriate file extension
        let fileExtension = getFileExtension(for: asset)
        return "\(filename)\(fileExtension)"
    }
    
    private func sanitizeFilename(_ filename: String) -> String {
        // Remove or replace invalid filename characters
        let invalidChars = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return filename
            .components(separatedBy: invalidChars)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func getFileExtension(for asset: PHAsset) -> String {
        switch asset.mediaSubtypes {
        case _ where asset.mediaType == .image:
            // Most common formats
            if let uniformTypeIdentifier = asset.value(forKey: "uniformTypeIdentifier") as? String {
                switch uniformTypeIdentifier {
                case "public.heic": return ".heic"
                case "public.png": return ".png"
                case "public.tiff": return ".tiff"
                case "public.gif": return ".gif"
                default: return ".jpg"
                }
            }
            return ".jpg"
        default:
            return ".jpg"
        }
    }
    
    private func loadPhotos() {
        print("loadPhotos called for album: \(album.localizedTitle ?? "Unknown") - isLoading: \(isLoading), hasLoaded: \(hasLoaded)")
        
        // Prevent duplicate loading
        guard !isLoading else {
            print("Photo loading already in progress, skipping...")
            return
        }
        
        print("Starting photo load process...")
        isLoading = true
        hasLoaded = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let fetchResult = PHAsset.fetchAssets(in: self.album, options: fetchOptions)
            var assetList: [PHAsset] = []
            
            fetchResult.enumerateObjects { asset, _, _ in
                assetList.append(asset)
            }
            
            print("Found \(assetList.count) assets in album \(self.album.localizedTitle ?? "Unknown")")
            
            DispatchQueue.main.async {
                self.assets = assetList
                self.isLoading = false  // Make sure to reset isLoading
                print("Photo loading completed for album: \(self.album.localizedTitle ?? "Unknown"), isLoading now: \(self.isLoading)")
            }
        }
    }
}

struct PhotoThumbnailView: View {
    let asset: PHAsset
    let isSelected: Bool
    let onSelectionChange: (Bool) -> Void
    
#if os(iOS)
    @State private var image: UIImage?
#elseif os(macOS)
    @State private var image: NSImage?
#endif
    
    var body: some View {
        ZStack {
            Group {
                if let image = image {
#if os(iOS)
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
#elseif os(macOS)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
#endif
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            if image == nil {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Selection overlay
            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue, lineWidth: 3)
                    .frame(width: 150, height: 150)
                
                // Checkmark
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .background(Circle().fill(.blue))
                    }
                    .padding(8)
                    Spacer()
                }
                .frame(width: 150, height: 150)
            }
        }
        .onTapGesture {
            onSelectionChange(!isSelected)
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        print("Loading image for asset: \(asset.localIdentifier)")
        
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        
        // Add progress handler for iCloud downloads
        options.progressHandler = { progress, error, stop, info in
            if let error = error {
                print("Progress error for asset \(self.asset.localIdentifier): \(error)")
            }
        }
        
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 300, height: 300),
            contentMode: .aspectFill,
            options: options
        ) { loadedImage, info in
            DispatchQueue.main.async {
                if let loadedImage = loadedImage {
                    print("Successfully loaded image for asset: \(self.asset.localIdentifier)")
                    self.image = loadedImage
                } else {
                    print("Failed to load image for asset: \(self.asset.localIdentifier), info: \(String(describing: info))")
                    
                    // Try fallback with different settings
                    self.loadImageFallback()
                }
            }
        }
    }
    
    private func loadImageFallback() {
        print("Attempting fallback load for asset: \(asset.localIdentifier)")
        
        let imageManager = PHImageManager.default()
        let fallbackOptions = PHImageRequestOptions()
        fallbackOptions.deliveryMode = .fastFormat
        fallbackOptions.resizeMode = .fast
        fallbackOptions.isSynchronous = false
        fallbackOptions.isNetworkAccessAllowed = false  // Don't wait for iCloud
        
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 150, height: 150),
            contentMode: .aspectFill,
            options: fallbackOptions
        ) { fallbackImage, info in
            DispatchQueue.main.async {
                if let fallbackImage = fallbackImage {
                    print("Fallback image loaded for asset: \(self.asset.localIdentifier)")
                    self.image = fallbackImage
                } else {
                    print("Fallback also failed for asset: \(self.asset.localIdentifier), info: \(String(describing: info))")
                }
            }
        }
    }
}

#Preview {
    iCloudPhotosView()
}