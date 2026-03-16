//
//  AuthenticationView.swift
//  ImageView
//
//  Created by david silver on 2026-03-15.
//

import SwiftUI
import CloudKit

struct AuthenticationView: View {
    let iCloudAvailable: Bool
    let openICloudSettings: () -> Void
    
    @EnvironmentObject private var dropboxAuthManager: DropboxAuthManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // iCloud Section
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "icloud")
                            .font(.title2)
                        Text("iCloud")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !iCloudAvailable {
                        Text("Sign in to your iCloud account to use this app.")
                            .foregroundColor(.red)
                            .font(.body)
                            .multilineTextAlignment(.center)
                        Button {
                            openICloudSettings()
                        } label: {
                            Label("Open iCloud Settings", systemImage: "person.crop.circle.badge.exclamationmark")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("✓ You are signed in to iCloud.")
                            .foregroundColor(.green)
                            .font(.body)
                        Button {
                            openICloudSettings()
                        } label: {
                            Label("iCloud Settings", systemImage: "gear")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
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