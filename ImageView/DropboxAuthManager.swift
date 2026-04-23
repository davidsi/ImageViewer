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
    private var cancellables = Set<AnyCancellable>()
    
    // Track if user explicitly logged out to prevent auto-login
    //
    @Published private var hasExplicitlyLoggedOut = false
    
    // Timer for macOS auth checking
    private var authTimer: Timer?
    
    // Prevent multiple credential checks
    private var hasCheckedCredentials = false
    private var lastAuthAttempt: Date?
    private var authRetryCount = 0
    private let maxAuthRetries = 3
    private let authRetryDelay: TimeInterval = 30.0 // 30 seconds between retries
    private var backgroundFetchDisabled = false // Disable background fetch if network issues persist
    
    // Dropbox app key - UPDATE THIS WITH YOUR NEW APP KEY
    //
    private let dropboxAppKey = "sua670w0k40zruc"
    
    init() {
        setupDropboxSDK()
        // If local mode was active from a previous session, restore authenticated state immediately
        if UserSettings.shared.isLocalMode && UserSettings.shared.localFolderURL != nil {
            isAuthenticated = true
        }
        checkExistingCredentials()

        // Mirror local-mode changes into isAuthenticated
        userSettings.$isLocalMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] localMode in
                guard let self else { return }
                if localMode {
                    // Switching to local mode: authenticated if folder is available
                    self.isAuthenticated = UserSettings.shared.localFolderURL != nil
                } else {
                    // Switching back to Dropbox mode: authenticated if Dropbox client exists
                    self.isAuthenticated = DropboxClientsManager.authorizedClient != nil
                }
            }
            .store(in: &cancellables)
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
        guard !hasCheckedCredentials else {
            print("📱 DropboxAuth: Already checked credentials, skipping")
            return
        }
        
        // Check if we should delay retry due to recent failure
        if let lastAttempt = lastAuthAttempt {
            let timeSinceLastAttempt = Date().timeIntervalSince(lastAttempt)
            if timeSinceLastAttempt < authRetryDelay && authRetryCount >= maxAuthRetries {
                print("📱 DropboxAuth: Too many recent auth attempts (\(authRetryCount)), waiting...")
                isAuthenticated = false
                return
            }
        }
        
        hasCheckedCredentials = true
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
        authTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            print("📱 DropboxAuth: Timer check - isAuthenticating: \(self.isAuthenticating)")
            if DropboxClientsManager.authorizedClient != nil {
                timer.invalidate()
                self.authTimer = nil
                print("📱 DropboxAuth: Timer detected authorized client")
                Task { @MainActor in
                    self.fetchUserInfo()
                }
            } else if !self.isAuthenticating {
                // User cancelled or authentication failed
                timer.invalidate()
                self.authTimer = nil
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
        
        // Track this attempt
        lastAuthAttempt = Date()
        authRetryCount += 1
        
        print("📱 DropboxAuth: Fetching user info... (attempt \(authRetryCount))")
        print("📱 DropboxAuth: Client exists: \(client)")
        print("📱 DropboxAuth: Client type: \(type(of: client))")
        
        // Always try to get real user info from API on both platforms 
        client.users.getCurrentAccount().response { result, error in
            DispatchQueue.main.async {
                // Invalidate timer since we're done with auth
                self.authTimer?.invalidate()
                self.authTimer = nil
                
                if let account = result {
                    print("📱 DropboxAuth: Successfully received account info")
                    
                    // Reset retry count on success
                    self.authRetryCount = 0
                    
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
                    
                    // Check if this is a network error
                    let isNetworkError = self.isNetworkError(error)
                    
                    if isNetworkError && self.authRetryCount < self.maxAuthRetries {
                        print("📱 DropboxAuth: Network error detected, will retry later")
                        self.authenticationError = "Network error, will retry automatically"
                        self.isAuthenticating = false
                        
                        // Schedule retry after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                            if !self.isAuthenticated && !self.hasExplicitlyLoggedOut {
                                print("📱 DropboxAuth: Retrying user info fetch...")
                                self.fetchUserInfo()
                            }
                        }
                    } else {
                        print("📱 DropboxAuth: API failed permanently or max retries reached, marking as authenticated with limited info")
                        
                        self.isAuthenticated = true
                        self.userEmail = "Authenticated User"  
                        self.userName = "Dropbox User"
                        self.authenticationError = nil
                        self.isAuthenticating = false
                        self.hasExplicitlyLoggedOut = false
                        
                        print("📱 DropboxAuth: Marked as authenticated with limited user info")
                    }
                    
                } else {
                    print("📱 DropboxAuth: Unknown error - no result and no error")
                    self.clearAllAuthenticationData()
                    self.authenticationError = "Failed to fetch user info: Unknown error"
                }
            }
        }
    }
    
    private func isNetworkError(_ error: Any) -> Bool {
        let errorString = String(describing: error)
        return errorString.contains("-1003") || // DNS lookup failed
               errorString.contains("server with the specified hostname could not be found") ||
               errorString.contains("urlSessionError") ||
               errorString.contains("network")
    }
    
    @MainActor
    private func fetchUserInfoInBackground() {
        guard let client = DropboxClientsManager.authorizedClient else {
            print("📱 DropboxAuth: No client for background fetch")
            return
        }
        
        print("📱 DropboxAuth: Background fetch of user info...")
        
        client.users.getCurrentAccount().response { result, error in
            DispatchQueue.main.async {
                if let account = result {
                    print("📱 DropboxAuth: Background fetch successful, updating user info")
                    self.userEmail = account.email
                    self.userName = account.name.displayName
                    
                    // Reset network issue flag on success
                    self.backgroundFetchDisabled = false
                    
                    // Update stored credentials with real user ID if needed
                    if self.userSettings.hasDropboxCredentials() {
                        self.userSettings.saveDropboxCredentials(
                            accessToken: "sdk_managed_token",
                            refreshToken: nil,
                            userId: account.accountId
                        )
                    }
                } else {
                    print("📱 DropboxAuth: Background fetch failed, keeping generic user info")
                    
                    // If this is a network error, disable future background fetches to reduce noise
                    if let error = error, self.isNetworkError(error) {
                        self.backgroundFetchDisabled = true
                        print("📱 DropboxAuth: Disabling future background fetches due to network issues")
                    }
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
        
        // Invalidate timer if running
        authTimer?.invalidate()
        authTimer = nil
        
        // Reset retry tracking
        authRetryCount = 0
        lastAuthAttempt = nil
        hasCheckedCredentials = false
        backgroundFetchDisabled = false // Reset network issue flag
        
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
