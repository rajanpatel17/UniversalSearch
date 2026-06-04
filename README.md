# UniversalSearchSDK

A powerful and easy-to-integrate iOS SDK that brings AI-assisted search and communication capabilities to your application.

## Features

- **Floating AI Assist View**: A non-intrusive floating button that provides quick access to AI features.
- **Smart Bar Web View**: A rich, interactive web-based search experience with deep-link support.
- **AI Voice/Video Calls**: Seamless integration with LiveKit for AI-powered real-time communication.
- **Deep Linking**: Built-in support for handling deep links within the search experience.
- **Customizable**: Delegate-based architecture to tightly integrate with your app's session and data.

## Installation

### Swift Package Manager

Add the following to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/your-repo/UniversalSearchSDK.git", from: "1.0.0")
]
```

Or add it via Xcode (**File** -> **Add Packages...**) using the repository URL.

## Getting Started

### 1. Initialize the SDK

Set up the session data as soon as the user logs in or the application starts:

```swift
import UniversalSearchSDK

UniversalSearchManager.shared.setupSession(
    sessionId: "user-session-id",
    loginId: "user-login-id",
    userName: "John Doe",
    userRole: "admin",
    fcmToken: "your-fcm-token",
    tid: "terminal-id",
    storeCount: 1
)
```

### 2. Implement the Delegate

Implement `UniversalSearchDelegate` to handle SDK events and provide necessary data:

```swift
class MyAppDelegate: UniversalSearchDelegate {
    func getSessionData() -> UniversalSearchSessionData? {
        // Return current session data if needed
        return nil
    }
    
    func logEvent(eventName: String, params: [String : String]) {
        // Log to your analytics service
    }
    
    func handleDeepLink(_ urlString: String) {
        // Navigate to the appropriate screen
    }
}

UniversalSearchManager.shared.delegate = myAppDelegate
```

### 3. Show the Floating Assist View

```swift
UniversalSearchManager.shared.showFloatingAIAssist()
```

## Requirements

- **iOS**: 16.0+
- **macOS**: 12.0+
- **Swift**: 5.9+

## Dependencies

- [LiveKit](https://github.com/livekit/client-sdk-swift)
- [SDWebImage](https://github.com/SDWebImage/SDWebImage)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
