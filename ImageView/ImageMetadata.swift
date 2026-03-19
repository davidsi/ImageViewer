//
//  ImageMetadata.swift
//  ImageView
//
//  Created by david silver on 2026-03-15.
//

import Foundation

struct ImageMetadata: Codable, Identifiable {
    let id = UUID()
    let filename: String
    let title: String?
    let dropboxPath: String
    let fileSize: Int64
    let lastModified: Date
    let contentHash: String?
    let keywords: [String]?
    
    // Local cache properties
    var isDownloaded: Bool = false
    var lastViewed: Date?
    var localPath: String?
    
    // Display name - uses title if available, otherwise filename
    var displayName: String {
        return title ?? filename.replacingOccurrences(of: "\\.[^.]*$", with: "", options: .regularExpression)
    }
    
    private enum CodingKeys: String, CodingKey {
        case filename, title, dropboxPath, fileSize, lastModified, contentHash, keywords
        case isDownloaded, lastViewed, localPath
    }
}

struct KeywordTree: Codable {
    var name: String
    var images: [String]
    var children: [KeywordTreeNode]
    
    init() {
        name = "keywords"
        images = []
        children = []
    }
    
    // MARK: - Image Filename Management
    
    mutating func addImageToKeyword(_ filename: String, keywordPath: [String]) {
        guard !keywordPath.isEmpty else { return }
        
        // Navigate to the target node and add the image
        if keywordPath.count == 1 {
            // Root level keyword
            let keywordName = keywordPath[0]
            
            // Find existing root keyword or create new one
            if let existingIndex = children.firstIndex(where: { $0.name == keywordName }) {
                if !children[existingIndex].images.contains(filename) {
                    children[existingIndex].images.append(filename)
                }
            } else {
                // Create new root keyword
                children.append(KeywordTreeNode(name: keywordName, images: [filename], children: []))
            }
        } else {
            // Multi-level keyword path - more complex navigation needed
            var localChildren = children
            addImageToKeywordRecursive(filename, keywordPath: keywordPath, children: &localChildren)
            children = localChildren
        }
    }
    
    private mutating func addImageToKeywordRecursive(_ filename: String, keywordPath: [String], children: inout [KeywordTreeNode]) {
        guard !keywordPath.isEmpty else { return }
        
        let currentKeyword = keywordPath[0]
        let remainingPath = Array(keywordPath.dropFirst())
        
        if let existingIndex = children.firstIndex(where: { $0.name == currentKeyword }) {
            if remainingPath.isEmpty {
                // This is the target - add image
                if !children[existingIndex].images.contains(filename) {
                    children[existingIndex].images.append(filename)
                }
            } else {
                // Continue recursively
                var childChildren = children[existingIndex].children
                addImageToKeywordRecursive(filename, keywordPath: remainingPath, children: &childChildren)
                children[existingIndex].children = childChildren
            }
        } else {
            // Create new keyword
            if remainingPath.isEmpty {
                children.append(KeywordTreeNode(name: currentKeyword, images: [filename], children: []))
            } else {
                var newNode = KeywordTreeNode(name: currentKeyword, images: [], children: [])
                addImageToKeywordRecursive(filename, keywordPath: remainingPath, children: &newNode.children)
                children.append(newNode)
            }
        }
    }
    
    mutating func removeImageFromKeyword(_ filename: String, keywordPath: [String]) {
        guard !keywordPath.isEmpty else { return }
        var localChildren = children
        removeImageFromKeywordRecursive(filename, keywordPath: keywordPath, children: &localChildren)
        children = localChildren
    }
    
    private mutating func removeImageFromKeywordRecursive(_ filename: String, keywordPath: [String], children: inout [KeywordTreeNode]) {
        guard !keywordPath.isEmpty else { return }
        
        let currentKeyword = keywordPath[0]
        let remainingPath = Array(keywordPath.dropFirst())
        
        if let existingIndex = children.firstIndex(where: { $0.name == currentKeyword }) {
            if remainingPath.isEmpty {
                // This is the target - remove image
                children[existingIndex].images.removeAll { $0 == filename }
            } else {
                // Continue recursively
                var childChildren = children[existingIndex].children
                removeImageFromKeywordRecursive(filename, keywordPath: remainingPath, children: &childChildren)
                children[existingIndex].children = childChildren
            }
        }
    }
    
    mutating func removeImageFromAllKeywords(_ filename: String) {
        var localChildren = children
        removeImageFromAllNodesRecursive(filename, children: &localChildren)
        children = localChildren
    }
    
    private mutating func removeImageFromAllNodesRecursive(_ filename: String, children: inout [KeywordTreeNode]) {
        for i in children.indices {
            // Remove filename from current node
            children[i].images.removeAll { $0 == filename }
            
            // Recursively process children
            var childChildren = children[i].children
            removeImageFromAllNodesRecursive(filename, children: &childChildren)
            children[i].children = childChildren
        }
    }
    
    mutating func updateFilenameInAllKeywords(from oldFilename: String, to newFilename: String) {
        var localChildren = children
        updateFilenameRecursive(from: oldFilename, to: newFilename, children: &localChildren)
        children = localChildren
    }
    
    private mutating func updateFilenameRecursive(from oldFilename: String, to newFilename: String, children: inout [KeywordTreeNode]) {
        for i in children.indices {
            // Update filename in current node's images array
            for j in children[i].images.indices {
                if children[i].images[j] == oldFilename {
                    children[i].images[j] = newFilename
                }
            }
            
            // Recursively process children
            var childChildren = children[i].children
            updateFilenameRecursive(from: oldFilename, to: newFilename, children: &childChildren)
            children[i].children = childChildren
        }
    }
    
    // MARK: - Query Methods
    
    func getImageFilenamesForKeyword(_ keyword: String) -> [String]? {
        let keywordPath = keyword.components(separatedBy: "/")
        return findKeywordImages(keywordPath, in: children)
    }
    
    private func findKeywordImages(_ keywordPath: [String], in children: [KeywordTreeNode]) -> [String]? {
        guard !keywordPath.isEmpty else { return nil }
        
        let currentKeyword = keywordPath[0]
        let remainingPath = Array(keywordPath.dropFirst())
        
        for node in children {
            if node.name == currentKeyword {
                if remainingPath.isEmpty {
                    return node.images
                } else {
                    return findKeywordImages(remainingPath, in: node.children)
                }
            }
        }
        
        return nil
    }
}

struct KeywordTreeNode: Codable {
    var name: String
    var images: [String]
    var children: [KeywordTreeNode]
    
    init(name: String = "", images: [String] = [], children: [KeywordTreeNode] = []) {
        self.name = name
        self.images = images
        self.children = children
    }
    
    // MARK: - Helper Properties
    
    var hasImages: Bool {
        return !images.isEmpty
    }
    
    var imageCount: Int {
        return images.count
    }
}