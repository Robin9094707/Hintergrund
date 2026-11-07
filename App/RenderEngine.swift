import AVFoundation
import CoreImage
import ImageIO
import Photos
import UniformTypeIdentifiers

enum ExportKind: String, CaseIterable, Identifiable {
    case live = "Live Photo"
    case still = "4K-Foto"
    case movie = "4K-Video"

    var id: Self { self }
    var icon: String {
        switch self {
        case .live: "livephoto"
        case .still: "photo"
        case .movie: "film"
        }
    }
    var detail: String {
        switch self {
        case .live: "Bewegung für den Sperrbildschirm"
        case .still: "2160 × 3840 · JPEG"
        case .movie: "2160 × 3840 · MP4 · 30 fps · ohne Ton"
        }
    }
}

struct RenderedWallpaper {
    let kind: ExportKind
    let file: URL
    let pairedMovie: URL?

    func saveToPhotos() async throws {
        guard [.authorized, .limited].contains(await PHPhotoLibrary.requestAuthorization(for: .addOnly)) else {
            throw StudioError.photosAccess
        }
        let kind = kind
        let file = file
        let pairedMovie = pairedMovie
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: kind == .movie ? .video : .photo, fileURL: file, options: nil)
            if let pairedMovie {
                request.addResource(with: .pairedVideo, fileURL: pairedMovie, options: nil)
            }
        }
    }
}

enum RenderEngine {
    static let context = CIContext(options: [.cacheIntermediates: false])
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static func render(_ media: StudioMedia, edit: WallpaperEdit, kind: ExportKind,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> RenderedWallpaper {
        let folder = try Workspace.makeDirectory()
        do {
            let size = kind == .live ? CGSize(width: 1080, height: 1920) : CGSize(width: 2160, height: 3840)
            switch kind {
            case .still:
                let image = try await stillImage(media, time: edit.start + edit.keyFrame, size: size)
                let output = folder.appendingPathComponent("RJ-Wallpaper-4K.jpg")
                try writeJPEG(compose(image, edit: edit, size: size), size: size, at: output, identifier: nil)
                progress(1)
                return RenderedWallpaper(kind: kind, file: output, pairedMovie: nil)
            case .movie, .live:
                let isLive = kind == .live
                let identifier = isLive ? UUID().uuidString : nil
                let video = folder.appendingPathComponent(isLive ? "RJ-Live.mov" : "RJ-Wallpaper-4K.mp4")
                let photo = isLive ? folder.appendingPathComponent("RJ-Live.jpg") : nil
                try await writeMovie(media, edit: edit, size: size, at: video, photo: photo,
                                     identifier: identifier, progress: progress)
                return RenderedWallpaper(kind: kind, file: photo ?? video, pairedMovie: isLive ? video : nil)
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private static func stillImage(_ media: StudioMedia, time: Double, size: CGSize) async throws -> CIImage {
        if let preset = media.preset { return preset.image(size: size) }
        if let gif = media.gif {
            guard let image = AnimatedImage.thumbnail(gif.source, index: gif.index(at: time), limit: 6144) else {
                throw StudioError.unreadable
            }
            return CIImage(cgImage: image)
        }
        guard let url = media.url else { throw StudioError.unreadable }
        if media.kind == .image {
            guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
                throw StudioError.unreadable
            }
            return image
        }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 24)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 24)
        let seconds = min(time, max(0, media.duration - 1.0 / 30))
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        return CIImage(cgImage: image)
    }

    private static func compose(_ source: CIImage, edit: WallpaperEdit, size: CGSize) -> CIImage {
        let bounds = CGRect(origin: .zero, size: size)
        let extent = source.extent
        let rect = edit.crop(source: extent.size, canvas: size)
        let scale = rect.width / extent.width
        var image = source
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: size.height - rect.maxY))
            .cropped(to: bounds)
        let values = edit.look.values
        if edit.look.temperature != 6500 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: edit.look.temperature, y: 0)
            ])
        }
        if edit.look != .original {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: values.saturation,
                kCIInputBrightnessKey: values.brightness,
                kCIInputContrastKey: values.contrast
            ])
        }
        let background = CIImage(color: .black).cropped(to: bounds)
        image = image.composited(over: background)
        if edit.shade > 0 {
            let shade = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: edit.shade)).cropped(to: bounds)
            image = shade.composited(over: image)
        }
        return image
    }

    private static func writeJPEG(_ image: CIImage, size: CGSize, at url: URL, identifier: String?) throws {
        guard let cgImage = context.createCGImage(image, from: CGRect(origin: .zero, size: size),
                                                 format: .RGBA8, colorSpace: colorSpace),
              let target = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw StudioError.encode
        }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.96]
        if let identifier {
            properties[kCGImagePropertyMakerAppleDictionary] = ["17": identifier]
        }
        CGImageDestinationAddImage(target, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(target) else { throw StudioError.encode }
    }

    private static func writeMovie(_ media: StudioMedia, edit: WallpaperEdit, size: CGSize, at output: URL,
                                   photo: URL?, identifier: String?,
                                   progress: @escaping @Sendable (Double) -> Void) async throws {
        let width = Int(size.width)
        let height = Int(size.height)
        let writer = try AVAssetWriter(outputURL: output, fileType: photo == nil ? .mp4 : .mov)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: photo == nil ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: photo == nil ? 24_000_000 : 12_000_000,
                AVVideoExpectedSourceFrameRateKey: 30
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ])
        guard writer.canAdd(input) else { throw StudioError.encode }
        writer.add(input)
        let buffers = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])

        let timedMetadata: AVAssetWriterInputMetadataAdaptor?
        if let identifier {
            let item = AVMutableMetadataItem()
            item.keySpace = .quickTimeMetadata
            item.key = "com.apple.quicktime.content.identifier" as NSString
            item.value = identifier as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            writer.metadata = [item]
            timedMetadata = try stillImageMetadata(writer)
        } else {
            timedMetadata = nil
        }

        // A Live Photo uses up to three seconds. Pad very short clips by repeating their last frame.
        let seconds = photo == nil ? edit.length : max(1, min(3, edit.length))
        let count = max(1, Int((seconds * 30).rounded()))
        let keyIndex = min(count - 1, max(0, Int((edit.keyFrame * 30).rounded())))
        let reader: MovieFrames?
        if media.kind == .video, let url = media.url {
            reader = try await MovieFrames.open(url: url, start: edit.start, duration: edit.length)
        } else {
            reader = nil
        }
        guard writer.startWriting() else { throw writer.error ?? StudioError.encode }
        writer.startSession(atSourceTime: .zero)
        defer {
            reader?.cancel()
            if writer.status == .writing { writer.cancelWriting() }
        }
        if let timedMetadata {
            let item = AVMutableMetadataItem()
            item.keySpace = .quickTimeMetadata
            item.key = "com.apple.quicktime.still-image-time" as NSString
            item.value = 0 as NSNumber
            item.dataType = kCMMetadataBaseDataType_SInt8 as String
            let range = CMTimeRange(start: CMTime(value: Int64(keyIndex), timescale: 30),
                                    duration: CMTime(value: 1, timescale: 30))
            guard timedMetadata.append(AVTimedMetadataGroup(items: [item], timeRange: range)) else {
                throw writer.error ?? StudioError.encode
            }
            timedMetadata.assetWriterInput.markAsFinished()
        }

        var lastGIFIndex: Int?
        var lastGIFImage: CIImage?
        for frame in 0..<count {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? StudioError.encode }
                try await Task.sleep(for: .milliseconds(5))
            }
            let time = edit.start + min(Double(frame) / 30, max(0, edit.length - 1.0 / 60))
            try autoreleasepool {
                let source: CIImage
                if let reader {
                    source = try reader.image(at: time)
                } else if let gif = media.gif {
                    let index = gif.index(at: time)
                    if index != lastGIFIndex {
                        guard let image = AnimatedImage.thumbnail(gif.source, index: index, limit: 6144) else {
                            throw StudioError.unreadable
                        }
                        lastGIFImage = CIImage(cgImage: image)
                        lastGIFIndex = index
                    }
                    guard let lastGIFImage else { throw StudioError.unreadable }
                    source = lastGIFImage
                } else {
                    throw StudioError.emptyVideo
                }
                let composed = compose(source, edit: edit, size: size)
                if frame == keyIndex, let photo {
                    try writeJPEG(composed, size: size, at: photo, identifier: identifier)
                }
                guard let pool = buffers.pixelBufferPool else { throw StudioError.encode }
                var pixelBuffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
                      let pixelBuffer else { throw StudioError.encode }
                context.render(composed, to: pixelBuffer, bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
                guard buffers.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                    throw writer.error ?? StudioError.encode
                }
            }
            if frame.isMultiple(of: 6) { progress(Double(frame + 1) / Double(count) * 0.95) }
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(count), timescale: 30))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? StudioError.encode }
        progress(1)
    }

    private static func stillImageMetadata(_ writer: AVAssetWriter) throws -> AVAssetWriterInputMetadataAdaptor {
        let specification: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_SInt8
        ]
        var format: CMFormatDescription?
        let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [specification] as CFArray, formatDescriptionOut: &format
        )
        guard status == noErr, let format else { throw StudioError.encode }
        let input = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: format)
        guard writer.canAdd(input) else { throw StudioError.encode }
        writer.add(input)
        return AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
    }
}

