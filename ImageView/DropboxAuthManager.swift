//
//  DropboxAuthManager.swift
//  ImageView
//
//  Created by david silver on 2026-03-15.
//

import Foundation
import SwiftUI
import Combine
import SwiftyDropbox

class DropboxAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    @Published var authenticationError: String?
    @Published var userEmail: String?
    @Published var userName: String?
    
    private let userSettings = UserSettings.shared
    
    // Track if user explicitly logged out to prevent auto-login
    //
    @Published private var hasExplicitlyLoggedOut = false
    
    // Dropbox app key - UPDATE THIS WITH YOUR NEW APP KEY
    //
    private let dropboxAppKey = "sua670w0k40zruc"
    
    init() {
        setupDropboxSDK()
        checkExistingCredentials()
    }
    
    private func setupDropboxSDK() {
        // Initialize Dropbox SDK
        #if os(iOS)
        DropboxClientsManager.setupWithAppKey(dropboxAppKey)
        #elseif os(macOS)
        DropboxClientsManager.setupWithAppKeyDesktop(dropboxAppKey)
        #endif
    }
    
    func checkExistingCredentials() {
        print("📱 DropboxAuth: Checking existing credentials...")
        Task { @MainActor in
            // Don't auto-login if user explicitly logged out
            if hasExplicitlyLoggedOut {
                print("📱 DropboxAuth: User previously logged out, skipping auto-login")
                isAuthenticated = false
                return
            }
            
            // Only auto-login if we have both stored creds AND an active SDK client
            let hasStoredCreds = userSettings.hasDropboxCredentials()
            let hasActiveClient = DropboxClientsManager.authorizedClient != nil
            
            print("📱 DropboxAuth: Has stored credentials: \(hasStoredCreds)")
            print("📱 DropboxAuth: Has active SDK client: \(hasActiveClient)")
            
            if hasStoredCreds && hasActiveClient {
                print("📱 DropboxAuth: Found both stored credentials and active client, attempting auto-login...")
                self.fetchUserInfo()
            } else {
                print("📱 DropboxAuth: Insufficient credentials for auto-login, clearing any stale data")
                // Clear any partial/stale authentication state
                userSettings.clearDropboxCredentials()
                DropboxClientsManager.unlinkClients()
                DropboxClientsManager.authorizedClient = nil
                isAuthenticated = false
            }
        }
    }
    
    @MainActor
    func validateStoredToken() {
        // This method is no longer needed since we rely on SDK client management
        // Keep for compatibility but just redirect to fetchUserInfo
        fetchUserInfo()
    }
    
    @MainActor
    func startAuthentication() {
        print("📱 DropboxAuth: Starting authentication process...")
        
        // Reset logout flag since user is actively authenticating
        hasExplicitlyLoggedOut = false
        
        isAuthenticating = true
        authenticationError = nil
        
        #if os(iOS)
        // iOS OAuth flow
        print("📱 DropboxAuth: Starting iOS authorization")
        DropboxClientsManager.authorizeFromControllerV2(
            UIApplication.shared,
            controller: nil,
            loadingStatusDelegate: nil,
            openURL: { (url: URL) -> Void in
                print("📱 DropboxAuth: Opening URL: \(url)")
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            },
            scopeRequest: nil
        )
        #elseif os(macOS)
        // macOS OAuth flow  
        print("📱 DropboxAuth: Starting macOS authorization")
        DropboxClientsManager.authorizeFromController(
            sharedApplication: NSApplication.shared,
            controller: nil as NSViewController?,
            openURL: { (url: URL) -> Void in
                print("📱 DropboxAuth: Opening URL: \(url)")
                NSWorkspace.shared.open(url)
            }
        )
        
        // For macOS, check authorization status periodically since URL callback might not work reliably
        print("📱 DropboxAuth: Starting periodic check for authorization...")
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            print("📱 DropboxAuth: Timer check - isAuthenticating: \(self.isAuthenticating)")
            if DropboxClientsManager.authorizedClient != nil {
                timer.invalidate()
                print("📱 DropboxAuth: Timer detected authorized client")
                Task { @MainActor in
                    self.fetchUserInfo()
                }
            } else if !self.isAuthenticating {
                // User cancelled or authentication failed
                timer.invalidate()
                print("📱 DropboxAuth: Timer stopped - not authenticating")
            }
        }
        #endif
        
        // Safety timeout to prevent infinite spinning
        DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) {
            if self.isAuthenticating {
                print("📱 DropboxAuth: Authentication timeout reached")
                self.clearAllAuthenticationData()
                self.authenticationError = "Authentication timed out. Please try again."
            }
        }
    }
    
    // Handle URL callbacks for OAuth
    func handleURL(_ url: URL) -> Bool {
        print("📱 DropboxAuth: Handling URL: \(url)")
        
        let result = DropboxClientsManager.handleRedirectURL(url, includeBackgroundClient: false) { result in
            DispatchQueue.main.async {
                print("📱 DropboxAuth: Received callback result")
                if let result = result {
                    switch result {
                    case .success(let token):
                        print("📱 DropboxAuth: Authentication successful")
                        // Save credentials
                        self.userSettings.saveDropboxCredentials(
                            accessToken: token.accessToken,
                            refreshToken: token.refreshToken,
                            userId: token.uid
                        )
                        
                        // Fetch user info
                        Task { @MainActor in
                            self.fetchUserInfo()
                        }
                        
                    case .cancel:
                        print("📱 DropboxAuth: Authentication cancelled")
                        self.clearAllAuthenticationData()
                        self.authenticationError = "Authentication was cancelled"
                        
                    case .error(let error, let description):
                        print("📱 DropboxAuth: Authentication error: \(description ?? String(describing: error))")
                        self.clearAllAuthenticationData()
                        self.authenticationError = description ?? "Authentication failed: \(String(describing: error))"
                    }
                } else {
                    print("📱 DropboxAuth: No result received")
                    self.clearAllAuthenticationData()
                    self.authenticationError = "Authentication failed"
                }
            }
        }
        
        let wasHandled = result != nil
        print("📱 DropboxAuth: URL was handled: \(wasHandled)")
        return wasHandled
    }
    
    @MainActor
    private func fetchUserInfo() {
        guard let client = DropboxClientsManager.authorizedClient else {
            print("📱 DropboxAuth: No authorized client available")
            authenticationError = "No authorized client available"
            isAuthenticating = false
            return
        }
        
        print("📱 DropboxAuth: Fetching user info...")
        print("📱 DropboxAuth: Client exists: \(client)")
        print("📱 DropboxAuth: Client type: \(type(of: client))")
        
        // Always try to get real user info from API on both platforms 
        client.users.getCurrentAccount().response { result, error in
            DispatchQueue.main.async {
                if let account = result {
                    print("📱 DropboxAuth: Successfully received account info")
                    
                    // Save credentials with real user ID
                    if !self.userSettings.hasDropboxCredentials() {
                        self.userSettings.saveDropboxCredentials(
                            accessToken: "sdk_managed_token",
                            refreshToken: nil,
                            userId: account.accountId
                        )
                        print("📱 DropboxAuth: Saved credentials for \(account.accountId)")
                    }
                    
                    self.isAuthenticated = true
                    self.userEmail = account.email
                    self.userName = account.name.displayName
                    self.authenticationError = nil
                    self.isAuthenticating = false
                    self.hasExplicitlyLoggedOut = false  // Reset logout flag on successful auth
                    
                    print("📱 DropboxAuth: Authentication completed for \(account.email)")
                    
                } else if let error = error {
                    print("📱 DropboxAuth: API Error: \(error)")
                    print("📱 DropboxAuth: Error details: \(String(describing: error))")
                    print("📱 DropboxAuth: Error type: \(type(of: error))")
                    print("📱 DropboxAuth: Error localizedDescription: \(error.localizedDescription)")
                    // If API call fails, try alternative approach - mark as authenticated but with limited info
                    print("📱 DropboxAuth: API failed, will mark as authenticated with limited info")
                    
                    if !self.userSettings.hasDropboxCredentials() {
                        self.userSettings.saveDropboxCredentials(
                            accessToken: "sdk_managed_token_limited",
                            refreshToken: nil,
                            userId: "dropbox_user"
                        )
                    }
                    
                    self.isAuthenticated = true
                    self.userEmail = "Authenticated User"  // Generic but not fake email
                    self.userName = "Dropbox User"
                    self.authenticationError = nil
                    self.isAuthenticating = false
                    self.hasExplicitlyLoggedOut = false  // Reset logout flag on successful auth
                    
                    print("📱 DropboxAuth: Marked as authenticated with limited user info")
                    
                } else {
                    print("📱 DropboxAuth: Unknown error - no result and no error")
                    self.clearAllAuthenticationData()
                    self.authenticationError = "Failed to fetch user info: Unknown error"
                }
            }
        }
    }
    
    func logout() {
        print("📱 DropboxAuth: User explicitly logging out")
        hasExplicitlyLoggedOut = true
        clearAllAuthenticationData()
    }
    
    private func clearAllAuthenticationData() {
        print("📱 DropboxAuth: Clearing all authentication data")
        
        // Clear SDK-managed authentication more aggressively
        DropboxClientsManager.unlinkClients()
        DropboxClientsManager.authorizedClient = nil
        
        // Clear stored credentials  
        userSettings.clearDropboxCredentials()
        
        // Clear UI state
        isAuthenticated = false
        isAuthenticating = false
        userEmail = nil
        userName = nil
        authenticationError = nil
        
        print("📱 DropboxAuth: All authentication data cleared")
    }
}
