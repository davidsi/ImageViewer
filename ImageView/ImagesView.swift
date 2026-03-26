//
//  ImagesView.swift
//  ImageView
//
//  Created by david silver on 2026-03-15.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    @State private var keywordTree: KeywordTree? = nil
    @State private var sidebarWidth: CGFloat = 200
    @State private var imageWidth: CGFloat = UserDefaults.standard.object(forKey: "ImageWidth") as? CGFloat ?? 250
    @State private var isSelectionMode = false
    @State private var selectedImages = Set<String>()
    @State private var showKeywordsOnHover = false // macOS only
    @State private var isGroupViewMode = false
    @State private var currentGroupImages: [String] = []
    @State private var invertResults = false
    
    private var filteredImages: [ImageMetadata] {
        var filtered = images
        
        // If in group view mode, only show images from the current group
        if isGroupViewMode {
            filtered = filtered.filter { image in
                return currentGroupImages.contains(image.filename)
            }
            return filtered // Skip other filters in group view mode
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { image in
                (image.title?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                image.filename.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Filter by selected keywords (including child keywords)
        if !selectedKeywords.isEmpty {
            // Special case: filter for images with zero keywords
            if selectedKeywords.contains("__NO_KEYWORDS__") {
                filtered = filtered.filter { image in
                    // Check if this image has any keyword associations
                    guard let keywordTree = dropboxService.cachedKeywordTree else { return true }
                    return !hasAnyKeywordAssociations(filename: image.filename, in: keywordTree)
                }
            } else {
                // Normal keyword filtering: Get all image filenames associated with selected keywords and their descendants
                let associatedFilenames = getImageFilenamesForKeywords(selectedKeywords)
                
                filtered = filtered.filter { image in
                    let hasKeyword = associatedFilenames.contains(image.filename)
                    return invertResults ? !hasKeyword : hasKeyword
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
            if isGroupViewMode {
                // Group view mode - show only images without sidebar
                ImagesMainView(
                    filteredImages: filteredImages,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    searchText: $searchText,
                    selectedKeywords: $selectedKeywords,
                    imageWidth: $imageWidth,
                    isSelectionMode: $isSelectionMode,
                    selectedImages: $selectedImages,
                    showKeywordsOnHover: $showKeywordsOnHover,
                    invertResults: $invertResults,
                    loadImagesAction: { Task { await loadImages() } },
                    onImageWidthChanged: { width in
                        UserDefaults.standard.set(width, forKey: "ImageWidth")
                    },
                    onCollectCheckedKeywords: collectCheckedKeywords,
                    dropboxService: dropboxService,
                    isGroupViewMode: $isGroupViewMode,
                    onExitGroupViewMode: {
                        isGroupViewMode = false
                        currentGroupImages = []
                    },
                    onEnterGroupViewMode: { filename in
                        print("🔍 Group Debug: Checking groups for image: \(filename)")
                        print("🔍 Group Debug: Total cached groups: \(dropboxService.cachedGroups.count)")
                        
                        let containingGroups = dropboxService.getGroupsContainingImages([filename])
                        print("🔍 Group Debug: Found \(containingGroups.count) groups containing \(filename)")
                        
                        if let firstGroup = containingGroups.first {
                            print("🔍 Group Debug: Entering group view with \(firstGroup.count) images: \(firstGroup.joined(separator: ", "))")
                            currentGroupImages = firstGroup
                            isGroupViewMode = true
                            isSelectionMode = false
                            selectedImages.removeAll()
                        } else {
                            print("🔍 Group Debug: No groups found for image \(filename)")
                        }
                    }
                )
                .navigationTitle("Group View (\(currentGroupImages.count) images)")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        RefreshButton(isLoading: isLoading) {
                            Task { await loadImages() }
                        }
                    }
                }
            } else {
#if os(macOS)
            ResizableSidebarView(
                keywordTree: dropboxService.cachedKeywordTree,
                selectedKeywords: $selectedKeywords,
                searchText: $searchText,
                invertResults: $invertResults,
                filteredImages: filteredImages,
                isLoading: isLoading,
                errorMessage: errorMessage,
                imageWidth: $imageWidth,
                sidebarWidth: $sidebarWidth,
                isSelectionMode: $isSelectionMode,
                selectedImages: $selectedImages,
                showKeywordsOnHover: $showKeywordsOnHover,
                loadImagesAction: { Task { await loadImages() } },
                onImageWidthChanged: { width in
                    UserDefaults.standard.set(width, forKey: "ImageWidth")
                },
                onKeywordToggle: { keyword in
                    toggleKeywordForSelectedImages(keyword)
                },
                onCollectCheckedKeywords: collectCheckedKeywords,
                dropboxService: dropboxService,
                onEnterGroupViewMode: { filename in
                    print("🔍 Group Debug: Checking groups for image: \(filename)")
                    print("🔍 Group Debug: Total cached groups: \(dropboxService.cachedGroups.count)")
                    
                    let containingGroups = dropboxService.getGroupsContainingImages([filename])
                    print("🔍 Group Debug: Found \(containingGroups.count) groups containing \(filename)")
                    
                    if let firstGroup = containingGroups.first {
                        print("🔍 Group Debug: Entering group view with \(firstGroup.count) images: \(firstGroup.joined(separator: ", "))")
                        currentGroupImages = firstGroup
                        isGroupViewMode = true
                        isSelectionMode = false
                        selectedImages.removeAll()
                    } else {
                        print("🔍 Group Debug: No groups found for image \(filename)")
                    }
                },
                onExitGroupViewMode: {
                    isGroupViewMode = false
                    currentGroupImages = []
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
            // Use horizontal layout for iPad, vertical for iPhone
            if UIDevice.current.userInterfaceIdiom == .pad {
                ResizableSidebarView(
                    keywordTree: dropboxService.cachedKeywordTree,
                    selectedKeywords: $selectedKeywords,
                    searchText: $searchText,
                    invertResults: $invertResults,
                    filteredImages: filteredImages,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    imageWidth: $imageWidth,
                    sidebarWidth: $sidebarWidth,
                    isSelectionMode: $isSelectionMode,
                    selectedImages: $selectedImages,
                    showKeywordsOnHover: $showKeywordsOnHover,
                    loadImagesAction: { Task { await loadImages() } },
                    onImageWidthChanged: { width in
                        UserDefaults.standard.set(width, forKey: "ImageWidth")
                    },
                    onKeywordToggle: { keyword in
                        toggleKeywordForSelectedImages(keyword)
                    },
                    onCollectCheckedKeywords: collectCheckedKeywords,
                    dropboxService: dropboxService,
                    onEnterGroupViewMode: { filename in
                        print("🔍 Group Debug: Checking groups for image: \(filename)")
                        print("🔍 Group Debug: Total cached groups: \(dropboxService.cachedGroups.count)")
                        
                        let containingGroups = dropboxService.getGroupsContainingImages([filename])
                        print("🔍 Group Debug: Found \(containingGroups.count) groups containing \(filename)")
                        
                        if let firstGroup = containingGroups.first {
                            print("🔍 Group Debug: Entering group view with \(firstGroup.count) images: \(firstGroup.joined(separator: ", "))")
                            currentGroupImages = firstGroup
                            isGroupViewMode = true
                            isSelectionMode = false
                            selectedImages.removeAll()
                        } else {
                            print("🔍 Group Debug: No groups found for image \(filename)")
                        }
                    },
                    onExitGroupViewMode: {
                        isGroupViewMode = false
                        currentGroupImages = []
                    }
                )
                .frame(minHeight: 300)
                .navigationTitle("Images")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        RefreshButton(isLoading: isLoading) {
                            Task { await loadImages() }
                        }
                    }
                }
            } else {
                // iPhone vertical layout
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
                            isSelectionMode: $isSelectionMode,
                            selectedImages: $selectedImages,
                            showKeywordsOnHover: $showKeywordsOnHover,
                            invertResults: $invertResults,
                            loadImagesAction: { Task { await loadImages() } },
                            onImageWidthChanged: { width in
                                UserDefaults.standard.set(width, forKey: "ImageWidth")
                            },
                            onCollectCheckedKeywords: collectCheckedKeywords,
                            dropboxService: dropboxService,
                            isGroupViewMode: $isGroupViewMode,
                            onExitGroupViewMode: {
                                isGroupViewMode = false
                                currentGroupImages = []
                            },
                            onEnterGroupViewMode: { filename in
                                print("🔍 Group Debug: Checking groups for image: \(filename)")
                                print("🔍 Group Debug: Total cached groups: \(dropboxService.cachedGroups.count)")
                                
                                let containingGroups = dropboxService.getGroupsContainingImages([filename])
                                print("🔍 Group Debug: Found \(containingGroups.count) groups containing \(filename)")
                                
                                if let firstGroup = containingGroups.first {
                                    print("🔍 Group Debug: Entering group view with \(firstGroup.count) images: \(firstGroup.joined(separator: ", "))")
                                    currentGroupImages = firstGroup
                                    isGroupViewMode = true
                                    isSelectionMode = false
                                    selectedImages.removeAll()
                                } else {
                                    print("🔍 Group Debug: No groups found for image \(filename)")
                                }
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
            } // Close the else block for iPad/iPhone check 
#endif
            } // Close the else block for isGroupViewMode  
        } // Close the Group block
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
    } // Close the body
    
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
            
            // Process and rename files to sequential format if needed
            do {
                print("📱 Images: Checking for files that need renaming...")
                try await dropboxService.processAndRenameFiles()
                print("📱 Images: File renaming process completed")
                
                // Refetch image list after potential renaming
                let updatedImages = try await dropboxService.fetchImageList()
                print("📱 Images: Refetched images after renaming: \(updatedImages.count)")
                
                await MainActor.run {
                    images = updatedImages
                }
            } catch {
                print("⚠️ Images: File renaming failed: \(error)")
                // Use original images if renaming fails
                await MainActor.run {
                    images = loadedImages
                }
            }
            
            // Load available keywords
            do {
                print("📱 Images: Attempting to fetch keywords...")
                let fetchedKeywordTree = try await dropboxService.fetchKeywords()
                print("📱 Images: Successfully fetched keywords tree with \(fetchedKeywordTree.children.count) root nodes")
                await MainActor.run {
                    availableKeywords = extractAllKeywords(from: fetchedKeywordTree)
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
                isLoading = false
            }
            
            let finalImageCount = images.count
            print("📱 Images: Successfully loaded \(finalImageCount) images from Dropbox")
            
            // Show helpful message if no images found
            if finalImageCount == 0 {
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
        
        func extractRecursive(_ children: [KeywordTreeNode], currentPath: [String] = []) {
            for node in children {
                let fullPath = currentPath + [node.name]
                let fullKeyword = fullPath.joined(separator: "/")
                keywords.append(fullKeyword)
                extractRecursive(node.children, currentPath: fullPath)
            }
        }
        
        extractRecursive(keywordTree.children)
        return keywords.sorted()
    }
    
    private func toggleKeyword(_ keyword: String) {
        if selectedKeywords.contains(keyword) {
            selectedKeywords.removeAll { $0 == keyword }
            // Reset invert when no keywords are selected
            if selectedKeywords.isEmpty {
                invertResults = false
            }
        } else {
            selectedKeywords.append(keyword)
        }
    }
    
    private func collectCheckedKeywords() -> [String] {
        guard isSelectionMode && !selectedImages.isEmpty else { return selectedKeywords }
        
        // Get selected image filenames
        let selectedMetadata = filteredImages.filter { selectedImages.contains($0.dropboxPath) }
        let selectedFilenames = Set(selectedMetadata.map { $0.filename })
        
        return availableKeywords.filter { keyword in
            // Get filenames associated with this keyword from the tree
            let keywordFilenames = Set(getImageFilenamesForKeyword(keyword, in: dropboxService.cachedKeywordTree ?? KeywordTree()) ?? [])
            
            // Return true if any selected images have this keyword (should be preserved as filter)
            return !selectedFilenames.intersection(keywordFilenames).isEmpty
        }
    }
    
    private func toggleKeywordForSelectedImages(_ keyword: String) {
        print("🔀 ImagesView: toggleKeywordForSelectedImages called for '\(keyword)'")
        print("🔀 ImagesView: isSelectionMode=\(isSelectionMode), selectedImages.count=\(selectedImages.count)")
        
        guard isSelectionMode && !selectedImages.isEmpty else { 
            print("🔀 ImagesView: Exiting - not in selection mode or no images selected")
            return 
        }
        
        // Get the selected image metadata objects to get filenames
        let selectedMetadata = filteredImages.filter { selectedImages.contains($0.dropboxPath) }
        let selectedFilenames = selectedMetadata.map { $0.filename }
        print("🔀 ImagesView: selectedFilenames: \(selectedFilenames)")
        
        // Check current status by looking at keyword tree associations
        let currentlyAssociatedFilenames = (dropboxService.cachedKeywordTree ?? KeywordTree()).getImageFilenamesForKeyword(keyword) ?? []
        let selectedFilenamesSet = Set(selectedFilenames)
        let currentlyAssociatedSet = Set(currentlyAssociatedFilenames)
        
        let intersection = selectedFilenamesSet.intersection(currentlyAssociatedSet)
        print("🔀 ImagesView: intersection.count=\(intersection.count), selectedFilenames.count=\(selectedFilenames.count)")
        
        // Decide the action based on how many selected images already have this keyword
        let shouldAdd: Bool
        if intersection.count == selectedFilenames.count {
            shouldAdd = false  // All selected images have this keyword - remove it
            print("🔀 ImagesView: Will REMOVE keyword (all images already have it)")
        } else {
            shouldAdd = true   // Some or no selected images have this keyword - add it to all
            print("🔀 ImagesView: Will ADD keyword (some/no images have it)")
        }
        
        // Apply the changes to selected images
        Task {
            print("🔀 ImagesView: Starting async task to apply changes")
            do {
                for filename in selectedFilenames {
                    if shouldAdd {
                        print("🔀 ImagesView: Adding '\(filename)' to keyword '\(keyword)'")
                        try await dropboxService.addImageToKeyword(filename: filename, keywordPath: keyword.components(separatedBy: "/"))
                    } else {
                        print("🔀 ImagesView: Removing '\(filename)' from keyword '\(keyword)'")
                        try await dropboxService.removeImageFromKeyword(filename: filename, keywordPath: keyword.components(separatedBy: "/"))
                    }
                }
                // Keyword tree is automatically updated via cache in DropboxService methods
                print("🔀 ImagesView: Keyword update completed")
            } catch {
                print("❌ ImagesView: Error toggling keyword for selected images: \(error)")
            }
        }
    }
    
    private func getDescendantKeywords(_ keyword: String) -> [String] {
        guard let keywordTree = dropboxService.cachedKeywordTree else { return [] }
        
        var descendants: [String] = []
        
        func traverseNode(_ node: KeywordTreeNode, currentPath: [String]) {
            for childNode in node.children {
                let fullPath = currentPath + [childNode.name]
                let fullKeyword = fullPath.joined(separator: "/")
                descendants.append(fullKeyword)
                traverseNode(childNode, currentPath: fullPath)
            }
        }
        
        // Parse the selected keyword to get its path components
        let keywordPath = keyword.components(separatedBy: "/")
        
        // Navigate to the selected keyword's node
        var currentNode: KeywordTreeNode? = nil
        var currentChildren = keywordTree.children
        
        for pathComponent in keywordPath {
            var foundNode: KeywordTreeNode? = nil
            for node in currentChildren {
                if node.name == pathComponent {
                    foundNode = node
                    currentChildren = node.children
                    break
                }
            }
            if let node = foundNode {
                currentNode = node
            } else {
                return [] // Keyword not found in tree
            }
        }
        
        // If we found the node, traverse all its descendants
        if let node = currentNode {
            traverseNode(node, currentPath: keywordPath)
        }
        
        return descendants
    }
    
    private func getImageFilenamesForKeywords(_ selectedKeywords: [String]) -> Set<String> {
        guard let keywordTree = dropboxService.cachedKeywordTree else { return [] }
        guard !selectedKeywords.isEmpty else { return [] }
        
        // Start with filenames from the first keyword (including descendants)
        var resultFilenames: Set<String>? = nil
        
        for keyword in selectedKeywords {
            var keywordFilenames = Set<String>()
            
            // Get filenames for the selected keyword itself
            if let filenames = getImageFilenamesForKeyword(keyword, in: keywordTree) {
                keywordFilenames.formUnion(filenames)
            }
            
            // Get filenames for all descendant keywords
            let descendants = getDescendantKeywords(keyword)
            for descendant in descendants {
                if let filenames = getImageFilenamesForKeyword(descendant, in: keywordTree) {
                    keywordFilenames.formUnion(filenames)
                }
            }
            
            // For the first keyword, initialize the result set
            if resultFilenames == nil {
                resultFilenames = keywordFilenames
            } else {
                // For subsequent keywords, intersect with existing results (AND logic)
                resultFilenames = resultFilenames!.intersection(keywordFilenames)
            }
        }
        
        return resultFilenames ?? []
    }
    
    private func getImageFilenamesForKeyword(_ keyword: String, in keywordTree: KeywordTree) -> [String]? {
        // Use the KeywordTree's built-in method instead of reimplementing
        return keywordTree.getImageFilenamesForKeyword(keyword)
    }
    
    private func hasAnyKeywordAssociations(filename: String, in keywordTree: KeywordTree) -> Bool {
        return hasKeywordAssociations(filename: filename, in: keywordTree.children)
    }
    
    private func hasKeywordAssociations(filename: String, in nodes: [KeywordTreeNode]) -> Bool {
        for node in nodes {
            // Check if this node contains the filename
            if node.images.contains(filename) {
                return true
            }
            
            // Recursively check children
            if hasKeywordAssociations(filename: filename, in: node.children) {
                return true
            }
        }
        return false
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
    let isSelectionMode: Bool
    let isSelected: Bool
    let showKeywordsOnHover: Bool
    let onSelectionToggle: () -> Void
    let dropboxService: DropboxService
    let onGroupTap: () -> Void
    
    @StateObject private var cacheManager = ImageCacheManager.shared
    @State private var image: PlatformImage?
    @State private var isLoading = false
    @State private var showingKeywordsPopup = false
    @State private var isHovering = false
    
    private var isInGroup: Bool {
        let result = dropboxService.areImagesInGroups([metadata.filename])
        // Only log occasionally to avoid spam
        if result {
            print("🏷️ ImageTile: \(metadata.filename) is IN a group (showing group icon)")
        }
        return result
    }
    
    private var imageKeywords: [String] {
        guard let keywordTree = dropboxService.cachedKeywordTree else { return [] }
        return getKeywordsForImage(filename: metadata.filename, in: keywordTree.children)
    }
    
    // Computed properties to break up complex expressions for type checker
    private var overlayBorders: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    (showKeywordsOnHover && !imageKeywords.isEmpty) 
                        ? Color.orange.opacity(0.8) 
                        : Color.gray.opacity(0.3), 
                    lineWidth: (showKeywordsOnHover && !imageKeywords.isEmpty) ? 2 : 1
                )
            
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
        }
    }
    
#if os(macOS)
    private var hoverKeywords: some View {
        Group {
            if showKeywordsOnHover && isHovering && !imageKeywords.isEmpty {
                keywordsPopupContent
                    .offset(x: -10, y: 10) // Position in bottom-right corner
                    .zIndex(1001)
                    .allowsHitTesting(false)
            }
        }
    }
    
    private var hoverKeywordsOverlay: some View {
        Group {
            if showKeywordsOnHover && isHovering && !imageKeywords.isEmpty {
                GeometryReader { geometry in
                    keywordsPopupContent
                        .position(
                            x: geometry.size.width - 10,  // Near right edge
                            y: geometry.size.height - 10  // Near bottom edge
                        )
                        .zIndex(999)
                        .allowsHitTesting(false)
                }
                .zIndex(999)
            }
        }
    }
    
    private var keywordsPopupContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Filename header
            Text(metadata.filename)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            if !imageKeywords.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.3))
                
                // Keywords list
                ForEach(imageKeywords.prefix(5), id: \.self) { keyword in
                    Text(keyword)
                        .font(.caption)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                if imageKeywords.count > 5 {
                    Text("...and \(imageKeywords.count - 5) more")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.9))
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        )
    }
