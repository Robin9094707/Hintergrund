import ImageIO
import SwiftUI

@main
struct RJWallpaperApp: App {
    init() { Workspace.prepare() }

    var body: some Scene {
        WindowGroup {
            StudioView()
                .preferredColorScheme(.dark)
                .tint(Color(rgb: 0x9FFFE5))
#if DEBUG
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--ci-smoke") {
                        await verifyStillExport()
                    }
                }
#endif
        }
    }

#if DEBUG
    private func verifyStillExport() async {
        let report = URL.cachesDirectory.appendingPathComponent("rj-smoke.txt")
        let result: String
        do {
            let preset = try StudioMedia.makePreset(.aurora)
            var edit = WallpaperEdit.fresh(for: preset)
            edit.zoom = 1.2
            edit.look = .frost
            let output = try await RenderEngine.render(preset, edit: edit, kind: .still) { _ in }
            let imported = try await StudioMedia.open(output.file)
            guard imported.size == CGSize(width: 2160, height: 3840), imported.kind == .image else {
                throw StudioError.encode
            }
            result = "4K export and reimport passed"
        } catch {
            result = "4K export failed: \(error.localizedDescription)"
        }
        try? result.write(to: report, atomically: true, encoding: .utf8)
    }
#endif
}
