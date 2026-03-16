//
//  KeywordEditView.swift
//  ImageView
//
//  Created by david silver on 2026-03-15.
//

import SwiftUI
import SwiftData

struct KeywordEditView: View {
    @StateObject private var dropboxService = DropboxService.shared
    @State private var keywordTree = KeywordTree()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var lastSaveTime: Date?
    @State private var saveTask: Task<Void, Never>?
    @State private var newlyCreatedKeywords: Set<String> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Keyword Editor")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Organize your images with hierarchical keywords")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            
            Divider()
            
            // Main Content
            if isLoading {
                VStack {
                    ProgressView()
                    Text("Loading keywords...")
                        .padding(.top, 8)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Keywords Not Found")
                        .font(.headline)
                        .padding(.top, 4)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .foregroundColor(.secondary)
                    
                    Button("Create New Keywords File") {
                        createNewKeywordsFile()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Keywords Tree Editor
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Keywords tree display
                        if keywordTree.children.isEmpty {
                            VStack {
                                Image(systemName: "tag")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("No keywords yet")
                                    .font(.headline)
                                    .padding(.top, 4)
                                
                                Button("Add your first keyword") {
                                    addRootKeyword()
                                }
                                .buttonStyle(.borderedProminent)
                                .padding(.top, 8)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 60)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(keywordTree.children.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }), id: \.self) { key in
                                    KeywordNodeView(
                                        keyword: key,
                                        node: Binding(
                                            get: { keywordTree.children[key] ?? KeywordTreeNode() },
                                            set: { keywordTree.children[key] = $0 }
                                        ),
                                        level: 0,
                                        onDelete: { deleteRootKeyword(key) },
                                        onRename: { oldName, newName in renameRootKeyword(from: oldName, to: newName) },
                                        onNodeChanged: { markAsChanged() },
                                        startEditingAutomatically: newlyCreatedKeywords.contains(key),
                                        markAsNewlyCreated: markKeywordAsNewlyCreated
                                    )
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                    }
                }
            }
        }
        .navigationTitle(isSaving ? "Keywords (Saving...)" : "Keywords")
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                KeywordToolbarContent(
                    isSaving: isSaving,
                    lastSaveTime: lastSaveTime,
                    isLoading: isLoading,
                    timeAgoString: timeAgoString,
                    refreshAction: { Task { await loadKeywords() } }
                )
            }
#else 
            ToolbarItem(placement: .primaryAction) {
                KeywordToolbarContent(
                    isSaving: isSaving,
                    lastSaveTime: lastSaveTime,
                    isLoading: isLoading,
                    timeAgoString: timeAgoString,
                    refreshAction: { Task { await loadKeywords() } }
                )
            }
#endif
        }
        .task {
            await loadKeywords()
        }
        .onDisappear {
            saveTask?.cancel()
        }
    }
    
    private func loadKeywords() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let loadedTree = try await dropboxService.fetchKeywords()
            await MainActor.run {
                keywordTree = loadedTree
                isLoading = false
            }
            print("📱 Keywords: Loaded keyword tree with \(loadedTree.children.count) root nodes")
            debugPrintKeywordTree(keywordTree)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
            print("❌ Failed to load keywords: \(error)")
        }
    }
    
    private func saveKeywords() async {
        await MainActor.run {
            isSaving = true
        }
        
        print("🔄 Keywords: Starting save operation...")
        debugPrintKeywordTree(keywordTree)
        
        do {
            try await dropboxService.saveKeywords(keywordTree)
            await MainActor.run {
                lastSaveTime = Date()
                isSaving = false
            }
            print("✅ Keywords: Save completed successfully")
        } catch {
            await MainActor.run {
                isSaving = false
                // Could show an alert here
            }
            print("❌ Keywords: Save failed with error: \(error)")
        }
    }
    
    private func createNewKeywordsFile() {
        keywordTree = KeywordTree()
        errorMessage = nil
        markAsChanged()
    }
    
    private func deleteRootKeyword(_ keyword: String) {
        keywordTree.children.removeValue(forKey: keyword)
        markAsChanged()
    }
    
    private func renameRootKeyword(from oldName: String, to newName: String) {
        guard oldName != newName else { return }
        
        if let node = keywordTree.children[oldName] {
            keywordTree.children.removeValue(forKey: oldName)
            keywordTree.children[newName] = node
            markAsChanged()
        }
    }
    
    private func markAsChanged() {
        print("🔄 Keywords: markAsChanged() called - scheduling save")
        
        // Cancel any pending save operation
        saveTask?.cancel()
        
        // Debounce save operations to prevent excessive API calls
        saveTask = Task {
            print("🔄 Keywords: Starting 500ms debounce delay...")
            try? await Task.sleep(for: .milliseconds(500)) // Wait 500ms
            
            // Check if task was cancelled during sleep
            guard !Task.isCancelled else { 
                print("🔄 Keywords: Save task was cancelled")
                return 
            }
            
            print("🔄 Keywords: Debounce delay completed, triggering save")
            await saveKeywords()
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
    
    private func markKeywordAsNewlyCreated(_ keyword: String) {
        newlyCreatedKeywords.insert(keyword)
        // Clear after a delay to prevent the auto-editing from persisting too long
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            newlyCreatedKeywords.remove(keyword)
        }
    }
    
    private func addRootKeyword() {
        let newName = "New Keyword"
        var finalName = newName
        var counter = 1
        
        while keywordTree.children.keys.contains(finalName) {
            finalName = "\(newName) \(counter)"
            counter += 1
        }
        
        keywordTree.children[finalName] = KeywordTreeNode()
        markKeywordAsNewlyCreated(finalName)
        markAsChanged()
    }
    
    private func debugPrintKeywordTree(_ tree: KeywordTree) {
        print("📱 Keywords: Tree structure with image references:")
        debugPrintNode(tree.children, level: 0)
    }
    
    private func debugPrintNode(_ children: [String: KeywordTreeNode], level: Int) {
        let indent = String(repeating: "  ", count: level)
        for (key, node) in children.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
            let imageCount = node.imageFilenames?.count ?? 0
            print("\(indent)- '\(key)' (\(imageCount) images)")
            if let imageFilenames = node.imageFilenames, !imageFilenames.isEmpty {
                print("\(indent)  📸 Images: \(imageFilenames.joined(separator: ", "))")
            }
            debugPrintNode(node.children, level: level + 1)
        }
    }
}

