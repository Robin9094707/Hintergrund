import SwiftUI

struct ExportPanel: View {
    let media: StudioMedia
    let edit: WallpaperEdit
    @State private var kind: ExportKind = .still
    @State private var result: RenderedWallpaper?
    @State private var task: Task<Void, Never>?
    @State private var progress = 0.0
    @State private var saving = false
    @State private var saved = false
    @State private var showGuide = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var kinds: [ExportKind] { media.hasMotion ? [.live, .still, .movie] : [.still] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(.mint)
                            .padding(.bottom, 4)
                        Text("Dein Wallpaper")
                            .font(.largeTitle.weight(.semibold))
                            .tracking(-1.4)
                            .accessibilityAddTraits(.isHeader)
                        Text("Wähle, wie du es exportieren möchtest.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(kinds) { option in
                        formatRow(option)
                    }
                    if kind == .live {
                        Text("Live Photo · 1080 × 1920 · bis zu 3 Sekunden Bewegung beim Aufwecken.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let result {
                        resultControls(result)
                    } else if task != nil {
                        VStack(spacing: 13) {
                            ProgressView(value: progress) {
                                Text("Wallpaper wird gerendert …")
                            }
                            Button("Abbrechen", role: .cancel) { task?.cancel() }
                        }
                        .padding(.vertical, 6)
                    } else {
                        Button(action: beginExport) {
                            Label(kind == .live ? "Live Photo erstellen" : "Datei erstellen", systemImage: "sparkles")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 43)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                .padding(22)
            }
            .background {
                LinearGradient(colors: [Color(rgb: 0x242043), Color(rgb: 0x101323)], startPoint: .topTrailing,
                               endPoint: .bottomLeading)
                .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .disabled(saving || task != nil)
                }
            }
        }
        .interactiveDismissDisabled(saving || task != nil)
        .sheet(isPresented: $showGuide) { WallpaperGuide() }
        .onAppear { kind = media.hasMotion ? .live : .still }
        .onDisappear { task?.cancel() }
        .alert("Vorgang fehlgeschlagen", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func formatRow(_ option: ExportKind) -> some View {
        Button {
            if kind != option {
                kind = option
                result = nil
                saved = false
            }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: option.icon).font(.title3).foregroundStyle(kind == option ? .mint : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.rawValue).font(.headline)
                    Text(option.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: kind == option ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(kind == option ? .mint : .secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(kind == option ? .regular.tint(.mint.opacity(0.16)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 18))
        .accessibilityAddTraits(kind == option ? .isSelected : [])
        .disabled(saving || task != nil)
    }

    private func resultControls(_ result: RenderedWallpaper) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(saved ? "In Fotos gespeichert" : "Export ist fertig",
                  systemImage: saved ? "checkmark.circle.fill" : "checkmark.circle")
                .foregroundStyle(.mint)
                .font(.subheadline.weight(.semibold))
                .sensoryFeedback(.success, trigger: saved)

            if !saved {
                Button {
                    Task { await save(result) }
                } label: {
                    Group {
                        if saving { ProgressView() }
                        else { Label("In Fotos speichern", systemImage: "square.and.arrow.down") }
                    }
                    .frame(maxWidth: .infinity, minHeight: 39)
                }
                .buttonStyle(.glassProminent)
                .disabled(saving)
            }
            if result.kind == .live || result.kind == .still {
                Button {
                    showGuide = true
                } label: {
                    Label("Als Hintergrund einrichten", systemImage: "iphone")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.glass)
            }
            if result.kind != .live {
                ShareLink(item: result.file) {
                    Label("Datei teilen", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private func beginExport() {
        progress = 0
        saved = false
        let selectedKind = kind
        task = Task {
            defer { task = nil }
            do {
                let rendered = try await RenderEngine.render(media, edit: edit, kind: selectedKind) { value in
                    Task { @MainActor in progress = max(progress, value) }
                }
                try Task.checkCancellation()
                result = rendered
            } catch is CancellationError {
                progress = 0
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save(_ rendered: RenderedWallpaper) async {
        saving = true
        defer { saving = false }
        do {
            try await rendered.saveToPhotos()
            saved = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct WallpaperGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    Text("Ab auf den\nSperrbildschirm")
                        .font(.largeTitle.weight(.semibold))
                        .tracking(-1.4)
                    instruction("1", "In Fotos speichern",
                                "Exportiere ein Live Photo für Bewegung oder ein 4K-Foto als Standbild.")
                    instruction("2", "Neuen Hintergrund hinzufügen",
                                "Öffne Einstellungen → Hintergrundbild → Neues Hintergrundbild auswählen.")
                    instruction("3", "Foto auswählen",
                                "Wähle unter Fotos dein Bild aus. Aktiviere bei einem Live Photo die Wiedergabetaste für Bewegung beim Aufwecken.")
                    Link(destination: URL(string: "https://support.apple.com/de-de/120734")!) {
                        Label("Apple-Anleitung öffnen", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.glass)
                }
                .frame(maxWidth: 480, alignment: .leading)
                .padding(22)
                .frame(maxWidth: .infinity)
            }
            .background(Color(rgb: 0x111626).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
    }

    private func instruction(_ number: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text(number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.mint)
                .frame(width: 34, height: 34)
                .glassEffect(.regular, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
