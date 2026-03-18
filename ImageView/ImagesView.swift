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
    @State private var sidebarWidth: CGFloat = 200
    @State private var imageWidth: CGFloat = UserDefaults.standard.object(forKey: "ImageWidth") as? CGFloat ?? 250
    
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
        [GridItem(.adaptive(minimum: imageWidth, maximum: imageWidth), spacing: 16)]
#else
        [GridItem(.adaptive(minimum: imageWidth, maximum: imageWidth), spacing: 12)]
#endif
    }
    
    var body: some View {
        Group {
#if os(macOS)
            ResizableSidebarView(
                availableKeywords: availableKeywords,
                selectedKeywords: $selectedKeywords,
                searchText: $searchText,
                filteredImages: filteredImages,
                isLoading: isLoading,
                errorMessage: errorMessage,
                imageWidth: $imageWidth,
                sidebarWidth: $sidebarWidth,
                loadImagesAction: { Task { await loadImages() } },
                onImageWidthChanged: { width in
                    UserDefaults.standard.set(width, forKey: "ImageWidth")
                }
            )
            .frame(minHeight: 300)
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
                        imageWidth: $imageWidth,
                        loadImagesAction: { Task { await loadImages() } },
                        onImageWidthChanged: { width in
                            UserDefaults.standard.set(width, forKey: "ImageWidth")
                        }
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
        }
        .onAppear {
            print("🔍 ImagesView: onAppear called - about to load images")
            print("🔍 ImagesView: Authentication status: \(dropboxService.isAuthenticated())")
            Task {
                await loadImages()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .imagesDidUpdate)) { _ in
            Task {
                await loadImages()
            }
        }
    }
    
    private func loadImages() async {
        print("🔍 Images: Starting loadImages() function")
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        // Test basic connectivity first
        print("📱 Images: Testing Dropbox connectivity...")
        let isConnected = await dropboxService.testConnectivity()
        print("📱 Images: Connectivity result: \(isConnected)")
        
        if !isConnected {
            await MainActor.run {
                errorMessage = "Cannot connect to Dropbox. Please check your internet connection and try again."
                isLoading = false
            }
            print("❌ Images: Connectivity failed - stopping image load")
            return
        }
        print("📱 Images: Connectivity test passed")
        
        // Check authentication status
        print("📱 Images: Checking authentication status...")
        if !dropboxService.isAuthenticated() {
            await MainActor.run {
                errorMessage = "Not authenticated with Dropbox. Please check the Authentication tab."
                isLoading = false
            }
            print("❌ Images: Not authenticated - stopping image load")
            return
        }
        print("📱 Images: Authentication check passed")
        
        // Explore the Dropbox structure for debugging
        print("📱 Images: Exploring Dropbox structure...")
        await dropboxService.exploreDropboxStructure()
        
        do {
            print("📱 Images: Attempting to fetch image list...")
            let loadedImages = try await dropboxService.fetchImageList()
            print("📱 Images: Successfully fetched \(loadedImages.count) images")
            
            // Load available keywords
            do {
                print("📱 Images: Attempting to fetch keywords...")
                let keywordTree = try await dropboxService.fetchKeywords()
                print("📱 Images: Successfully fetched keywords tree with \(keywordTree.children.count) root nodes")
                await MainActor.run {
                    availableKeywords = extractAllKeywords(from: keywordTree)
                }
                print("📱 Images: Extracted \(availableKeywords.count) total keywords")
            } catch {
                print("⚠️ Images: Keywords fetch failed: \(error)")
                print("⚠️ Images: Keywords error type: \(type(of: error))")
                // Continue without keywords - this is normal for new setups
                await MainActor.run {
                    availableKeywords = []
                }
            }
            
            await MainActor.run {
                images = loadedImages
                isLoading = false
            }
            
            print("📱 Images: Successfully loaded \(loadedImages.count) images from Dropbox")
            
            // Show helpful message if no images found
            if loadedImages.isEmpty {
                await MainActor.run {
                    errorMessage = "No images found. Upload images to your Dropbox folder '/Apps/InspirationViewer' to get started."
                    isLoading = false
                }
                print("⚠️ Images: No images found in Dropbox folder")
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load images: \(error.localizedDescription)"
                isLoading = false
            }
            print("❌ Images: Failed to load images with error: \(error)")
            print("❌ Images: Error type: \(type(of: error))")
            print("❌ Images: Error localized description: \(error.localizedDescription)")
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
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
#else
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        print("🖼️ ImageTile: Starting loadImage for \(metadata.filename)")
        
        // Check if already cached
        if let cachedImage = cacheManager.getCachedImage(for: metadata) {
            print("🖼️ ImageTile: Found cached image for \(metadata.filename)")
            await MainActor.run {
                image = cachedImage
            }
            return
        }
        
        print("🖼️ ImageTile: No cached image, starting download for \(metadata.filename)")
        
        // Download and cache
        await MainActor.run {
            isLoading = true
        }
        
        if let downloadedImage = await cacheManager.downloadAndCacheImage(for: metadata) {
            print("🖼️ ImageTile: Successfully got downloaded image for \(metadata.filename)")
            await MainActor.run {
                image = downloadedImage
                isLoading = false
            }
        } else {
            print("🖼️ ImageTile: Failed to get downloaded image for \(metadata.filename)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Missing View Components

struct KeywordsSidebarView: View {
    let availableKeywords: [String]
    @Binding var selectedKeywords: [String]
    @Binding var searchText: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search images...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            
            // Keywords section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Keywords")
                        .font(.headline)
                    Spacer()
                    if !selectedKeywords.isEmpty {
                        Button("Clear") {
                            selectedKeywords.removeAll()
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal)
                
                if availableKeywords.isEmpty {
                    Text("No keywords available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(availableKeywords, id: \.self) { keyword in
                                KeywordRowView(
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
            
            Spacer() // Push content to top
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func toggleKeyword(_ keyword: String) {
        if selectedKeywords.contains(keyword) {
            selectedKeywords.removeAll { $0 == keyword }
        } else {
            selectedKeywords.append(keyword)
        }
    }
}

struct KeywordRowView: View {
    let keyword: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
                
                Text(keyword)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.vertical, 2)
    }
}

struct ImagesMainView: View {
    let filteredImages: [ImageMetadata]
    let isLoading: Bool
    let errorMessage: String?
    @Binding var searchText: String
    @Binding var selectedKeywords: [String]
    @Binding var imageWidth: CGFloat
    let loadImagesAction: () -> Void
    let onImageWidthChanged: (CGFloat) -> Void
    
    private var gridColumns: [GridItem] {
#if os(macOS)
        [GridItem(.adaptive(minimum: imageWidth, maximum: imageWidth), spacing: 16)]
#else
        [GridItem(.adaptive(minimum: imageWidth, maximum: imageWidth), spacing: 12)]
#endif
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            Group {
                if isLoading {
                    VStack {
                        ProgressView("Loading images...")
                            .scaleEffect(1.2)
                        Text("Please wait while we fetch your images")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        
                        Text("Error Loading Images")
                            .font(.headline)
                        
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        Button("Try Again") {
                            loadImagesAction()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredImages.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        
                        Text("No Images Found")
                            .font(.headline)
                        
                        if selectedKeywords.isEmpty && searchText.isEmpty {
                            Text("Upload images to your Dropbox folder to get started")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No images match your current filters")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                            
                            Button("Clear Filters") {
                                searchText = ""
                                selectedKeywords.removeAll()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(filteredImages) { metadata in
                                ImageTileView(metadata: metadata)
                            }
                        }
                        .padding()
                    }
                }
            }
            
            // Image width slider - Always show for testing
            Divider()
            HStack {
                Image(systemName: "photo.on.rectangle")
                    .foregroundColor(.secondary)
                
                Slider(value: $imageWidth, in: 100...400, step: 10) { editing in
                    if !editing {
                        onImageWidthChanged(imageWidth)
                    }
                }
                
                Image(systemName: "photo.on.rectangle.fill")
                    .foregroundColor(.secondary)
                    .font(.title3)
                
                Text("\(Int(imageWidth))px")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 45, alignment: .trailing)
                
                Text("Images: \(filteredImages.count)")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            .padding()
            .background(Color.yellow.opacity(0.2)) // Make it visible for debugging
        }
    }
}

// MARK: - Resizable Sidebar Layout

struct ResizableSidebarView: View {
    let availableKeywords: [String]
    @Binding var selectedKeywords: [String]
    @Binding var searchText: String
    let filteredImages: [ImageMetadata]
    let isLoading: Bool
    let errorMessage: String?
    @Binding var imageWidth: CGFloat
    @Binding var sidebarWidth: CGFloat
    let loadImagesAction: () -> Void
    let onImageWidthChanged: (CGFloat) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Keywords Sidebar
                KeywordsSidebarView(
                    availableKeywords: availableKeywords,
                    selectedKeywords: $selectedKeywords,
                    searchText: $searchText
                )
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)
                
                // Draggable Divider
                DraggableDivider(
                    sidebarWidth: $sidebarWidth,
                    totalWidth: geometry.size.width
                )
                
                // Main Images View
                ImagesMainView(
                    filteredImages: filteredImages,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    searchText: $searchText,
                    selectedKeywords: $selectedKeywords,
                    imageWidth: $imageWidth,
                    loadImagesAction: loadImagesAction,
                    onImageWidthChanged: onImageWidthChanged
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct DraggableDivider: View {
    @Binding var sidebarWidth: CGFloat
    let totalWidth: CGFloat
    @State private var isDragging = false
    
    var body: some View {
        // Make the entire divider area draggable and more visible for testing
        Rectangle()
            .fill(isDragging ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
            .frame(width: 6)
            .onHover { isHovering in
#if os(macOS)
                if isHovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
#endif
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let newWidth = sidebarWidth + value.translation.width
                        let minWidth: CGFloat = 120
                        let maxWidth: CGFloat = max(minWidth + 50, totalWidth - 300)
                        sidebarWidth = max(minWidth, min(newWidth, maxWidth))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
