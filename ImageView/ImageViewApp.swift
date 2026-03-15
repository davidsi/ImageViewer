//
//  ImageViewApp.swift
//  ImageView
//
//  Created by david silver on 2026-03-12.
//

import SwiftUI
import SwiftData
import SwiftyDropbox

@main
struct ImageViewApp: App {
    @StateObject private var dropboxAuthManager = DropboxAuthManager()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dropboxAuthManager)
                .onOpenURL { url in
                    // Handle Dropbox OAuth callback
                    _ = dropboxAuthManager.handleURL(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
