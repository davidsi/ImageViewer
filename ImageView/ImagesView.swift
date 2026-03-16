//
//  ImagesView.swift
//  ImageView
//
//  Created by david silver on 2026-03-15.
//

import SwiftUI

struct ImagesView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var dropboxService = DropboxService.shared
    @StateObject private var cacheManager = ImageCacheManager.shared
    
    @State private var images: [ImageMetadata] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedKeywords: [String] = []
    @State private var availableKeywords: [String] = []
    
    private var filteredImages: [ImageMetadata] {
        var filtered = images
        
        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { image in
                (image.title?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                image.filename.localizedCaseInsensitiveContains(searchText) ||
                (image.keywords?.contains { $0.localizedCaseInsensitiveContains(searchText) } ?? false)
            }
        }
        
        // Filter by selected keywords
        if !selectedKeywords.isEmpty {
            filtered = filtered.filter { image in
                guard let imageKeywords = image.keywords else { return false }
                return selectedKeywords.allSatisfy { keyword in
                    imageKeywords.contains(keyword)
                }
            }
        }
        
        return filtered
    }
    
    private var gridColumns: [GridItem] {
#if os(macOS)
        Array(repeating: GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16), count: 1)
#else
        Array(repeating: GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12), count: 1)
#endif
    }
    
    var body: some View {
#if os(macOS)
        HSplitView {
            // Keywords Sidebar
            KeywordsSidebarView(
                availableKeywords: availableKeywords,
                selectedKeywords: $selectedKeywords,
                searchText: $searchText
            )
            .frame(minWidth: 200, maxWidth: 300)
            
            // Main Images View
            ImagesMainView(
                filteredImages: filteredImages,
                isLoading: isLoading,
                errorMessage: errorMessage,
                searchText: $searchText,
                selectedKeywords: $selectedKeywords,
                gridColumns: gridColumns,
                loadImagesAction: { Task { await loadImages() } }
            )
        }
        .navigationTitle("Images")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                RefreshButton(isLoading: isLoading) {
                    Task { await loadImages() }
                }
            }
        }
#else
        NavigationView {
            VStack(spacing: 0) {
                // Search and Filter Controls
                VStack(spacing: 12) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search images...", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .padding(.horizontal)
                    
                    // Keyword filter chips
                    if !availableKeywords.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 8) {
                                ForEach(availableKeywords, id: \.self) { keyword in
                                    KeywordChip(
                                        keyword: keyword,
                                        isSelected: selectedKeywords.contains(keyword)
                                    ) {
                                        toggleKeyword(keyword)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical, 8)
                
                Divider()
                
                // Main Content
                ImagesMainView(
                    filteredImages: filteredImages,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    searchText: $searchText,
                    selectedKeywords: $selectedKeywords,
                    gridColumns: gridColumns,
                    loadImagesAction: { Task { await loadImages() } }
                )
            }
            .navigationTitle("Images")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    RefreshButton(isLoading: isLoading) {
                        Task { await loadImages() }
                    }
                }
            }
        }
#endif
        .task {
            await loadImages()
        }
        .onReceive(NotificationCenter.default.publisher(for: .imagesDidUpdate)) { _ in
            Task {
                await loadImages()
            }
        }
    }
    
    private func loadImages() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        // Test basic connectivity first
        print("📱 Images: Testing Dropbox connectivity...")
        let isConnected = await dropboxService.testConnectivity()
        if !isConnected {
            await MainActor.run {
                errorMessage = "Cannot connect to Dropbox. Please check your internet connection and try again."
                isLoading = false
            }
            return
        }
        print("📱 Images: Connectivity test passed")
        
        // Explore the Dropbox structure for debugging
        print("📱 Images: Exploring Dropbox structure...")
        await dropboxService.exploreDropboxStructure()
        
        do {
            let loadedImages = try await dropboxService.fetchImageList()
            
            // Load available keywords
            do {
                let keywordTree = try await dropboxService.fetchKeywords()
                await MainActor.run {
                    availableKeywords = extractAllKeywords(from: keywordTree)
                }
            } catch {
                print("⚠️ No keywords file found or error loading keywords: \(error)")
                // Continue without keywords - this is normal for new setups
                await MainActor.run {
                    availableKeywords = []
                }
            }
            
            await MainActor.run {
                images = loadedImages
                isLoading = false
            }
            
            print("📱 Images: Loaded \(loadedImages.count) images from Dropbox")
            
            // Show helpful message if no images found
            if loadedImages.isEmpty {
                await MainActor.run {
                    errorMessage = "No images found. Upload images to your Dropbox folder '/Apps/InspirationViewer' to get started."
                    isLoading = false
                }
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load images: \(error.localizedDescription)"
                isLoading = false
            }
            print("❌ Failed to load images: \(error)")
        }
    }
    
    private func extractAllKeywords(from keywordTree: KeywordTree) -> [String] {
        var keywords: [String] = []
        
        func extractRecursive(_ children: [String: KeywordTreeNode]) {
            for (key, node) in children {
                keywords.append(key)
                extractRecursive(node.children)
            }
        }
        
        extractRecursive(keywordTree.children)
        return keywords.sorted()
    }
    
    private func toggleKeyword(_ keyword: String) {
        if selectedKeywords.contains(keyword) {
            selectedKeywords.removeAll { $0 == keyword }
        } else {
            selectedKeywords.append(keyword)
        }
    }
}

struct RefreshButton: View {
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(isLoading)
    }
}

struct KeywordChip: View {
    let keyword: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(keyword)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ImageTileView: View {
    let metadata: ImageMetadata
    @StateObject private var cacheManager = ImageCacheManager.shared
    @State private var image: PlatformImage?
    @State private var isLoading = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .aspectRatio(4/3, contentMode: .fit)
                
                if let image = image {
#if os(macOS)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
#else
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
#endif
                } else {
                    VStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Title and metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(metadata.displayName)
                    .font(.headline)
                    .lineLimit(2)
                
                if let keywords = metadata.keywords, !keywords.isEmpty {
                    Text(keywords.prefix(3).joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        // Check if already cached
        if let cachedImage = cacheManager.getCachedImage(for: metadata) {
            await MainActor.run {
                image = cachedImage
            }
            return
        }
        
        // Download and cache
        await MainActor.run {
            isLoading = true
        }
        
        if let downloadedImage = await cacheManager.downloadAndCacheImage(for: metadata) {
            await MainActor.run {
                image = downloadedImage
                isLoading = false
            }
        } else {
            await MainActor.run {
                isLoading = false
            }
        }
    }
}
