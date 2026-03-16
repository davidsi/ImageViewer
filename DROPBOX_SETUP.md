# Dropbox SDK Integration Setup

## Step 1: Add Dropbox SDK to Xcode Project

1. In Xcode, go to **File → Add Package Dependencies**
2. Enter the repository URL: `https://github.com/dropbox/SwiftyDropbox`
3. Select **Up to Next Major Version** and click **Add Package**
4. Add the **SwiftyDropbox** library to your **ImageView** target

## Step 2: Configure URL Scheme in Info.plist

Add the following to your Info.plist file (or use Xcode's GUI):

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>Dropbox OAuth</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>YOUR_ACTUAL_DROPBOX_APP_KEY</string>
        </array>
    </dict>
</array>
```

Replace `YOUR_DROPBOX_APP_KEY` with your actual Dropbox app key.

## Step 3: Create Dropbox App

1. Go to https://www.dropbox.com/developers/apps
2. Click **Create app**
3. Choose **Scoped access** 
4. Choose **Full Dropbox** access
5. Give your app a name
6. Copy the **App key** from the settings page

## Step 4: Update DropboxAuthManager

In `DropboxAuthManager.swift`, replace the placeholder app key:

```swift
private let dropboxAppKey = "YOUR_ACTUAL_DROPBOX_APP_KEY"
```

## Step 5: URL Handling (Cross-Platform)

The URL handling is already implemented in `ImageViewApp.swift` and works for both iOS and macOS:

```swift
import SwiftUI
import SwiftData
import SwiftyDropbox

@main
struct ImageViewApp: App {
    @StateObject private var dropboxAuthManager = DropboxAuthManager()
    
    // ... existing code ...

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
```

**No additional platform-specific code is needed.** The `.onOpenURL` modifier automatically handles URL callbacks on both iOS and macOS.

## Step 6: Configure OAuth Redirect URI

In your Dropbox app settings (https://www.dropbox.com/developers/apps), add the redirect URI.

**Try these options in order until one is accepted:**

### Option 1: Standard Mobile Format
- **Redirect URI:** `db-YOUR_DROPBOX_APP_KEY://1/connect`

### Option 2: Token Format  
- **Redirect URI:** `db-YOUR_DROPBOX_APP_KEY://2/token`

### Option 3: With Authority (if above fail)
- **Redirect URI:** `db-YOUR_DROPBOX_APP_KEY://auth/token`

### Option 4: HTTPS Format (if custom schemes rejected)
- **Redirect URI:** `https://your-domain.com/dropbox-auth`
- Note: This requires additional URL handling code

**Most likely to work:** Try Option 1 first (`db-YOUR_DROPBOX_APP_KEY://1/connect`)

**Important:** Replace `YOUR_DROPBOX_APP_KEY` with your actual app key in both:
1. The redirect URI setting in Dropbox console
2. The URL scheme in your Info.plist 
3. The `dropboxAppKey` variable in `DropboxAuthManager.swift`

**Example:** If your app key is `abc123xyz`, then:
- Redirect URI: `db-abc123xyz://1/connect`
- URL scheme: `db-abc123xyz`  
- Code: `private let dropboxAppKey = "abc123xyz"`

## Features Implemented

✅ **Real Dropbox SDK Integration** - Uses SwiftyDropbox SDK instead of simulation  
✅ **Token Validation** - Validates stored tokens with Dropbox API  
✅ **OAuth Flow** - Complete OAuth 2.0 authentication flow  
✅ **Cross-platform** - Works on both iOS and macOS  
✅ **User Info Fetching** - Gets user email and display name  
✅ **Token Management** - Secure storage and cleanup of credentials  
✅ **Error Handling** - Comprehensive error handling and user feedback  

## Testing

1. Build and run the app
2. Navigate to the Authentication tab
3. Click "Authenticate with Dropbox"
4. Complete the OAuth flow in your browser
5. Verify the app shows "✓ Connected to Dropbox" with your email

The app will remember your authentication and auto-login on subsequent launches.