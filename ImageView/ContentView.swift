//
//  ContentView.swift
//  ImageView
//
//  Created by david silver on 2026-03-12.
//

import SwiftUI
import SwiftData
import CloudKit
import Photos

struct ContentView: View {
    enum SidebarSelection: Hashable {
        case authentication, images, keywordEdit, iCloudPhotos, item(Item)
    }
    @State private var selection: SidebarSelection? = nil
    
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    
    @State private var iCloudAvailable = false
    @State private var checkingICloud = true
    @State private var iCloudError: String?
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var dropboxAuthManager: DropboxAuthManager

    var body: some View {
        NavigationSplitView {
            if checkingICloud {
                ProgressView("Checking iCloud status…")
            }
            Group {
                List(selection: $selection) {
                    NavigationLink("Authentication", value: SidebarSelection.authentication)
                        .disabled(false)
                    NavigationLink("Images", value: SidebarSelection.images)
                        .disabled(!dropboxAuthManager.isAuthenticated)
                    NavigationLink("Keyword edit", value: SidebarSelection.keywordEdit)
                        .disabled(!dropboxAuthManager.isAuthenticated)
                    NavigationLink("iCloud Photos", value: SidebarSelection.iCloudPhotos)
                        .disabled(!iCloudAvailable)
#if os(macOS)
                    Section(header: Text("Items")) {
                        ForEach(items) { item in
                            NavigationLink(value: SidebarSelection.item(item)) {
                                Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                            }
                            .disabled(!iCloudAvailable)
                        }
                        .onDelete(perform: deleteItems)
                    }
#else
                    ForEach(items) { item in
                        NavigationLink(value: SidebarSelection.item(item)) {
                            Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                        }
                        .disabled(!iCloudAvailable)
                    }
                    .onDelete(perform: deleteItems)
#endif
                }
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
                await checkICloudStatus()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    Task { await checkICloudStatus() }
                }
            }
        } detail: {
            switch selection {
            case .authentication:
                AuthenticationView(
                    iCloudAvailable: iCloudAvailable,
                    openICloudSettings: openICloudSettings
                )
            case .images:
                ImagesView()
            case .keywordEdit:
                KeywordEditView()
            case .iCloudPhotos:
                iCloudPhotosView()
            case .item(let item):
                Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
            case nil:
                Text("Select an item")
            }
        }
    }
    
    private func checkICloudStatus() async {
        checkingICloud = true
        iCloudError = nil
        do {
            let status = try await CKContainer.default().accountStatus()
            if status == .available {
                iCloudAvailable = true
            } else {
                iCloudAvailable = false
                switch status {
                case .noAccount:
                    iCloudError = "Sign in to your iCloud account to use this app."
                case .restricted:
                    iCloudError = "iCloud access is restricted."
                case .couldNotDetermine:
                    iCloudError = "Unable to determine iCloud account status."
                default:
                    iCloudError = "iCloud is not available."
                }
            }
        } catch {
            iCloudAvailable = false
            iCloudError = "Error checking iCloud status: \(error.localizedDescription)"
        }
        checkingICloud = false

        // Set initial selection based on authentication state
        if dropboxAuthManager.isAuthenticated {
            if selection != .images {
                selection = .images
            }
        } else {
            if selection != .authentication {
                selection = .authentication
            }
        }
    }

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
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
