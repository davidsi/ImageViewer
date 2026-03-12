//
//  Item.swift
//  ImageView
//
//  Created by david silver on 2026-03-12.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
