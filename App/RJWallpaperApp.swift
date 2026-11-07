import SwiftUI

@main
struct RJWallpaperApp: App {
    init() { Workspace.prepare() }

    var body: some Scene {
        WindowGroup {
            StudioView()
                .preferredColorScheme(.dark)
                .tint(Color(rgb: 0x9FFFE5))
        }
    }
}