struct KeywordToolbarContent: View {
    let isSaving: Bool
    let lastSaveTime: Date?
    let isLoading: Bool
    let timeAgoString: (Date) -> String
    let refreshAction: () -> Void
    
    var body: some View {
        HStack {
            if isSaving {
                ProgressView()
                    .scaleEffect(0.8)
            } else if let lastSaveTime = lastSaveTime {
                Text("Saved \(timeAgoString(lastSaveTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button("Refresh") {
                refreshAction()
            }
            .disabled(isLoading || isSaving)
        }
    }
}

struct KeywordNodeView: View {
    let keyword: String
    @Binding var node: KeywordTreeNode
    let level: Int
    let onDelete: () -> Void
    let onRename: (String, String) -> Void
    let onNodeChanged: () -> Void
    let startEditingAutomatically: Bool
    let markAsNewlyCreated: ((String) -> Void)?
    
    @State private var isExpanded = true
    @State private var isEditing = false
    @State private var editingName = ""
    @State private var showingDeleteAlert = false
    @FocusState private var isTextFieldFocused: Bool
    
    private var indentWidth: CGFloat {
        CGFloat(level * 20)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Current node row
            HStack {
                // Indent
                if level > 0 {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: indentWidth, height: 1)
                }
                
                // Expand/collapse button (only if has children)
                if !node.children.isEmpty {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                }
                
                // Keyword name (editable)
                if isEditing {
                    TextField("Keyword name", text: $editingName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            finishEditing()
                        }
                        .onAppear {
                            editingName = keyword
                            // Focus and select all text
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isTextFieldFocused = true
                            }
                        }
                } else {
                    Text(keyword)
                        .font(.body)
                        .onTapGesture {
                            startEditing()
                        }
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 8) {
                    // Add child button
                    Button(action: addChild) {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.blue)
                    
                    // Delete button
                    Button(action: { showingDeleteAlert = true }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.red)
                }
            }
            .padding(.vertical, 4)
            .background(level % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))
            
            // Children (if expanded)
            if isExpanded && !node.children.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(node.children.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }), id: \.self) { childKey in
                        KeywordNodeView(
                            keyword: childKey,
                            node: Binding(
                                get: { node.children[childKey] ?? KeywordTreeNode() },
                                set: { node.children[childKey] = $0 }
                            ),
                            level: level + 1,
                            onDelete: { deleteChild(childKey) },
                            onRename: { oldName, newName in renameChild(from: oldName, to: newName) },
                            onNodeChanged: onNodeChanged,
                            startEditingAutomatically: childKey.hasPrefix("New Keyword"),  // Auto-edit if it's a newly created keyword
                            markAsNewlyCreated: markAsNewlyCreated
                        )
                    }
                }
            }
        }
        .alert("Delete Keyword", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete '\(keyword)' and all its sub-keywords? This action cannot be undone.")
        }
        .onAppear {
            if startEditingAutomatically {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    startEditing()
                }
            }
        }
    }
    
    private func startEditing() {
        isEditing = true
        editingName = keyword
    }
    
    private func finishEditing() {
        let trimmedName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && trimmedName != keyword {
            onRename(keyword, trimmedName)
        }
        isEditing = false
    }
    
    private func addChild() {
        let newName = "New Keyword"
        var finalName = newName
        var counter = 1
        
        while node.children.keys.contains(finalName) {
            finalName = "\(newName) \(counter)"
            counter += 1
        }
        
        node.children[finalName] = KeywordTreeNode()
        isExpanded = true // Expand to show the new child
        
        // Mark the new keyword for auto-editing if at root level
        if level == 0 {
            markAsNewlyCreated?(finalName)
        }
        
        onNodeChanged()
    }
    
    private func deleteChild(_ childKey: String) {
        node.children.removeValue(forKey: childKey)
        onNodeChanged()
    }
    
    private func renameChild(from oldName: String, to newName: String) {
        guard oldName != newName else { return }
        
        if let childNode = node.children[oldName] {
            node.children.removeValue(forKey: oldName)
            node.children[newName] = childNode
            onNodeChanged()
        }
    }
}

#Preview {
    KeywordEditView()
}