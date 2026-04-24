//
//  AuthenticationView.swift
//  ImageView
//
//  Created by david silver on 2026-03-15.
//

import SwiftUI
#if os(macOS)
import CloudKit
import UniformTypeIdentifiers
#endif

struct AuthenticationView: View {
    #if os(macOS)
    let iCloudAvailable: Bool
    let openICloudSettings: () -> Void
    #else
    let iCloudAvailable: Bool
    let openICloudSettings: () -> Void
    #endif
    
    @EnvironmentObject private var dropboxAuthManager: DropboxAuthManager
    @ObservedObject private var userSettings = UserSettings.shared
    #if os(macOS)
    @State private var showingLocalFolderPicker = false
    #endif
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                #if os(macOS)
                // CloudKit Section (Optional) - For syncing app data between devices
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "icloud")
                            .font(.title2)
                        Text("CloudKit (Optional)")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("For syncing app data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if !iCloudAvailable {
                        VStack(spacing: 8) {
                            Text("CloudKit sync is disabled")
                                .foregroundColor(.orange)
                                .font(.body)
                            Text("App will work normally without CloudKit. Enable CloudKit to sync app data between devices.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                openICloudSettings()
                            } label: {
                                Label("iCloud Settings", systemImage: "gear")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        HStack {
                            Text("✓ CloudKit sync enabled")
                                .foregroundColor(.green)
                                .font(.body)
                            Spacer()
                            Button {
                                openICloudSettings()
                            } label: {
                                Label("Settings", systemImage: "gear")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // Note about Photos access
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "photos")
                            .foregroundColor(.blue)
                        Text("iCloud Photos Access")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    VStack(spacing: 4) {
                        Text("Accessing iCloud Photos requires:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("• Photos permission (app will request)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("• iCloud Photos enabled in System Settings")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("• Photos synced locally to this device")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)
                #endif
                
                // Dropbox Section
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "folder")
                            .font(.title2)
                        Text("Dropbox")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if dropboxAuthManager.isAuthenticating {
                        ProgressView("Authenticating...")
                            .progressViewStyle(CircularProgressViewStyle())
                    } else if dropboxAuthManager.isAuthenticated {
                        VStack(spacing: 12) {
                            Text("✓ Connected to Dropbox")
                                .foregroundColor(.green)
                                .font(.body)
                            
                            VStack(spacing: 4) {
                                if let name = dropboxAuthManager.userName {
                                    Text(name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                if let email = dropboxAuthManager.userEmail {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Button {
                                dropboxAuthManager.logout()
                            } label: {
                                Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                                    .font(.headline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            
                            Button {
                                Task {
                                    await DropboxService.shared.debugTokenPermissions()
                                }
                            } label: {
                                Label("Debug Token Scopes", systemImage: "info.circle")
                                    .font(.headline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.blue)
                            
                            Button {
                                DropboxService.shared.forceReauthentication()
                                dropboxAuthManager.logout()
                            } label: {
                                Label("Force Re-authenticate", systemImage: "arrow.counterclockwise.circle")
                                    .font(.headline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.orange)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Text("Connect to Dropbox to sync your files")
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                            
                            if let error = dropboxAuthManager.authenticationError {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                            }
                            
                            Button {
                                dropboxAuthManager.startAuthentication()
                            } label: {
                                Label("Authenticate with Dropbox", systemImage: "person.crop.circle.badge.plus")
                                    .font(.headline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)

                #if os(macOS)
                // Local Folder Section
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "internaldrive")
                            .font(.title2)
                        Text("Local Folder (Offline Mode)")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                    }

                    Text("Use a local folder instead of Dropbox. Images and keywords are read/written directly from disk — useful when files are already downloaded from Dropbox and you are offline.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)

                    if userSettings.isLocalMode, let url = userSettings.localFolderURL {
                        // Active local mode
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Offline mode active")
                                    .foregroundColor(.green)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            Text(url.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack {
                                Button {
                                    showingLocalFolderPicker = true
                                } label: {
                                    Label("Change Folder", systemImage: "folder.badge.gear")
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    userSettings.disableLocalMode()
                                    DropboxService.shared.invalidateKeywordCache()
                                } label: {
                                    Label("Switch to Dropbox", systemImage: "arrow.triangle.2.circlepath")
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.bordered)

                                Button(role: .destructive) {
                                    userSettings.clearLocalFolder()
                                    DropboxService.shared.invalidateKeywordCache()
                                } label: {
                                    Label("Forget Folder", systemImage: "trash")
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    } else if userSettings.hasLocalFolder, let url = userSettings.localFolderURL {
                        // Has a saved folder but currently in Dropbox mode
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "internaldrive")
                                    .foregroundColor(.indigo)
                                Text("Saved folder:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            Text(url.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack {
                                Button {
                                    userSettings.enableLocalMode()
                                    DropboxService.shared.invalidateKeywordCache()
                                } label: {
                                    Label("Use Local Folder", systemImage: "internaldrive")
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.indigo)

                                Button {
                                    showingLocalFolderPicker = true
                                } label: {
                                    Label("Change", systemImage: "folder.badge.gear")
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.bordered)

                                Button(role: .destructive) {
                                    userSettings.clearLocalFolder()
                                    DropboxService.shared.invalidateKeywordCache()
                                } label: {
                                    Label("Forget", systemImage: "trash")
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    } else {
                        // No folder saved yet
                        Button {
                            showingLocalFolderPicker = true
                        } label: {
                            Label("Choose Local Folder…", systemImage: "folder.badge.plus")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                    }
                }
                .padding()
                .background(Color.indigo.opacity(0.08))
                .cornerRadius(12)
                .fileImporter(
                    isPresented: $showingLocalFolderPicker,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    Task { @MainActor in
                        if case .success(let urls) = result, let url = urls.first {
                            UserSettings.shared.setLocalFolderURL(url)
                            DropboxService.shared.invalidateKeywordCache()
                        }
                    }
                }
                #endif

                // Build info
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                Text("Version \(version) (\(build))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding()
        }
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    AuthenticationView(iCloudAvailable: false) {
        print("Open iCloud settings")
    }
    .environmentObject(DropboxAuthManager())
}