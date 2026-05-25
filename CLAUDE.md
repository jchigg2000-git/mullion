When writing Swift: target Swift 6 idioms on macOS 15+ (current build is
   Swift 5.10). No force unwraps. Mark types Sendable where crossing actor
   boundaries. If SwiftUI is added: @Observable not ObservableObject,
   NavigationStack not NavigationView, foregroundStyle not foregroundColor.