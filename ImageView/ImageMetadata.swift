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
        
        // Build the full path by navigating and creating nodes as needed
        var currentChildren = children
        var pathNodes: [(String, KeywordTreeNode?)] = []
        
        // First pass: collect all nodes along the path
        for keyword in keywordPath {
            let node = currentChildren[keyword]
            pathNodes.append((keyword, node))
            currentChildren = node?.children ?? [:]
        }
        
        // Second pass: rebuild the tree from the bottom up
        var newChildren: [String: KeywordTreeNode] = [:]
        
        // Start from the deepest level and work backwards
        for i in (0..<pathNodes.count).reversed() {
            let (keyword, existingNode) = pathNodes[i]
            
            if i == pathNodes.count - 1 {
                // This is the target node - add the image filename
                var imageFilenames = existingNode?.imageFilenames ?? []
                if !imageFilenames.contains(filename) {
                    imageFilenames.append(filename)
                }
                newChildren = [keyword: KeywordTreeNode(imageFilenames: imageFilenames, children: existingNode?.children ?? [:])]
            } else {
                // This is an intermediate node - preserve existing data and add the child
                let childKeyword = pathNodes[i + 1].0
                var nodeChildren = existingNode?.children ?? [:]
                nodeChildren[childKeyword] = newChildren[childKeyword]!
                newChildren = [keyword: KeywordTreeNode(imageFilenames: existingNode?.imageFilenames, children: nodeChildren)]
            }
        }
        
        // Finally, update the root children
        if let (rootKeyword, updatedNode) = newChildren.first {
            children[rootKeyword] = updatedNode
        }
    }
    
    mutating func removeImageFromKeyword(_ filename: String, keywordPath: [String]) {
        guard !keywordPath.isEmpty else { return }
        
        // Build the full path by navigating existing nodes
        var currentChildren = children
        var pathNodes: [(String, KeywordTreeNode?)] = []
        
        // First pass: collect all nodes along the path
        for keyword in keywordPath {
            let node = currentChildren[keyword]
            pathNodes.append((keyword, node))
            if let node = node {
                currentChildren = node.children
            } else {
                // Node doesn't exist, nothing to remove
                return
            }
        }
        
        // Second pass: rebuild the tree from the bottom up
        var newChildren: [String: KeywordTreeNode] = [:]
        
        // Start from the deepest level and work backwards
        for i in (0..<pathNodes.count).reversed() {
            let (keyword, existingNode) = pathNodes[i]
            guard let existingNode = existingNode else { continue }
            
            if i == pathNodes.count - 1 {
                // This is the target node - remove the image filename
                var imageFilenames = existingNode.imageFilenames ?? []
                imageFilenames.removeAll { $0 == filename }
                let updatedFilenames = imageFilenames.isEmpty ? nil : imageFilenames
                newChildren = [keyword: KeywordTreeNode(imageFilenames: updatedFilenames, children: existingNode.children)]
            } else {
                // This is an intermediate node - preserve existing data and add the child
                let childKeyword = pathNodes[i + 1].0
                var nodeChildren = existingNode.children
                if let updatedChild = newChildren[childKeyword] {
                    nodeChildren[childKeyword] = updatedChild
                }
                newChildren = [keyword: KeywordTreeNode(imageFilenames: existingNode.imageFilenames, children: nodeChildren)]
            }
        }
        
        // Finally, update the root children
        if let (rootKeyword, updatedNode) = newChildren.first {
            children[rootKeyword] = updatedNode
        }
    }
    
    mutating func removeImageFromAllKeywords(_ filename: String) {
        children = removeImageFromAllNodes(filename, nodes: children)
    }
    
    private func removeImageFromAllNodes(_ filename: String, nodes: [String: KeywordTreeNode]) -> [String: KeywordTreeNode] {
        var updatedNodes: [String: KeywordTreeNode] = [:]
        
        for (key, node) in nodes {
            // Remove filename from current node
            var imageFilenames = node.imageFilenames ?? []
            imageFilenames.removeAll { $0 == filename }
            let updatedFilenames = imageFilenames.isEmpty ? nil : imageFilenames
            
            // Recursively process children
            let updatedChildren = removeImageFromAllNodes(filename, nodes: node.children)
            
            updatedNodes[key] = KeywordTreeNode(imageFilenames: updatedFilenames, children: updatedChildren)
        }
        
        return updatedNodes
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