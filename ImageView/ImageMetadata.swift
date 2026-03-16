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
    var children: [String: KeywordTreeNode]
    
    init() {
        children = [:]
    }
    
    // MARK: - Image Filename Management
    
    mutating func addImageToKeyword(_ filename: String, keywordPath: [String]) {
        guard !keywordPath.isEmpty else { return }
        
        // Navigate to the target node, creating intermediate nodes if needed
        addImageToNode(filename, keywordPath: keywordPath, children: &children)
    }
    
    private mutating func addImageToNode(_ filename: String, keywordPath: [String], children: inout [String: KeywordTreeNode]) {
        guard !keywordPath.isEmpty else { return }
        
        let currentKeyword = keywordPath[0]
        let remainingPath = Array(keywordPath.dropFirst())
        
        // Ensure the current node exists
        if children[currentKeyword] == nil {
            children[currentKeyword] = KeywordTreeNode()
        }
        
        var node = children[currentKeyword]!
        
        if remainingPath.isEmpty {
            // This is the target node - add the image filename
            var imageFilenames = node.imageFilenames ?? []
            if !imageFilenames.contains(filename) {
                imageFilenames.append(filename)
                children[currentKeyword] = KeywordTreeNode(imageFilenames: imageFilenames, children: node.children)
            }
        } else {
            // Navigate deeper
            var nodeChildren = node.children
            addImageToNode(filename, keywordPath: remainingPath, children: &nodeChildren)
            children[currentKeyword] = KeywordTreeNode(imageFilenames: node.imageFilenames, children: nodeChildren)
        }
    }
    
    mutating func removeImageFromKeyword(_ filename: String, keywordPath: [String]) {
        guard !keywordPath.isEmpty else { return }
        
        removeImageFromNode(filename, keywordPath: keywordPath, children: &children)
    }
    
    private mutating func removeImageFromNode(_ filename: String, keywordPath: [String], children: inout [String: KeywordTreeNode]) {
        guard !keywordPath.isEmpty else { return }
        
        let currentKeyword = keywordPath[0]
        let remainingPath = Array(keywordPath.dropFirst())
        
        guard var node = children[currentKeyword] else { return }
        
        if remainingPath.isEmpty {
            // This is the target node - remove the image filename
            if var imageFilenames = node.imageFilenames {
                imageFilenames.removeAll { $0 == filename }
                let updatedFilenames = imageFilenames.isEmpty ? nil : imageFilenames
                children[currentKeyword] = KeywordTreeNode(imageFilenames: updatedFilenames, children: node.children)
            }
        } else {
            // Navigate deeper
            var nodeChildren = node.children
            removeImageFromNode(filename, keywordPath: remainingPath, children: &nodeChildren)
            children[currentKeyword] = KeywordTreeNode(imageFilenames: node.imageFilenames, children: nodeChildren)
        }
    }
    
    mutating func removeImageFromAllKeywords(_ filename: String) {
        removeImageFromNode(filename, node: &children)
    }
    
    private mutating func removeImageFromNode(_ filename: String, node: inout [String: KeywordTreeNode]) {
        for (key, var keywordNode) in node {
            // Remove from current node
            if var imageFilenames = keywordNode.imageFilenames {
                imageFilenames.removeAll { $0 == filename }
                keywordNode = KeywordTreeNode(imageFilenames: imageFilenames.isEmpty ? nil : imageFilenames, children: keywordNode.children)
                node[key] = keywordNode
            }
            
            // Recursively remove from children
            var childrenCopy = keywordNode.children
            removeImageFromNode(filename, node: &childrenCopy)
            node[key] = KeywordTreeNode(imageFilenames: keywordNode.imageFilenames, children: childrenCopy)
        }
    }
}

struct KeywordTreeNode: Codable {
    var children: [String: KeywordTreeNode]
    let imageFilenames: [String]?
    
    init(imageFilenames: [String]? = nil, children: [String: KeywordTreeNode] = [:]) {
        self.children = children
        self.imageFilenames = imageFilenames
    }
    
    // MARK: - Helper Properties
    
    var hasImages: Bool {
        return !(imageFilenames?.isEmpty ?? true)
    }
    
    var imageCount: Int {
        return imageFilenames?.count ?? 0
    }
}