#endif
    
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
                
                // Keywords info icon (top left, only visible if image has keywords)
                // Hidden on macOS since hover functionality replaces it
#if !os(macOS)
                if !imageKeywords.isEmpty {
                    VStack {
                        HStack {
                            Button(action: {
                                showingKeywordsPopup = true
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.9))
                                        .frame(width: 20, height: 20)
                                    
                                    Image(systemName: "tag.fill")
                                        .foregroundColor(.white)
                                        .font(.caption2)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                }
#endif
                
                // Selection overlay
                if isSelectionMode {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.9))
                                    .frame(width: 24, height: 24)
                                
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? .blue : .gray)
                                    .font(.title3)
                            }
                            .padding(8)
                        }
                        Spacer()
                    }
                }
                
                // Group indicator overlay (when NOT in selection mode)
                if !isSelectionMode && isInGroup {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onGroupTap) {
                                ZStack {
                                    Circle()
                                        .fill(Color.orange.opacity(0.9))
                                        .frame(width: 24, height: 24)
                                    
                                    Image(systemName: "rectangle.3.group.fill")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            .overlay(overlayBorders)
            .onTapGesture {
                if isSelectionMode {
                    onSelectionToggle()
                }
            }
#if os(macOS)
            .onHover { hovering in
                isHovering = hovering
                if hovering && !imageKeywords.isEmpty {
                    print("🖱️ Hover Debug: Image \(metadata.filename) - hovering=\(hovering), showKeywordsOnHover=\(showKeywordsOnHover), keywords=\(imageKeywords.count)")
                }
            }
                        .overlay(hoverKeywords, alignment: .topTrailing)
#endif
            .popover(isPresented: $showingKeywordsPopup) {
                KeywordsPopupView(keywords: imageKeywords, filename: metadata.filename)
#if os(macOS)
                    .frame(minWidth: 200, maxWidth: 300)
#endif
            }
            
            // No metadata display needed - selection checkboxes show keyword state
        }
        .task {
            await loadImage()
        }
    }
    
    private func getKeywordsForImage(filename: String, in nodes: [KeywordTreeNode], parentPath: String = "") -> [String] {
        var keywords: [String] = []
        
        for node in nodes {
            let currentPath = parentPath.isEmpty ? node.name : "\(parentPath)/\(node.name)"
            
            // Check if this node contains the filename
            if node.images.contains(filename) {
                keywords.append(currentPath)
            }
            
            // Recursively check children
            keywords.append(contentsOf: getKeywordsForImage(filename: filename, in: node.children, parentPath: currentPath))
        }
        
        return keywords
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

struct KeywordsPopupView: View {
    let keywords: [String]
    let filename: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keywords")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(filename)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            
            Divider()
            
            // Keywords list
            if keywords.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tag.slash")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("No keywords assigned")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(keywords.sorted(), id: \.self) { keyword in
                            HStack {
                                Image(systemName: "tag")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                
                                Text(keyword)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            
#if os(iOS)
            // Dismiss button for iOS
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
#endif
        }
        .padding()
#if os(macOS)
        .frame(minWidth: 200, maxWidth: 300, minHeight: 100)
#else 
        .frame(minWidth: 250, maxWidth: 350, minHeight: 150)
#endif
    }
}

