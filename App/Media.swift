import AVFoundation
import CoreImage
import CoreTransferable
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum StudioError: LocalizedError {
    case unreadable, emptyVideo, encode, photosAccess, livePhoto

    var errorDescription: String? {
        switch self {
        case .unreadable: "Diese Datei konnte nicht gelesen werden. Probiere ein Foto, GIF, MP4 oder MOV."
        case .emptyVideo: "In diesem Ausschnitt wurden keine Videobilder gefunden."
        case .encode: "Der Export konnte nicht fertiggestellt werden."
        case .photosAccess: "Erlaube RJ Wallpaper den Zugriff zum Hinzufügen von Fotos in den iPhone-Einstellungen."
        case .livePhoto: "Fotos konnte das Live Photo nicht speichern."
        }
    }
}

enum Workspace {
    // One session directory keeps share-sheet URLs alive and cleans up after prior launches.
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("RJ-Wallpaper", isDirectory: true)
    static let current = root.appendingPathComponent(UUID().uuidString, isDirectory: true)

    static func prepare() {
        try? FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        let older = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for directory in older where directory != current {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func makeDirectory() throws -> URL {
        let directory = current.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func copy(_ source: URL) throws -> URL {
        let directory = try makeDirectory()
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

struct PickedMedia: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { PickedMedia(url: try Workspace.copy($0.file)) }
        FileRepresentation(importedContentType: .image) { PickedMedia(url: try Workspace.copy($0.file)) }
    }
}

enum WallpaperLook: String, CaseIterable, Identifiable {
    case original = "Original"
    case aurora = "Aurora"
    case amber = "Warm"
    case frost = "Kühl"
    case mono = "Mono"

    var id: Self { self }
    var tint: Color {
        switch self {
        case .original: .white
        case .aurora: .mint
        case .amber: .orange
        case .frost: .cyan
        case .mono: .gray
        }
    }

    var values: (saturation: Double, brightness: Double, contrast: Double) {
        switch self {
        case .original: (1, 0, 1)
        case .aurora: (1.35, 0.015, 1.10)
        case .amber: (1.12, 0.025, 1.04)
        case .frost: (0.86, 0.015, 1.13)
        case .mono: (0, 0.015, 1.16)
        }
    }

    var temperature: CGFloat {
        switch self {
        case .amber: 5200
        case .frost: 8200
        default: 6500
        }
    }
}

struct WallpaperEdit: Equatable {
    var zoom = 1.0
    var x = 0.0
    var y = 0.0
    var look: WallpaperLook = .original
    var shade = 0.0
    var start = 0.0
    var length = 3.0
    var keyFrame = 0.35

    static func fresh(for media: StudioMedia) -> Self {
        var edit = Self()
        if media.hasMotion {
            edit.length = min(3, media.duration)
            edit.keyFrame = min(0.35, edit.length / 2)
        } else {
            edit.keyFrame = 0
        }
        return edit
    }

    func crop(source: CGSize, canvas: CGSize) -> CGRect {
        let scale = max(canvas.width / source.width, canvas.height / source.height) * zoom
        let width = source.width * scale
        let height = source.height * scale
        return CGRect(
            x: (canvas.width - width) / 2 + x * max(0, width - canvas.width) / 2,
            y: (canvas.height - height) / 2 + y * max(0, height - canvas.height) / 2,
            width: width, height: height
        )
    }
}

enum StudioPreset: String, CaseIterable, Identifiable {
    case aurora = "Polarlicht"
    case ember = "Sonnensturm"
    case tide = "Tiefsee"

    var id: Self { self }
    var palette: (base: UInt32, glow: UInt32, accent: UInt32) {
        switch self {
        case .aurora: (0x090C25, 0x754AFA, 0x42F5C2)
        case .ember: (0x220D25, 0xFC5376, 0xFFBE69)
        case .tide: (0x040F27, 0x1544CF, 0x4DEFEA)
        }
    }
    var symbol: String {
        switch self {
        case .aurora: "sparkles"
        case .ember: "sun.horizon"
        case .tide: "water.waves"
        }
    }

    func image(size: CGSize) -> CIImage {
        let bounds = CGRect(origin: .zero, size: size)
        func glow(_ rgb: UInt32, center: CGPoint, radius: CGFloat) -> CIImage {
            let color = CIColor(rgb: rgb)
            return CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(cgPoint: center),
                "inputRadius0": 0,
                "inputRadius1": radius,
                "inputColor0": color,
                "inputColor1": CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
            ])!.outputImage!.cropped(to: bounds)
        }
        let base = CIImage(color: CIColor(rgb: palette.base)).cropped(to: bounds)
        let mist = glow(palette.glow, center: CGPoint(x: size.width * 0.20, y: size.height * 0.35), radius: size.height * 0.65)
        let beam = glow(palette.accent, center: CGPoint(x: size.width * 1.03, y: size.height * 0.62), radius: size.width * 0.92)
        return beam.composited(over: mist.composited(over: base))
    }
}

extension CIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 255) / 255,
                  green: CGFloat((rgb >> 8) & 255) / 255,
                  blue: CGFloat(rgb & 255) / 255)
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255) / 255,
                  green: Double((rgb >> 8) & 255) / 255,
                  blue: Double(rgb & 255) / 255)
    }
}

