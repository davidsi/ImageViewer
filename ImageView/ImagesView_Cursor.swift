//
//  ImagesView_Cursor.swift
//  ImageView
//
//  Cursor extension for macOS resize functionality
//

import SwiftUI

#if os(macOS)
import AppKit

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
#endif