// MARK: - Missing View Components

struct KeywordsSidebarView: View {
    let keywordTree: KeywordTree?
    @Binding var selectedKeywords: [String]
    @Binding var searchText: String
    @Binding var invertResults: Bool
    let isSelectionMode: Bool
    let selectedImages: Set<String>
    let filteredImages: [ImageMetadata]
    let onKeywordToggle: (String) -> Void
    
    @State private var expandedNodes: Set<String> = []
    
    private func keywordStatusForSelectedImages(_ keyword: String) -> KeywordStatus {
        guard isSelectionMode && !selectedImages.isEmpty else {
            return selectedKeywords.contains(keyword) ? .selected : .unselected
        }
        
        // Get selected image filenames
        let selectedMetadata = filteredImages.filter { selectedImages.contains($0.dropboxPath) }
        let selectedFilenames = Set(selectedMetadata.map { $0.filename })
        
        // Get filenames associated with this keyword from the tree
        let keywordFilenames = Set((keywordTree ?? KeywordTree()).getImageFilenamesForKeyword(keyword) ?? [])
        
        // Find intersection
        let intersection = selectedFilenames.intersection(keywordFilenames)
        
        if intersection.count == selectedFilenames.count {
            return .allSelected
        } else if intersection.count > 0 {
            return .partiallySelected
        } else {
            return .noneSelected
        }
    }
    
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
            
