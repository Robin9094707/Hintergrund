import SwiftUI
import UniformTypeIdentifiers

struct LockScreenPanel: View {
    let media: StudioMedia
    let edit: WallpaperEdit
    let player: LockScreenPlayer

    @State private var pickingAudio = false
    @State private var importing = false
    @State private var renderTask: Task<Void, Never>?
    @State private var progress = 0.0
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var working: Bool { importing || renderTask != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(.mint)
                            .accessibilityHidden(true)
                        Text("Sperrbildschirm-Player")
                            .font(.largeTitle.weight(.semibold))
                            .tracking(-1.2)
                            .accessibilityAddTraits(.isHeader)
                        Text("Dein Video oder GIF erscheint als animiertes Cover, während deine Audiodatei läuft.")
                            .foregroundStyle(.secondary)
                    }
                    Label(player.coverTitle ?? media.title, systemImage: "film")
                        .font(.subheadline.weight(.medium))
                    audioButton
                    if player.isActive {
                        playbackButtons
                        Text("Sperre dein iPhone und tippe im Medienplayer auf das Cover, falls es klein angezeigt wird.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if renderTask != nil {
                        ProgressView(value: progress) { Text("Animiertes Cover wird erstellt …") }
                        Button("Abbrechen", role: .cancel) { renderTask?.cancel() }
                            .buttonStyle(.glass)
                    } else {
                        Button(action: start) {
                            Label("Wiedergabe starten", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(player.audioTitle == nil || !media.hasMotion || working)
                        Text("Cover im Format 3:4. Der Clip folgt deinem Zuschnitt und deinen Looks. iOS steuert, wann das Cover animiert angezeigt wird.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 480, alignment: .leading)
                .padding(22)
                .frame(maxWidth: .infinity)
            }
            .background {
                LinearGradient(colors: [Color(rgb: 0x242043), Color(rgb: 0x101323)],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
                    .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .disabled(working)
                }
            }
        }
        .interactiveDismissDisabled(working)
        .fileImporter(isPresented: $pickingAudio, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                Task { await importAudio(url) }
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
        .alert("Sperrbildschirm-Player", isPresented: Binding(
            get: { error != nil || player.playbackError != nil },
            set: { if !$0 { error = nil; player.clearError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? player.playbackError ?? "")
        }
    }

    private var audioButton: some View {
        Button {
            pickingAudio = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform").foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.audioTitle ?? "Audiodatei auswählen")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text("Aus Dateien · MP3, M4A, WAV")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if importing {
                    ProgressView()
                } else if !player.isActive {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .disabled(player.isActive || working)
    }

    private var playbackButtons: some View {
        HStack {
            Button {
                player.togglePlayback()
            } label: {
                Label(player.isPlaying ? "Pause" : "Fortsetzen", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.glassProminent)
            Button {
                player.stop()
            } label: {
                Label("Stopp", systemImage: "stop.fill").frame(minHeight: 34)
            }
            .buttonStyle(.glass)
        }
    }

    private func importAudio(_ url: URL) async {
        importing = true
        defer { importing = false }
        do {
            try await player.importAudio(from: url)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func start() {
        progress = 0
        renderTask = Task {
            defer { renderTask = nil }
            do {
                let artwork = try await RenderEngine.renderLockScreenArtwork(media, edit: edit) { value in
                    Task { @MainActor in progress = max(progress, value) }
                }
                try Task.checkCancellation()
                try player.start(artwork: artwork, title: media.title)
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
