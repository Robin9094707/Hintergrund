import AVFoundation
import MediaPlayer
import Observation
import UIKit

enum LockScreenPlayerError: LocalizedError {
    case audio, cover, playback

    var errorDescription: String? {
        switch self {
        case .audio: "Wähle eine abspielbare Audiodatei oder ein Video mit Ton. Diese Datei hat keine unterstützte Tonspur."
        case .cover: "Das animierte Cover konnte nicht geladen werden."
        case .playback: "Die Audiowiedergabe konnte nicht gestartet werden."
        }
    }
}

@MainActor
@Observable
final class LockScreenPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var audioTitle: String?
    private(set) var coverTitle: String?
    private(set) var isPlaying = false
    private(set) var playbackError: String?

    @ObservationIgnored private var audio: AVAudioPlayer?
    @ObservationIgnored private var audioURL: URL?
    @ObservationIgnored private var metadata: [String: Any]?
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var interruption: NSObjectProtocol?

    var isActive: Bool { coverTitle != nil }

    func importAudio(from source: URL) async throws {
        guard !isActive else { return }
        let copied = try await Task.detached(priority: .userInitiated) {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            guard try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true else {
                throw LockScreenPlayerError.audio
            }
            return try Workspace.copy(source)
        }.value
        do {
            let player = try await Self.makeAudioPlayer(from: copied)
            guard player.duration.isFinite, player.duration > 0 else { throw LockScreenPlayerError.audio }
            player.delegate = self
            if let audioURL {
                try? FileManager.default.removeItem(at: audioURL.deletingLastPathComponent())
            }
            audio = player
            audioURL = copied
            audioTitle = source.deletingPathExtension().lastPathComponent
        } catch {
            try? FileManager.default.removeItem(at: copied.deletingLastPathComponent())
            throw LockScreenPlayerError.audio
        }
    }

    private static func makeAudioPlayer(from file: URL) async throws -> AVAudioPlayer {
        if let audio = try? AVAudioPlayer(contentsOf: file), audio.duration.isFinite, audio.duration > 0 {
            return audio
        }

        let asset = AVURLAsset(url: file)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
              let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw LockScreenPlayerError.audio
        }
        let soundtrack = file.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".m4a")
        try await exporter.export(to: soundtrack, as: .m4a)
        let player = try AVAudioPlayer(contentsOf: soundtrack)
        try? FileManager.default.removeItem(at: file)
        return player
    }

    func start(artwork: LockScreenArtwork, title: String) throws {
        guard !isActive, let audio, let audioTitle else { throw LockScreenPlayerError.audio }
        guard let cover = UIImage(contentsOfFile: artwork.preview.path) else { throw LockScreenPlayerError.cover }
        let video = artwork.video
        let animated = MPMediaItemAnimatedArtwork(
            artworkID: UUID().uuidString,
            previewImageRequestHandler: { _, completion in completion(cover) },
            videoAssetFileURLRequestHandler: { _, completion in completion(video) }
        )
        metadata = [
            MPMediaItemPropertyTitle: audioTitle,
            MPMediaItemPropertyArtist: "RJ Wallpaper Studio",
            MPMediaItemPropertyPlaybackDuration: audio.duration,
            MPMediaItemPropertyArtwork: MPMediaItemArtwork(boundsSize: cover.size) { _ in cover },
            MPNowPlayingInfoProperty3x4AnimatedArtwork: animated
        ]
        coverTitle = title
        playbackError = nil
        audio.currentTime = 0
        installControls()
        publishPlayback()
        do {
            try resume()
        } catch {
            stop()
            throw error
        }
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            resumeFromControls()
        }
    }

    func stop() {
        guard isActive else { return }
        audio?.stop()
        audio?.currentTime = 0
        isPlaying = false
        coverTitle = nil
        metadata = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        for (command, target) in remoteTargets {
            command.removeTarget(target)
        }
        remoteTargets.removeAll()
        if let interruption {
            NotificationCenter.default.removeObserver(interruption)
            self.interruption = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func clearError() { playbackError = nil }

    private func resume() throws {
        guard isActive, let audio else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback)
        try session.setActive(true)
        guard audio.play() else { throw LockScreenPlayerError.playback }
        isPlaying = true
        publishPlayback()
    }

    private func resumeFromControls() {
        do {
            try resume()
        } catch {
            playbackError = error.localizedDescription
            stop()
        }
    }

    private func pause() {
        guard isActive else { return }
        audio?.pause()
        isPlaying = false
        publishPlayback()
    }

    private func seek(to time: Double) {
        guard let audio, isActive, time.isFinite else { return }
        audio.currentTime = min(max(0, time), audio.duration)
        publishPlayback()
    }

    private func publishPlayback() {
        guard var info = metadata, let audio else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audio.currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func installControls() {
        let commands = MPRemoteCommandCenter.shared()
        register(commands.playCommand) { $0.resumeFromControls() }
        register(commands.pauseCommand) { $0.pause() }
        register(commands.togglePlayPauseCommand) { $0.togglePlayback() }
        register(commands.stopCommand) { $0.stop() }
        let seek = commands.changePlaybackPositionCommand
        remoteTargets.append((seek, seek.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor in self?.seek(to: time) }
            return .success
        }))
        let session = AVAudioSession.sharedInstance()
        interruption = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            if type == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor in self?.pause() }
            }
        }
    }

    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor (LockScreenPlayer) -> Void) {
        let target = command.addTarget { [weak self] _ in
            Task { @MainActor in
                if let self, self.isActive { action(self) }
            }
            return .success
        }
        remoteTargets.append((command, target))
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.audio === player else { return }
            if !flag { self.playbackError = LockScreenPlayerError.playback.localizedDescription }
            self.stop()
        }
    }
}
