import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private let studioMint = Color(rgb: 0x9FFFE5)
private let studioBackground = Color(rgb: 0x0C1020)

struct StudioView: View {
    @State private var media = try? StudioMedia.makePreset(.aurora)
    @State private var edit = WallpaperEdit()
    @State private var playing = false
    @State private var overlays = true
    @State private var pickerItem: PhotosPickerItem?
    @State private var choosingPhotos = false
    @State private var choosingFile = false
    @State private var importing = false
    @State private var exportSheet = false
    @State private var lockScreenSheet = false
    @State private var lockScreenPlayer = LockScreenPlayer()
    @State private var guideSheet = false
    @State private var error: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    introduction
                    if let media {
                        preview(media)
                        trimControls(media)
                        cropControls
                        lookControls
                    }
                    presets
                }
                .padding(.horizontal, 19)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .frame(maxWidth: 575)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background {
                ZStack {
                    studioBackground
                    RadialGradient(colors: [Color(rgb: 0x262449), .clear], center: .topTrailing,
                                   startRadius: 0, endRadius: 480)
                }
                .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkle").foregroundStyle(studioMint)
                        Text("RJ WALLPAPER").font(.system(.caption, design: .monospaced, weight: .bold))
                            .tracking(2)
                    }
                    .accessibilityLabel("RJ Wallpaper")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hilfe", systemImage: "questionmark", action: { guideSheet = true })
                        .labelStyle(.iconOnly)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        }
        .sensoryFeedback(.selection, trigger: edit.look)
        .sheet(isPresented: $guideSheet) { WallpaperGuide() }
        .sheet(isPresented: $exportSheet, onDismiss: resumePreview) {
            if let media {
                ExportPanel(media: media, edit: edit)
            }
        }
        .sheet(isPresented: $lockScreenSheet, onDismiss: resumePreview) {
            if let media {
                LockScreenPanel(media: media, edit: edit, player: lockScreenPlayer)
            }
        }
        .photosPicker(isPresented: $choosingPhotos, selection: $pickerItem,
                      matching: .any(of: [.images, .videos]), preferredItemEncoding: .current)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image, .movie, .video]) { result in
            switch result {
            case .success(let url):
                Task { await importFromFiles(url) }
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await importFromPhotos(item) }
        }
        .alert("Import fehlgeschlagen", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEIN LOCKSCREEN. DEIN LOOK.")
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(studioMint)
                .accessibilityHidden(true)
            Text("Wallpaper\nStudio")
                .font(.system(size: 53, weight: .semibold, design: .default))
                .tracking(-3)
                .lineSpacing(-12)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Mach aus deinen Fotos, GIFs und Videos dein eigenes iPhone-Wallpaper.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func preview(_ media: StudioMedia) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Circle().fill(studioMint).frame(width: 5, height: 5)
                Text("VORSCHAU").tracking(1.8)
                Spacer()
                Text(media.label).foregroundStyle(studioMint)
                Text("·")
                Text("9:16")
            }
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .foregroundStyle(.white.opacity(0.68))
            .accessibilityHidden(true)

            PreviewCanvas(media: media, edit: $edit, playing: playing && !exportSheet && !lockScreenSheet,
                          showsLockScreen: overlays)
                .id(media.id)
                .aspectRatio(9.0 / 16, contentMode: .fit)
                .frame(maxWidth: 270)
                .clipShape(.rect(cornerRadius: 35))
                .overlay {
                    RoundedRectangle(cornerRadius: 35).strokeBorder(.white.opacity(0.25), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.42), radius: 18, y: 9)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)

            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(media.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(media.hasMotion ? "\(media.duration.formatted(.number.precision(.fractionLength(1)))) s" : "Standbild")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button(overlays ? "Uhr ausblenden" : "Uhr einblenden", systemImage: overlays ? "clock.fill" : "clock") {
                    overlays.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                if media.hasMotion {
                    Button(playing ? "Pause" : "Abspielen", systemImage: playing ? "pause.fill" : "play.fill") {
                        playing.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                }
            }
            if media.hasMotion || lockScreenPlayer.isActive {
                Button {
                    playing = false
                    lockScreenSheet = true
                } label: {
                    Label("Sperrbildschirm-Player", systemImage: lockScreenPlayer.isPlaying ? "waveform" : "play.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 27).fill(.white.opacity(0.055))
            RoundedRectangle(cornerRadius: 27).strokeBorder(.white.opacity(0.095))
        }
    }

    @ViewBuilder private func trimControls(_ media: StudioMedia) -> some View {
        if media.hasMotion {
            VStack(alignment: .leading, spacing: 11) {
                sectionTitle("Ausschnitt", icon: "timeline.selection")
                if media.duration > edit.length + 0.001 {
                    slider("Start", value: Binding(get: { edit.start }, set: { edit.start = $0 }),
                           range: 0...max(0.01, media.duration - edit.length), display: seconds(edit.start))
                }
                if media.duration > 0.51 {
                    let limit = min(30, media.duration)
                    slider("Dauer", value: Binding(get: { edit.length }, set: { length in
                        edit.length = length
                        edit.start = min(edit.start, max(0, media.duration - length))
                        edit.keyFrame = min(edit.keyFrame, length)
                    }), range: 0.5...limit, display: seconds(edit.length))
                }
                slider("Titelbild", value: Binding(get: { edit.keyFrame }, set: {
                    playing = false
                    edit.keyFrame = $0
                }), range: 0...max(0.01, edit.length), display: seconds(edit.keyFrame))
                Text("Live Photos verwenden bis zu 2 Sekunden rund um das Titelbild. Der 4K-Videoexport übernimmt den ganzen Ausschnitt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cropControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Bildausschnitt", icon: "crop")
                Spacer()
                if edit.zoom != 1 || edit.x != 0 || edit.y != 0 || edit.shade != 0 {
                    Button("Zurücksetzen") {
                        edit.zoom = 1
                        edit.x = 0
                        edit.y = 0
                        edit.shade = 0
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            slider("Zoom", value: $edit.zoom, range: 1...3, display: "\(Int(edit.zoom * 100)) %")
            slider("Abdunkeln", value: $edit.shade, range: 0...0.65, display: "\(Int(edit.shade * 100)) %")
            Text("Zieh das Bild in der Vorschau, um es auszurichten. Zoome mit zwei Fingern oder dem Regler.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var lookControls: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Looks", icon: "slider.horizontal.3")
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(WallpaperLook.allCases) { look in
                        Button {
                            edit.look = look
                        } label: {
                            HStack(spacing: 5) {
                                Circle().fill(look.tint).frame(width: 6, height: 6)
                                Text(look.rawValue).font(.caption.weight(.semibold))
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.glass)
                        .tint(edit.look == look ? studioMint : .white)
                        .accessibilityAddTraits(edit.look == look ? .isSelected : [])
                    }
                }
                .padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Studio-Kollektion", icon: "square.grid.2x2")
            HStack(spacing: 8) {
                ForEach(StudioPreset.allCases) { preset in
                    Button {
                        if let sample = try? StudioMedia.makePreset(preset) {
                            select(sample)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 11) {
                            Image(systemName: preset.symbol).font(.body.weight(.medium))
                            Text(preset.rawValue).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.76)
                        }
                        .foregroundStyle(.white)
                        .padding(11)
                        .frame(maxWidth: .infinity, minHeight: 75, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 15).fill(
                                .linearGradient(colors: [Color(rgb: preset.palette.glow).opacity(0.72),
                                                         Color(rgb: preset.palette.base)],
                                                startPoint: .topTrailing, endPoint: .bottomLeading)
                            )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 15)
                                .strokeBorder(media?.preset == preset ? studioMint : .white.opacity(0.15),
                                              lineWidth: media?.preset == preset ? 1.5 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(media?.preset == preset ? .isSelected : [])
                }
            }
        }
    }

    private var actionBar: some View {
        GlassEffectContainer(spacing: 11) {
            HStack(spacing: 11) {
                Menu {
                    Button("Aus Fotos", systemImage: "photo.on.rectangle") { choosingPhotos = true }
                    Button("Aus Dateien", systemImage: "folder") { choosingFile = true }
                } label: {
                    Group {
                        if importing { ProgressView() }
                        else { Label("Import", systemImage: "plus").font(.subheadline.weight(.semibold)) }
                    }
                    .frame(minWidth: 78, minHeight: 50)
                    .padding(.horizontal, 10)
                    .contentShape(.capsule)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityLabel("Importieren")
                .disabled(importing)

                Button {
                    playing = false
                    exportSheet = true
                } label: {
                    Label("Exportieren", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.glassProminent)
                .disabled(media == nil || importing)
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 20)
        .padding(.top, 9)
        .padding(.bottom, 3)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label {
            Text(title).font(.headline)
        } icon: {
            Image(systemName: icon).foregroundStyle(studioMint).font(.subheadline)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(spacing: 1) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(display).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).accessibilityLabel(title).accessibilityValue(display)
        }
    }

    private func seconds(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(2)))) s"
    }

    private func select(_ sample: StudioMedia) {
        media = sample
        edit = .fresh(for: sample)
        resumePreview()
    }

    private func resumePreview() { playing = media?.hasMotion == true && !reduceMotion }

    private func importFromPhotos(_ item: PhotosPickerItem) async {
        guard !importing else { return }
        importing = true
        defer {
            importing = false
            pickerItem = nil
        }
        do {
            guard let imported = try await item.loadTransferable(type: PickedMedia.self) else {
                throw StudioError.unreadable
            }
            select(try await StudioMedia.open(imported.url))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func importFromFiles(_ url: URL) async {
        guard !importing else { return }
        importing = true
        defer { importing = false }
        do {
            let copied = try await Task.detached {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try Workspace.copy(url)
            }.value
            select(try await StudioMedia.open(copied))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