            // Zero keywords filter button
            HStack {
                Button(action: {
                    if selectedKeywords.contains("__NO_KEYWORDS__") {
                        selectedKeywords.removeAll { $0 == "__NO_KEYWORDS__" }
                    } else {
                        selectedKeywords.removeAll()
                        selectedKeywords.append("__NO_KEYWORDS__")
                    }
                }) {
                    HStack {
                        Image(systemName: selectedKeywords.contains("__NO_KEYWORDS__") ? "tag.slash.fill" : "tag.slash")
                            .foregroundColor(selectedKeywords.contains("__NO_KEYWORDS__") ? .white : .orange)
                        Text("Images with Zero Keywords")
                            .foregroundColor(selectedKeywords.contains("__NO_KEYWORDS__") ? .white : .orange)
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedKeywords.contains("__NO_KEYWORDS__") ? Color.orange : Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                Spacer()
            }
            .padding(.horizontal)
            
            // Keywords section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Keywords")
                        .font(.headline)
                    Spacer()
                    if !selectedKeywords.isEmpty && !isSelectionMode {
                        Button("Clear") {
                            selectedKeywords.removeAll()
                            invertResults = false // Reset invert when clearing
                        }
                        .font(.caption)
                    }
                    if keywordTree != nil && !isSelectionMode {
                        Button(invertResults ? "Show Match" : "Show Inverse") {
                            invertResults.toggle()
                        }
                        .font(.caption)
                        .foregroundColor(invertResults ? .orange : .blue)
                        .disabled(selectedKeywords.isEmpty)
                    }
                    if isSelectionMode && !selectedImages.isEmpty {
                        Text("\(selectedImages.count) images")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                
                ScrollView {
                    if let tree = keywordTree {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(tree.children, id: \.name) { node in
                                KeywordTreeNodeView(
                                    keyword: node.name,
                                    fullKeywordPath: node.name,
                                    node: node,
                                    level: 0,
                                    selectedKeywords: $selectedKeywords,
                                    expandedNodes: $expandedNodes,
                                    isSelectionMode: isSelectionMode,
                                    hasSelectedImages: !selectedImages.isEmpty,
                                    keywordStatusProvider: keywordStatusForSelectedImages,
                                    onKeywordToggle: onKeywordToggle
                                )
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        Text("No keywords available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                }
            }
            
            Spacer() // Push content to top
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

enum KeywordStatus {
    case selected // Normal mode: keyword is in filter
    case unselected // Normal mode: keyword not in filter
    case allSelected // Selection mode: all selected images have this keyword
    case partiallySelected // Selection mode: some selected images have this keyword
    case noneSelected // Selection mode: no selected images have this keyword
}

struct KeywordTreeNodeView: View {
    let keyword: String  // Display name (just the node name)
    let fullKeywordPath: String  // Full path from root (e.g., "animals/cats")
    let node: KeywordTreeNode
    let level: Int
    @Binding var selectedKeywords: [String]
    @Binding var expandedNodes: Set<String>
    let isSelectionMode: Bool
    let hasSelectedImages: Bool
    let keywordStatusProvider: (String) -> KeywordStatus
    let onKeywordToggle: (String) -> Void
    
    private var isExpanded: Bool {
        expandedNodes.contains(fullKeywordPath)
    }
    
    private var keywordStatus: KeywordStatus {
        keywordStatusProvider(fullKeywordPath)
    }
    
    private var hasChildren: Bool {
        !node.children.isEmpty
    }
    
    private var checkboxIcon: String {
        switch keywordStatus {
        case .selected, .allSelected:
            return "checkmark.square.fill"
        case .partiallySelected:
            return "minus.square.fill"
        case .unselected, .noneSelected:
            return "square"
        }
    }
    
    private var checkboxColor: Color {
        switch keywordStatus {
        case .selected, .allSelected:
            return .blue
        case .partiallySelected:
            return .orange
        case .unselected, .noneSelected:
            return .secondary
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Current node
            HStack(spacing: 4) {
                // Indentation
                ForEach(0..<level, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 20, height: 1)
                }
                
                // Expand/Collapse button
                if hasChildren {
                    Button(action: { toggleExpanded() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(width: 20, alignment: .leading)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 20, height: 1)
                }
                
                // Keyword selection
                Button(action: { toggleKeyword() }) {
                    HStack(spacing: 8) {
                        Image(systemName: checkboxIcon)
                            .foregroundColor(checkboxColor)
                            .font(.caption)
                        
                        Text(keyword)
                            .font(hasSelectedImages ? .body.italic() : .body)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())
            }
            .padding(.vertical, 2)
            
            // Children nodes (if expanded)
            if isExpanded && hasChildren {
                ForEach(node.children, id: \.name) { childNode in
                    KeywordTreeNodeView(
                        keyword: childNode.name,
                        fullKeywordPath: fullKeywordPath + "/" + childNode.name,
                        node: childNode,
                        level: level + 1,
                        selectedKeywords: $selectedKeywords,
                        expandedNodes: $expandedNodes,
                        isSelectionMode: isSelectionMode,
                        hasSelectedImages: hasSelectedImages,
                        keywordStatusProvider: keywordStatusProvider,
                        onKeywordToggle: onKeywordToggle
                    )
                }
            }
        }
    }
    
    private func toggleExpanded() {
        if isExpanded {
            expandedNodes.remove(fullKeywordPath)
        } else {
            expandedNodes.insert(fullKeywordPath)
        }
    }
    
    private func toggleKeyword() {
        print("🔘 KeywordTreeNodeView: toggleKeyword called for '\(fullKeywordPath)', isSelectionMode: \(isSelectionMode)")
        
        if isSelectionMode {
            // In selection mode, toggle keyword for selected images using full path
            print("🔘 KeywordTreeNodeView: Calling onKeywordToggle for '\(fullKeywordPath)'")
            onKeywordToggle(fullKeywordPath)
        } else {
            // In normal mode, toggle keyword filter using full path
            if selectedKeywords.contains(fullKeywordPath) {
                selectedKeywords.removeAll { $0 == fullKeywordPath }
                print("🔘 KeywordTreeNodeView: Removed '\(fullKeywordPath)' from filter")
            } else {
                selectedKeywords.append(fullKeywordPath)
                print("🔘 KeywordTreeNodeView: Added '\(fullKeywordPath)' to filter")
            }
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
    @Binding var isSelectionMode: Bool
    @Binding var selectedImages: Set<String>
    @Binding var showKeywordsOnHover: Bool
    @Binding var invertResults: Bool
    let loadImagesAction: () -> Void
    let onImageWidthChanged: (CGFloat) -> Void
    let onCollectCheckedKeywords: () -> [String]
    @ObservedObject var dropboxService: DropboxService
    @Binding var isGroupViewMode: Bool
    let onExitGroupViewMode: () -> Void
    let onEnterGroupViewMode: (String) -> Void
    
    private var gridColumns: [GridItem] {
#if os(macOS)
        [GridItem(.adaptive(minimum: imageWidth, maximum: imageWidth), spacing: 16)]
#else
        [GridItem(.adaptive(minimum: imageWidth, maximum: imageWidth), spacing: 12)]
#endif
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Local toolbar for images subpane
            HStack {
                Button(action: {
                    if isGroupViewMode {
                        // Exit group view mode
                        onExitGroupViewMode()
                    } else if isSelectionMode {
                        // Simply exit selection mode without preserving keywords
                        isSelectionMode = false
                        selectedImages.removeAll()
                    } else {
                        // Enter selection mode
                        isSelectionMode = true
                    }
                }) {
                    Text(isGroupViewMode ? "Exit Group Mode" : (isSelectionMode ? "Done" : "Select"))
                        .foregroundColor(isGroupViewMode ? .orange : (isSelectionMode ? .red : .blue))
                        .font(.body)
                }
                
#if os(macOS)
                // Show Keywords checkbox (macOS only)
                if !isGroupViewMode {
                    Button(action: {
                        showKeywordsOnHover.toggle()
                    }) {
                        HStack {
                            Image(systemName: showKeywordsOnHover ? "checkmark.square.fill" : "square")
                                .foregroundColor(showKeywordsOnHover ? .blue : .secondary)
                            Text("Show Keywords")
                                .foregroundColor(.primary)
                        }
                        .font(.body)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
#endif
                
                // Save button next to Done/Select button (left-aligned)
                if isSelectionMode && !selectedImages.isEmpty {
                    Button(action: {
                        Task {
                            do {
                                // Get current cached keyword tree and save it to Dropbox
                                if let keywordTree = DropboxService.shared.cachedKeywordTree {
                                    try await DropboxService.shared.saveKeywords(keywordTree)
                                    print("💾 Successfully saved keyword associations to Dropbox")
                                } else {
                                    print("⚠️ No cached keyword tree to save")
                                }
                            } catch {
                                print("❌ Failed to save keyword associations: \(error)")
                            }
                            
                            // Exit selection mode after save attempt (success or failure)
                            await MainActor.run {
                                isSelectionMode = false
                                selectedImages.removeAll()
                            }
                        }
                    }) {
                        Text("Save")
                            .foregroundColor(.green)
                            .font(.body)
                    }
                    
                    // Group button next to Save button
                    Button(action: {
                        Task {
                            do {
                                // Extract filenames from selected dropbox paths (same as keywords do)
                                let selectedMetadata = filteredImages.filter { selectedImages.contains($0.dropboxPath) }
                                let selectedFilenames = selectedMetadata.map { $0.filename }
                                try await dropboxService.addImagesToGroup(selectedFilenames)
                                print("📦 Successfully grouped \(selectedFilenames.count) images: \(selectedFilenames)")
                            } catch {
                                print("❌ Failed to create group: \(error)")
                            }
                        }
                    }) {
                        Text("Group")
                            .foregroundColor(.orange)
                            .font(.body)
                    }
                    
                    // Clear Keyword Names button next to Group button
                    Button(action: {
                        Task {
                            do {
                                // Extract filenames from selected dropbox paths
                                let selectedMetadata = filteredImages.filter { selectedImages.contains($0.dropboxPath) }
                                let selectedFilenames = selectedMetadata.map { $0.filename }
                                
                                // Remove all keyword associations from selected images
                                if let keywordTree = DropboxService.shared.cachedKeywordTree {
                                    // Get all keywords that have associations with the selected images
                                    let allKeywords = collectAllKeywords(from: keywordTree.children)
                                    
                                    // Remove each selected image from all keywords
                                    for keyword in allKeywords {
                                        let keywordPath = keyword.components(separatedBy: "/")
                                        for filename in selectedFilenames {
                                            try await DropboxService.shared.removeImageFromKeyword(filename: filename, keywordPath: keywordPath)
                                        }
                                    }
                                    
                                    print("🗑️ Successfully cleared all keyword associations from \(selectedFilenames.count) images")
                                } else {
                                    print("⚠️ No cached keyword tree available")
                                }
                            } catch {
                                print("❌ Failed to clear keyword associations: \(error)")
                            }
                        }
                    }) {
                        Text("Clear Keyword Names")
                            .foregroundColor(.purple)
                            .font(.body)
                    }
                    
                    // Ungroup button next to Group button
                    Button(action: {
                        Task {
                            do {
                                // Extract filenames from selected dropbox paths (same as keywords do)
                                let selectedMetadata = filteredImages.filter { selectedImages.contains($0.dropboxPath) }
                                let selectedFilenames = selectedMetadata.map { $0.filename }
                                try await dropboxService.removeImagesFromGroups(selectedFilenames)
                                print("📦 Successfully ungrouped \(selectedFilenames.count) images: \(selectedFilenames)")
                            } catch {
                                print("❌ Failed to ungroup images: \(error)")
                            }
                        }
                    }) {
                        Text("Ungroup")
                            .foregroundColor(.purple)
                            .font(.body)
                    }
                    .disabled(!dropboxService.areImagesInGroups(filteredImages.filter { selectedImages.contains($0.dropboxPath) }.map { $0.filename }))
                }
                
                Spacer()
                
                if isSelectionMode && !selectedImages.isEmpty {
                    Text("\(selectedImages.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            
            Divider()
            
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
                                ImageTileView(
                                    metadata: metadata,
                                    isSelectionMode: isSelectionMode,
                                    isSelected: selectedImages.contains(metadata.dropboxPath),
                                    showKeywordsOnHover: showKeywordsOnHover,
                                    onSelectionToggle: {
                                        if selectedImages.contains(metadata.dropboxPath) {
                                            selectedImages.remove(metadata.dropboxPath)
                                        } else {
                                            selectedImages.insert(metadata.dropboxPath)
                                        }
                                    },
                                    dropboxService: dropboxService,
                                    onGroupTap: {
                                        print("🔘 Group Icon: Clicked for image \(metadata.filename)")
                                        // Enter group view mode for this image
                                        onEnterGroupViewMode(metadata.filename)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 60) // Extra bottom padding to prevent cropping
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
    
    private func collectAllKeywords(from nodes: [KeywordTreeNode], parentPath: String = "") -> [String] {
        var keywords: [String] = []
        
        for node in nodes {
            let currentPath = parentPath.isEmpty ? node.name : "\(parentPath)/\(node.name)"
            keywords.append(currentPath)
            
            // Recursively collect keywords from children
            keywords.append(contentsOf: collectAllKeywords(from: node.children, parentPath: currentPath))
        }
        
        return keywords
    }
}

// MARK: - Resizable Sidebar Layout

struct ResizableSidebarView: View {
    let keywordTree: KeywordTree?
    @Binding var selectedKeywords: [String]
    @Binding var searchText: String
    @Binding var invertResults: Bool
    let filteredImages: [ImageMetadata]
    let isLoading: Bool
    let errorMessage: String?
    @Binding var imageWidth: CGFloat
    @Binding var sidebarWidth: CGFloat
    @Binding var isSelectionMode: Bool
    @Binding var selectedImages: Set<String>
    @Binding var showKeywordsOnHover: Bool
    let loadImagesAction: () -> Void
    let onImageWidthChanged: (CGFloat) -> Void
    let onKeywordToggle: (String) -> Void
    let onCollectCheckedKeywords: () -> [String]
    @ObservedObject var dropboxService: DropboxService
    let onEnterGroupViewMode: (String) -> Void
    let onExitGroupViewMode: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Keywords Sidebar
                KeywordsSidebarView( keywordTree: keywordTree, selectedKeywords: $selectedKeywords, searchText: $searchText, invertResults: $invertResults, isSelectionMode: isSelectionMode, selectedImages: selectedImages,
                                     filteredImages: filteredImages, onKeywordToggle: onKeywordToggle )
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
                    isSelectionMode: $isSelectionMode,
                    selectedImages: $selectedImages,
                    showKeywordsOnHover: $showKeywordsOnHover,
                    invertResults: .constant(false),
                    loadImagesAction: loadImagesAction,
                    onImageWidthChanged: onImageWidthChanged,
                    onCollectCheckedKeywords: onCollectCheckedKeywords,
                    dropboxService: dropboxService,
                    isGroupViewMode: .constant(false),
                    onExitGroupViewMode: onExitGroupViewMode,
                    onEnterGroupViewMode: onEnterGroupViewMode
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
