#if DEBUG
import AVFoundation
import ImageIO
import MediaPlayer
import UniformTypeIdentifiers
#endif
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
                        await verifyStudio()
                    }
                }
#endif
        }
    }

#if DEBUG
    private func verifyStudio() async {
        let report = URL.cachesDirectory.appendingPathComponent("rj-smoke.txt")
        let progress = URL.cachesDirectory.appendingPathComponent("rj-smoke-progress.txt")
        let result: String
        do {
            try "Rendering 4K photo".write(to: progress, atomically: true, encoding: .utf8)
            let preset = try StudioMedia.makePreset(.aurora)
            var edit = WallpaperEdit.fresh(for: preset)
            edit.zoom = 1.2
            edit.look = .frost
            let output = try await RenderEngine.render(preset, edit: edit, kind: .still) { _ in }
            let imported = try await StudioMedia.open(output.file)
            guard imported.size == CGSize(width: 2160, height: 3840), imported.kind == .image else {
                throw StudioError.encode
            }
            try await verifyLockScreenPlayer(progress: progress)
            result = "4K export, animated cover, audio import and playback passed"
        } catch {
            result = "Studio smoke test failed: \(error.localizedDescription)"
        }
        try? result.write(to: report, atomically: true, encoding: .utf8)
    }

    @MainActor
    private func verifyLockScreenPlayer(progress: URL) async throws {
        try "Preparing GIF and WAV fixtures".write(to: progress, atomically: true, encoding: .utf8)
        let directory = try Workspace.makeDirectory()
        let gif = directory.appendingPathComponent("Cover-Test.gif")
        let audio = directory.appendingPathComponent("Audio-Test.wav")
        try writeTestGIF(to: gif)
        try writeTestAudio(to: audio)

        let media = try await StudioMedia.open(gif)
        guard media.kind == .gif else { throw StudioError.unreadable }
        try "Rendering 3:4 animated cover".write(to: progress, atomically: true, encoding: .utf8)
        let artwork = try await RenderEngine.renderLockScreenArtwork(media, edit: .fresh(for: media)) { _ in }
        let preview = try await StudioMedia.open(artwork.preview)
        let video = try await StudioMedia.open(artwork.video)
        let coverSize = CGSize(width: 900, height: 1200)
        guard preview.size == coverSize, video.size == coverSize, video.hasMotion, video.duration > 0 else {
            throw LockScreenPlayerError.cover
        }
        try "Checking audio and video soundtrack import".write(to: progress, atomically: true, encoding: .utf8)
        let movieWithAudio = directory.appendingPathComponent("Video-With-Sound.mov")
        try await writeTestMovie(video: artwork.video, audio: audio, to: movieWithAudio)
        let player = LockScreenPlayer()
        try await player.importAudio(from: movieWithAudio)
        guard player.audioTitle == "Video-With-Sound" else { throw LockScreenPlayerError.audio }

        do {
            try await player.importAudio(from: artwork.preview)
            throw StudioError.unreadable
        } catch LockScreenPlayerError.audio {
            guard player.audioTitle == "Video-With-Sound" else { throw LockScreenPlayerError.audio }
        }

        try "Starting Now Playing audio".write(to: progress, atomically: true, encoding: .utf8)
        try await player.importAudio(from: audio)
        guard player.audioTitle == "Audio-Test" else { throw LockScreenPlayerError.audio }
        try player.start(artwork: artwork, title: media.title)
        defer { player.stop() }
        let info = MPNowPlayingInfoCenter.default()
        guard player.isPlaying,
              info.nowPlayingInfo?[MPNowPlayingInfoProperty3x4AnimatedArtwork] is MPMediaItemAnimatedArtwork else {
            throw LockScreenPlayerError.playback
        }
        player.togglePlayback()
        guard player.isActive, !player.isPlaying else { throw LockScreenPlayerError.playback }
        player.stop()
        guard !player.isActive, info.nowPlayingInfo == nil else { throw LockScreenPlayerError.playback }
    }

    private func writeTestGIF(to url: URL) throws {
        guard let image = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil) else {
            throw StudioError.encode
        }
        let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary
        for preset in [StudioPreset.aurora, .ember] {
            CGImageDestinationAddImage(image, try StudioMedia.makePreset(preset).poster, properties)
        }
        guard CGImageDestinationFinalize(image) else { throw StudioError.encode }
    }

    private func writeTestMovie(video: URL, audio: URL, to url: URL) async throws {
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        let composition = AVMutableComposition()
        guard let videoSource = try await videoAsset.loadTracks(withMediaType: .video).first,
              let audioSource = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw StudioError.encode
        }
        let range = CMTimeRange(start: .zero, duration: try await videoAsset.load(.duration))
        try videoTrack.insertTimeRange(range, of: videoSource, at: .zero)
        try audioTrack.insertTimeRange(range, of: audioSource, at: .zero)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw StudioError.encode
        }
        try await exporter.export(to: url, as: .mov)
    }

    private func writeTestAudio(to url: URL) throws {
        let rate = 22_050.0
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: true),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * 8)),
              let samples = buffer.int16ChannelData?.pointee else { throw LockScreenPlayerError.audio }
        buffer.frameLength = buffer.frameCapacity
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame] = Int16(sin(Double(frame) / rate * 440 * 2 * .pi) * 80)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        try file.write(from: buffer)
    }
#endif
}
