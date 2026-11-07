import AVFoundation
import SwiftUI

struct PreviewCanvas: View {
    let media: StudioMedia
    @Binding var edit: WallpaperEdit
    let playing: Bool
    let showsLockScreen: Bool
    @GestureState private var drag = CGSize.zero
    @GestureState private var magnification = CGFloat(1)

    var body: some View {
        GeometryReader { geometry in
            let adjusted = displayedEdit(geometry.size)
            let rect = adjusted.crop(source: media.size, canvas: geometry.size)
            ZStack(alignment: .topLeading) {
                Color.black
                artwork
                    .frame(width: rect.width, height: rect.height)
                    .saturation(adjusted.look.values.saturation)
                    .brightness(adjusted.look.values.brightness)
                    .contrast(adjusted.look.values.contrast)
                    .overlay {
                        if adjusted.look == .amber || adjusted.look == .frost {
                            (adjusted.look == .amber ? Color.orange : Color.cyan)
                                .opacity(0.12).blendMode(.softLight)
                        }
                        Color.black.opacity(adjusted.shade)
                    }
                    .position(x: rect.midX, y: rect.midY)
                if showsLockScreen { lockScreen(width: geometry.size.width) }
            }
            .clipped()
            .contentShape(.rect)
            .gesture(DragGesture().updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    let result = adjustedCrop(geometry.size, scale: 1, translation: value.translation)
                    edit.x = result.x
                    edit.y = result.y
                })
            .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
                .onEnded { value in edit.zoom = min(3, max(1, edit.zoom * value.magnification)) })
        }
        .accessibilityLabel("Vorschau des Hintergrundbilds")
    }

    @ViewBuilder private var artwork: some View {
        if media.kind == .video, let url = media.url {
            VideoSurface(url: url, playing: playing, start: edit.start, duration: edit.length,
                         selectedTime: edit.start + edit.keyFrame)
        } else if let gif = media.gif {
            GIFSurface(gif: gif, poster: media.poster, playing: playing, start: edit.start,
                       duration: edit.length, keyFrame: edit.keyFrame)
        } else {
            Image(decorative: media.poster, scale: 1).resizable()
        }
    }

    private func lockScreen(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: width * 0.18)
            Image(systemName: "lock.fill")
                .font(.system(size: width * 0.045, weight: .semibold))
                .padding(.bottom, 7)
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                .font(.system(size: width * 0.058, weight: .semibold))
            Text("09:41")
                .font(.system(size: width * 0.29, weight: .semibold, design: .rounded))
                .tracking(-width * 0.017)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Spacer()
            Capsule().fill(.white.opacity(0.65)).frame(width: width * 0.34, height: 3).padding(.bottom, 11)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white.opacity(0.92))
        .shadow(color: .black.opacity(0.48), radius: 7, y: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func displayedEdit(_ size: CGSize) -> WallpaperEdit {
        adjustedCrop(size, scale: magnification, translation: drag)
    }

    private func adjustedCrop(_ size: CGSize, scale: CGFloat, translation: CGSize) -> WallpaperEdit {
        var result = edit
        result.zoom = min(3, max(1, edit.zoom * scale))
        let crop = result.crop(source: media.size, canvas: size)
        let horizontal = max(0, crop.width - size.width)
        let vertical = max(0, crop.height - size.height)
        if horizontal > 0 { result.x = min(1, max(-1, result.x + 2 * translation.width / horizontal)) }
        if vertical > 0 { result.y = min(1, max(-1, result.y + 2 * translation.height / vertical)) }
        return result
    }
}

private struct GIFSurface: View {
    let gif: AnimatedImage
    let poster: CGImage
    let playing: Bool
    let start: Double
    let duration: Double
    let keyFrame: Double
    @State private var cache = GIFPreviewCache()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !playing)) { context in
            let phase = context.date.timeIntervalSince(cache.epoch).truncatingRemainder(dividingBy: max(duration, 0.01))
            let index = gif.index(at: start + (playing ? max(0, phase) : keyFrame))
            Image(decorative: cache.image(for: index, gif: gif) ?? poster, scale: 1).resizable()
        }
        .onChange(of: playing) { _, _ in cache.epoch = .now }
        .onChange(of: start) { _, _ in cache.epoch = .now }
        .onChange(of: duration) { _, _ in cache.epoch = .now }
    }
}

private final class GIFPreviewCache {
    var epoch = Date.now
    private let cache = NSCache<NSNumber, UIImage>()

    init() { cache.totalCostLimit = 16 * 1024 * 1024 }

    func image(for index: Int, gif: AnimatedImage) -> CGImage? {
        let key = NSNumber(value: index)
        if let image = cache.object(forKey: key)?.cgImage { return image }
        guard let image = AnimatedImage.thumbnail(gif.source, index: index, limit: 640) else { return nil }
        cache.setObject(UIImage(cgImage: image), forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}

private struct VideoSurface: UIViewRepresentable {
    let url: URL
    let playing: Bool
    let start: Double
    let duration: Double
    let selectedTime: Double

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.setURL(url)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.update(playing: playing, start: start, duration: duration, selectedTime: selectedTime)
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) { view.stop() }
}

private final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private let player = AVPlayer()
    private var observer: Any?
    private var playing = false
    private var start = -1.0
    private var duration = -1.0
    private var selectedTime = -1.0
    private var generation = 0

    func setURL(_ url: URL) {
        let layer = layer as! AVPlayerLayer
        layer.player = player
        layer.videoGravity = .resize
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            guard let self, self.playing, time.seconds >= self.start + self.duration - 1.0 / 40 else { return }
            self.seek(self.start, resume: true)
        }
    }

    func update(playing: Bool, start: Double, duration: Double, selectedTime: Double) {
        let changed = self.start != start || self.duration != duration || self.playing != playing
        let stillChanged = self.selectedTime != selectedTime
        self.playing = playing
        self.start = start
        self.duration = duration
        self.selectedTime = selectedTime
        if changed || (!playing && stillChanged) {
            player.pause()
            seek(playing ? start : min(selectedTime, start + max(0, duration - 1.0 / 60)), resume: playing)
        }
    }

    private func seek(_ time: Double, resume: Bool) {
        generation += 1
        let expected = generation
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, self.generation == expected, self.playing, finished, resume else { return }
                self.player.play()
            }
        }
    }

    func stop() {
        playing = false
        player.pause()
        if let observer {
            player.removeTimeObserver(observer)
            self.observer = nil
        }
        player.replaceCurrentItem(with: nil)
    }
}
