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
                                ForEach(keywordTree.children, id: \.name) { node in
                                    KeywordNodeView(
                                        keyword: node.name,
                                        node: Binding(
                                            get: { node },
                                            set: { newNode in
                                                if let index = keywordTree.children.firstIndex(where: { $0.name == node.name }) {
                                                    keywordTree.children[index] = newNode
                                                }
                                            }
                                        ),
                                        level: 0,
                                        onDelete: { deleteRootKeyword(node.name) },
                                        onRename: { oldName, newName in renameRootKeyword(from: oldName, to: newName) },
                                        onNodeChanged: { markAsChanged() },
                                        startEditingAutomatically: newlyCreatedKeywords.contains(node.name),
                                        markAsNewlyCreated: markKeywordAsNewlyCreated
                                    )
                                }
                                
                                // Add new keyword button
                                Divider()
                                    .padding(.vertical, 8)
                                
                                Button(action: addRootKeyword) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.blue)
                                        Text("Add Keyword")
                                            .foregroundColor(.blue)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.horizontal)
                                .padding(.bottom)
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
                HStack {
                    Button("Save") {
                        Task {
                            await saveKeywords()
                        }
                    }
                    .disabled(isLoading || isSaving)
                    
                    Button("Refresh") {
                        Task { await loadKeywords() }
                    }
                    .disabled(isLoading || isSaving)
                }
            }
#else 
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button("Save") {
                        Task {
                            await saveKeywords()
                        }
                    }
                    .disabled(isLoading || isSaving)
                    
                    Button("Refresh") {
                        Task { await loadKeywords() }
                    }
                    .disabled(isLoading || isSaving)
                }
            }
#endif
        }
        .task {
            await loadKeywords()
        }
        .onDisappear {
            // No cleanup needed
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
        // Remove from array-based structure
        keywordTree.children.removeAll { node in
            node.name == keyword
        }
        markAsChanged()
    }
    
    private func renameRootKeyword(from oldName: String, to newName: String) {
        guard oldName != newName else { return }
        
        // Find and update in array-based structure
        if let index = keywordTree.children.firstIndex(where: { $0.name == oldName }) {
            keywordTree.children[index].name = newName
            markAsChanged()
        }
    }
    
    private func markAsChanged() {
        print("🔄 Keywords: markAsChanged() called - changes made but not saved")
        // No automatic saving - user must click Save button
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
        
        // Check if name exists in array-based structure
        while keywordTree.children.contains(where: { $0.name == finalName }) {
            finalName = "\(newName) \(counter)"
            counter += 1
        }
        
        // Add to array-based structure
        keywordTree.children.append(KeywordTreeNode(name: finalName, images: [], children: []))
        markKeywordAsNewlyCreated(finalName)
        markAsChanged()
    }
    
    // MARK: - Debug print support functions
    private func debugPrintKeywordTree(_ tree: KeywordTree) {
        print("📱 Keywords: Tree structure with image references:")
        debugPrintNodeArray(tree.children, level: 0)
    }
    
    private func debugPrintNodeArray(_ children: [KeywordTreeNode], level: Int) {
        let indent = String(repeating: "  ", count: level)
        for node in children.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            let imageCount = node.images.count
            print("\(indent)- '\(node.name)' (\(imageCount) images)")
            if !node.images.isEmpty {
                print("\(indent)  📸 Images: \(node.images.joined(separator: ", "))")
            }
            debugPrintNodeArray(node.children, level: level + 1)
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
                    ForEach(node.children.indices, id: \.self) { index in
                        KeywordNodeView(
                            keyword: node.children[index].name,
                            node: Binding(
                                get: { node.children[index] },
                                set: { newNode in
                                    node.children[index] = newNode
                                }
                            ),
                            level: level + 1,
                            onDelete: { deleteChild(index) },
                            onRename: { oldName, newName in renameChild(at: index, to: newName) },
                            onNodeChanged: onNodeChanged,
                            startEditingAutomatically: node.children[index].name.hasPrefix("New Keyword"),  // Auto-edit if it's a newly created keyword
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
        
        // Check if name exists in array-based children
        while node.children.contains(where: { $0.name == finalName }) {
            finalName = "\(newName) \(counter)"
            counter += 1
        }
        
        // Add to array-based structure
        node.children.append(KeywordTreeNode(name: finalName, images: [], children: []))
        isExpanded = true // Expand to show the new child
        
        // Mark the new keyword for auto-editing if at root level
        if level == 0 {
            markAsNewlyCreated?(finalName)
        }
        
        onNodeChanged()
    }
    
    private func deleteChild(_ index: Int) {
        // Remove from array-based structure
        node.children.remove(at: index)
        onNodeChanged()
    }
    
    private func renameChild(at index: Int, to newName: String) {
        // Update name directly
        node.children[index].name = newName
        onNodeChanged()
    }
}

#Preview {
    KeywordEditView()
}