struct StudioMedia: Identifiable {
    enum Kind {
        case image, gif, video, preset
    }

    let id = UUID()
    let title: String
    let kind: Kind
    let url: URL?
    let poster: CGImage
    let size: CGSize
    let duration: Double
    let gif: AnimatedImage?
    let preset: StudioPreset?

    var hasMotion: Bool { kind == .gif || kind == .video }
    var label: String {
        switch kind {
        case .image: "FOTO"
        case .gif: "GIF"
        case .video: "VIDEO"
        case .preset: "STUDIO"
        }
    }

    static func makePreset(_ preset: StudioPreset) throws -> Self {
        let size = CGSize(width: 540, height: 960)
        let bounds = CGRect(origin: .zero, size: size)
        guard let poster = RenderEngine.context.createCGImage(preset.image(size: size), from: bounds) else {
            throw StudioError.unreadable
        }
        return Self(title: preset.rawValue, kind: .preset, url: nil, poster: poster, size: size,
                    duration: 0, gif: nil, preset: preset)
    }

    static func open(_ url: URL) async throws -> Self {
        let title = url.deletingPathExtension().lastPathComponent
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let poster = AnimatedImage.thumbnail(source, index: 0, limit: 1000) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? Double(poster.width)
            let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? Double(poster.height)
            let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            let size = (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
            let gif = AnimatedImage(source)
            return Self(title: title, kind: gif == nil ? .image : .gif, url: url, poster: poster, size: size,
                        duration: gif?.duration ?? 0, gif: gif, preset: nil)
        }

        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw StudioError.unreadable
        }
        let duration = try await asset.load(.duration).seconds
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized.size
        guard duration.isFinite, duration > 0, oriented.width > 0, oriented.height > 0 else {
            throw StudioError.unreadable
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1000, height: 1000)
        let (poster, _) = try await generator.image(at: .zero)
        return Self(title: title, kind: .video, url: url, poster: poster, size: oriented,
                    duration: duration, gif: nil, preset: nil)
    }
}

struct AnimatedImage {
    let source: CGImageSource
    let ends: [Double]
    var duration: Double { ends.last ?? 0 }

    init?(_ source: CGImageSource) {
        let count = CGImageSourceGetCount(source)
        guard count > 1, let type = CGImageSourceGetType(source),
              [UTType.gif.identifier, UTType.png.identifier, UTType.webP.identifier].contains(type as String) else {
            return nil
        }
        var elapsed = 0.0
        self.source = source
        self.ends = (0..<count).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
            let animation = (properties?["{GIF}"] ?? properties?["{PNG}"] ?? properties?["{WebP}"]) as? [String: Any]
            let delay = ((animation?["UnclampedDelayTime"] ?? animation?["DelayTime"]) as? NSNumber)?.doubleValue ?? 0.1
            elapsed += delay.isFinite && delay >= 0.02 ? delay : 0.1
            return elapsed
        }
    }

    func index(at time: Double) -> Int {
        var lower = 0
        var upper = ends.count - 1
        while lower < upper {
            let middle = (lower + upper) / 2
            if time < ends[middle] { upper = middle } else { lower = middle + 1 }
        }
        return lower
    }

    static func thumbnail(_ source: CGImageSource, index: Int, limit: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit
        ] as CFDictionary)
    }
}
