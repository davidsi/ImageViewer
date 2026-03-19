//
//  LocalDriveView.swift
//  ImageView
//
//  Created by GitHub Copilot on 2026-03-19.
//

import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers

struct LocalDriveView: View {
    @State private var selectedFolderURL: URL?
    @State private var imageFiles: [URL] = []
    @State private var isLoading = false
    @State private var selectedImages = Set<String>()
    @State private var copyProgress: Double = 0.0
    @State private var isCopying = false
    @State private var copyMessage = ""
    @StateObject private var dropboxService = DropboxService.shared
    
    private let supportedImageTypes: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff", "webp"]
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side: Folder browser and controls
            VStack(alignment: .leading, spacing: 16) {
                // Folder Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Source Folder")
                        .font(.headline)
                    
                    Button(action: selectFolder) {
                        HStack {
                            Image(systemName: "folder")
                            Text(selectedFolderURL?.lastPathComponent ?? "Choose Folder…")
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if let folderURL = selectedFolderURL {
                        Text(folderURL.path())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Image Selection Controls
                if !imageFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Images Found: \(imageFiles.count)")
                                .font(.headline)
                            Spacer()
                            if !selectedImages.isEmpty {
                                Text("\(selectedImages.count) selected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Button("Select All") {
                                selectedImages = Set(imageFiles.map { $0.absoluteString })
                            }
                            .disabled(imageFiles.isEmpty)
                            
                            Button("Select None") {
                                selectedImages.removeAll()
                            }
                            .disabled(selectedImages.isEmpty)
                        }
                    }
                    
                    Divider()
                }
                
                // Copy Controls
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: copySelectedImages) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Copy to Dropbox")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(selectedImages.isEmpty || isCopying || !dropboxService.isAuthenticated())
                    .buttonStyle(.borderedProminent)
                    
                    if isCopying {
                        ProgressView(value: copyProgress) {
                            Text(copyMessage)
                                .font(.caption)
                        }
                    }
                    
                    if !dropboxService.isAuthenticated() {
                        Text("Please authenticate with Dropbox first")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 350)
            .background(Color.gray.opacity(0.05))
            
            Divider()
            
            // Right side: Image preview grid
            VStack {
                if imageFiles.isEmpty && !isLoading {
                    Text("Select a folder to see images")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading {
                    ProgressView("Loading images...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 120), spacing: 8)], spacing: 8) {
                            ForEach(imageFiles, id: \.absoluteString) { imageURL in
                                LocalImageTile(
                                    imageURL: imageURL,
                                    isSelected: selectedImages.contains(imageURL.absoluteString)
                                ) {
                                    toggleImageSelection(imageURL)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.blue.opacity(0.05))
        }
        .navigationTitle("Local Drive Import")
        .onChange(of: selectedFolderURL) { _ in
            print("Folder selection changed: \(selectedFolderURL?.path() ?? "nil")")
            if selectedFolderURL != nil {
                loadImagesFromFolder()
            } else {
                imageFiles.removeAll()
                selectedImages.removeAll()
            }
        }
        .onChange(of: imageFiles) { _ in
            print("imageFiles array updated with \(imageFiles.count) images")
        }
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        
        print("Opening folder selection panel...")
        if panel.runModal() == .OK {
            print("User selected folder: \(panel.url?.path() ?? "nil")")
            selectedFolderURL = panel.url
            selectedImages.removeAll()
        } else {
            print("Folder selection was cancelled")
        }
    }
    
    private func loadImagesFromFolder() {
        guard let folderURL = selectedFolderURL else { return }
        
        print("Loading images from folder: \(folderURL.path())")
        isLoading = true
        imageFiles.removeAll()
        
        Task {
            do {
                let fileManager = FileManager.default
                let contents = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                
                print("Found \(contents.count) total files in folder")
                
                let imageURLs = contents.filter { url in
                    guard let isRegularFile = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                          isRegularFile else { 
                        print("Skipping non-regular file: \(url.lastPathComponent)")
                        return false 
                    }
                    
                    let pathExtension = url.pathExtension.lowercased()
                    let isImage = supportedImageTypes.contains(pathExtension)
                    if !isImage && !pathExtension.isEmpty {
                        print("Skipping unsupported file type: \(url.lastPathComponent) (.\(pathExtension))")
                    }
                    return isImage
                }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                
                print("Found \(imageURLs.count) image files")
                for imageURL in imageURLs {
                    print("- \(imageURL.lastPathComponent)")
                }
                
                await MainActor.run {
                    imageFiles = imageURLs
                    isLoading = false
                    print("Updated imageFiles array with \(imageFiles.count) images")
                    print("Current UI state - isLoading: \(isLoading), imageFiles.count: \(imageFiles.count)")
                }
            } catch {
                print("Error loading folder contents: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func toggleImageSelection(_ imageURL: URL) {
        let urlString = imageURL.absoluteString
        if selectedImages.contains(urlString) {
            selectedImages.remove(urlString)
        } else {
            selectedImages.insert(urlString)
        }
    }
    
    private func copySelectedImages() {
        guard !selectedImages.isEmpty else { return }
        
        isCopying = true
        copyProgress = 0.0
        
        let selectedURLs = imageFiles.filter { selectedImages.contains($0.absoluteString) }
        let totalCount = selectedURLs.count
        
        Task {
            for (index, imageURL) in selectedURLs.enumerated() {
                await MainActor.run {
                    copyMessage = "Copying \(imageURL.lastPathComponent)..."
                    copyProgress = Double(index) / Double(totalCount)
                }
                
                do {
                    try await copyImageToDropbox(imageURL)
                    print("Successfully copied: \(imageURL.lastPathComponent)")
                } catch {
                    print("Failed to copy \(imageURL.lastPathComponent): \(error)")
                }
            }
            
            await MainActor.run {
                copyProgress = 1.0
                copyMessage = "Copy completed!"
                isCopying = false
                selectedImages.removeAll()
                
                // Clear the message after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if !isCopying {
                        copyMessage = ""
                    }
                }
            }
        }
    }
    
    private func copyImageToDropbox(_ imageURL: URL) async throws {
        // Read the image data
        let imageData = try Data(contentsOf: imageURL)
        
        // Get current images to determine next sequential name
        let currentImages = try await dropboxService.fetchImageList()
        
        // Find the highest sequential number
        var maxNumber = 0
        for image in currentImages {
            if isSequentiallyNamed(image.filename) {
                let components = image.filename.split(separator: ".")
                if let numberString = components.first,
                   let number = Int(numberString) {
                    maxNumber = max(maxNumber, number)
                }
            }
        }
        
        // Generate new sequential filename
        let nextNumber = maxNumber + 1
        let paddedNumber = String(format: "%05d", nextNumber)
        let fileExtension = imageURL.pathExtension.lowercased()
        let newFilename = "\(paddedNumber).\(fileExtension)"
        
        // Upload to Dropbox with new name
        try await dropboxService.uploadFile(data: imageData, filename: newFilename)
        
        print("Copied \(imageURL.lastPathComponent) as \(newFilename)")
    }
    
    private func isSequentiallyNamed(_ filename: String) -> Bool {
        let components = filename.split(separator: ".")
        guard components.count == 2 else { return false }
        
        let nameComponent = String(components[0])
        return nameComponent.count == 5 && nameComponent.allSatisfy { $0.isNumber }
    }
}

struct LocalImageTile: View {
    let imageURL: URL
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var thumbnail: NSImage?
    
    init(imageURL: URL, isSelected: Bool, onTap: @escaping () -> Void) {
        self.imageURL = imageURL
        self.isSelected = isSelected
        self.onTap = onTap
        print("Creating LocalImageTile for: \(imageURL.lastPathComponent)")
    }
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(1, contentMode: .fit)
                
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } else {
                    ProgressView()
                        .scaleEffect(0.5)
                }
                
                // Selection overlay
                if isSelected {
                    Rectangle()
                        .fill(Color.blue.opacity(0.3))
                        .strokeBorder(Color.blue, lineWidth: 3)
                }
                
                // Selection indicator
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .blue : .white)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .font(.caption)
                    }
                    Spacer()
                }
                .padding(4)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .cornerRadius(8)
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        guard thumbnail == nil else { return }
        
        await Task.detached {
            guard let image = NSImage(contentsOf: imageURL) else { return }
            
            // Create thumbnail
            let thumbnailSize = NSSize(width: 120, height: 120)
            let thumbnailImage = NSImage(size: thumbnailSize)
            
            thumbnailImage.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: thumbnailSize),
                      from: NSRect(origin: .zero, size: image.size),
                      operation: .copy,
                      fraction: 1.0)
            thumbnailImage.unlockFocus()
            
            await MainActor.run {
                thumbnail = thumbnailImage
            }
        }.value
    }
}

#else
// Placeholder for non-macOS platforms
struct LocalDriveView: View {
    var body: some View {
        Text("Local Drive import is only available on macOS")
            .foregroundColor(.secondary)
    }
}
#endif