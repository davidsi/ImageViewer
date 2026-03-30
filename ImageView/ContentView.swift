//
//  ContentView.swift
//  ImageView
//
//  Created by david silver on 2026-03-12.
//

import SwiftUI
import SwiftData
#if os(macOS)
import CloudKit
#endif
import Photos

struct ContentView: View {
    enum SidebarSelection: Hashable {
        case authentication, images, keywordEdit, localDrive, item(Item)
        #if os(macOS)
        case iCloudPhotos
        #endif
    }
    @State private var selection: SidebarSelection? = nil
    @State private var hasSetInitialSelection = false
    
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    
    #if os(macOS)
    @State private var cloudKitAvailable = false  // For app data syncing  
    @State private var checkingCloudKit = true
    @State private var cloudKitError: String?
    @State private var hasCheckedCloudKit = false  // Prevent multiple checks
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var dropboxAuthManager: DropboxAuthManager

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            switch selection {
            case .authentication:
                #if os(macOS)
                AuthenticationView(
                    iCloudAvailable: cloudKitAvailable,  // CloudKit status for app data
                    openICloudSettings: openICloudSettings
                )
                #else
                AuthenticationView(
                    iCloudAvailable: true, // Always true for iOS since we don't need CloudKit
                    openICloudSettings: {}
                )
                #endif
            case .images:
                ImagesView()
            case .keywordEdit:
                KeywordEditView()
            #if os(macOS)
            case .iCloudPhotos:
                // Photos access doesn't require CloudKit - it uses Photos framework
                iCloudPhotosView()
            #endif
            case .localDrive:
                #if os(macOS)
                LocalDriveView()
                #else
                iCloudPhotosView() // On iOS, this is actually just photo library access
                #endif
            case .item(let item):
                Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
            case nil:
                Text("Select an item")
            }
        }
    }
    
    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $selection) {
            // Always show authentication for debugging
            NavigationLink("Authentication", value: SidebarSelection.authentication)
                .disabled(false)
            NavigationLink("Images", value: SidebarSelection.images)
                .disabled(!dropboxAuthManager.isAuthenticated)
            NavigationLink("Keyword edit", value: SidebarSelection.keywordEdit)
                .disabled(!dropboxAuthManager.isAuthenticated)
            #if os(macOS)
            NavigationLink("iCloud Photos", value: SidebarSelection.iCloudPhotos)
                .disabled(!dropboxAuthManager.isAuthenticated) // Only require Dropbox, not iCloud
            NavigationLink("Local Drive", value: SidebarSelection.localDrive)
                .disabled(!dropboxAuthManager.isAuthenticated)
            #else
            NavigationLink("Photos", value: SidebarSelection.localDrive)
                .disabled(false)
            #endif
            
            #if os(macOS)
            if !checkingCloudKit && !cloudKitAvailable {
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("CloudKit sync disabled")
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                    Text("App data won't sync between devices")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            #endif
            
            #if os(macOS)
            Section(header: Text("Items")) {
                ForEach(items) { item in
                    NavigationLink(value: SidebarSelection.item(item)) {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                    // Don't disable based on iCloud status
                }
                .onDelete(perform: deleteItems)
            }
            #else
            ForEach(items) { item in
                NavigationLink(value: SidebarSelection.item(item)) {
                    Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                }
            }
            .onDelete(perform: deleteItems)
            #endif
        }
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            #endif
            ToolbarItem {
                Button(action: addItem) {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .task {
            #if os(macOS)
            if !hasCheckedCloudKit {
                await checkCloudKitStatus()
            }
            #endif
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                #if os(macOS)
                if !hasCheckedCloudKit && !checkingCloudKit {
                    Task { await checkCloudKitStatus() }
                }
                #endif
            }
        }
        .onChange(of: dropboxAuthManager.isAuthenticated) { isAuthenticated in
            // Set initial selection only once
            if !hasSetInitialSelection {
                hasSetInitialSelection = true
                if isAuthenticated {
                    selection = .images
                    print("🔍 ContentView: Initial selection set to images (authenticated)")
                } else {
                    selection = .authentication
                    print("🔍 ContentView: Initial selection set to authentication (not authenticated)")
                }
            }
        }
    }
    
    #if os(macOS)
    @MainActor
    private func checkCloudKitStatus() async {
        print("🔍 ContentView: checkCloudKitStatus() called - checking CloudKit for app data sync")
        guard !hasCheckedCloudKit && !checkingCloudKit else { return }
        
        print("🔍 ContentView: Starting CloudKit status check...")
        checkingCloudKit = true
        cloudKitError = nil
        hasCheckedCloudKit = true
        
        // Use proper timeout with task racing
        do {
            let isAvailable = try await withThrowingTaskGroup(of: Bool.self) { group in
                // Add CloudKit status check task
                group.addTask {
                    do {
                        print("🔍 ContentView: Calling CKContainer.default().accountStatus()...")
                        let status = try await CKContainer.default().accountStatus()
                        print("🔍 ContentView: CloudKit status received: \(status.rawValue) (\(status))")
                        let available = status == .available
                        print("🔍 ContentView: CloudKit available: \(available)")
                        return available
                    } catch {
                        print("🔍 ContentView: CloudKit error: \(error)")
                        print("🔍 ContentView: Error details: \(String(describing: error))")
                        return false
                    }
                }
                
                // Add timeout task - increased to 10 seconds
                group.addTask {
                    try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    print("🔍 ContentView: CloudKit check timeout reached")
                    throw CancellationError() // Timeout
                }
                
                // Return first completed task result
                let result = try await group.next() ?? false
                group.cancelAll() // Cancel remaining tasks
                return result
            }
            
            await MainActor.run {
                self.cloudKitAvailable = isAvailable
                if !isAvailable {
                    self.cloudKitError = "CloudKit is not available or not signed in"
                    print("🔍 ContentView: CloudKit marked as NOT available")
                } else {
                    print("🔍 ContentView: CloudKit marked as AVAILABLE")
                }
                self.checkingCloudKit = false
                print("🔍 ContentView: CloudKit status check complete. Available: \(isAvailable)")
            }
            
        } catch {
            // Timeout or other error
            await MainActor.run {
                self.cloudKitAvailable = false
                self.cloudKitError = "CloudKit status check timed out"
                self.checkingCloudKit = false
                print("🔍 ContentView: CloudKit status check timed out or failed: \(error)")
            }
        }
    }
    #endif

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }

    #if os(macOS)
    private func openICloudSettings() {
        #if os(iOS)
        if let url = URL(string: "App-Prefs:root=APPLE_ACCOUNT") {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.AppleID-Account") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
    #endif
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}