private final class MovieFrames {
    let reader: AVAssetReader
    let output: AVAssetReaderTrackOutput
    let transform: CGAffineTransform
    var previous: CMSampleBuffer?
    var next: CMSampleBuffer?

    init(reader: AVAssetReader, output: AVAssetReaderTrackOutput, transform: CGAffineTransform) {
        self.reader = reader
        self.output = output
        self.transform = transform
        next = output.copyNextSampleBuffer()
    }

    static func open(url: URL, start: Double, duration: Double) async throws -> MovieFrames {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw StudioError.emptyVideo
        }
        let preferred = try await track.load(.preferredTransform)
        let transform = CGAffineTransform(a: preferred.a, b: -preferred.b, c: -preferred.c, d: preferred.d,
                                          tx: preferred.tx, ty: -preferred.ty)
        let reader = try AVAssetReader(asset: asset)
        let readerStart = max(0, start - 0.15)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: readerStart, preferredTimescale: 600),
                                       duration: CMTime(seconds: duration + start - readerStart, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw StudioError.emptyVideo }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? StudioError.emptyVideo }
        return MovieFrames(reader: reader, output: output, transform: transform)
    }

    func image(at seconds: Double) throws -> CIImage {
        while let sample = next, sample.presentationTimeStamp.seconds <= seconds + 0.0001 {
            previous = sample
            next = output.copyNextSampleBuffer()
        }
        if reader.status == .failed { throw reader.error ?? StudioError.emptyVideo }
        guard let sample = previous ?? next, let buffer = CMSampleBufferGetImageBuffer(sample) else {
            throw StudioError.emptyVideo
        }
        return CIImage(cvPixelBuffer: buffer).transformed(by: transform)
    }

    func cancel() { reader.cancelReading() }
}
