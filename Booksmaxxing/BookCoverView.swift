import SwiftUI
import ImageIO
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

// Utility to allow conditional clipShape
struct AnyShape: Shape {
    private let pathBuilder: @Sendable (CGRect) -> Path
    init<S: Shape>(_ wrapped: S) { self.pathBuilder = { rect in wrapped.path(in: rect) } }
    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
}

struct BookCoverView: View {
    let thumbnailUrl: String?
    let coverUrl: String?
    let isLargeView: Bool
    let cornerRadius: CGFloat?
    // Optional explicit target size to match container (e.g., 56x84)
    let targetSize: CGSize?

    // Progressive images: show low-res while high-res loads
    @State private var lowResImage: PlatformImage? = nil
    @State private var highResImage: PlatformImage? = nil
    @State private var isLoading = false
    // Average color extracted from the currently displayed image
    @State private var averageColor: Color? = nil

    // Rectangle overlay sizing ratios (relative to cover size)
    private let overlayWidthRatio: CGFloat = 0.17
    private let overlayHeightRatio: CGFloat = 0.17

    init(
        thumbnailUrl: String? = nil,
        coverUrl: String? = nil,
        isLargeView: Bool = false,
        cornerRadius: CGFloat? = nil,
        targetSize: CGSize? = nil
    ) {
        self.thumbnailUrl = thumbnailUrl
        self.coverUrl = coverUrl
        self.isLargeView = isLargeView
        self.cornerRadius = cornerRadius
        self.targetSize = targetSize
    }
    
    var body: some View {
        let size = targetSize ?? (isLargeView ? CGSize(width: 240, height: 320) : CGSize(width: 60, height: 90))
        let useFillMode = (targetSize != nil) // lists/grids want exact thumbnail fill; large views should preserve aspect
        Group {
            if let image = (highResImage ?? lowResImage) {
                #if canImport(UIKit)
                Group {
                    if useFillMode {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .clipped()
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                #elseif canImport(AppKit)
                Group {
                    if useFillMode {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .clipped()
                    } else {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                #else
                Group {
                    if useFillMode {
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .clipped()
                    } else {
                        Image(systemName: "photo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                #endif
            } else if isLoading {
                ProgressView()
                    .frame(width: useFillMode ? size.width : nil, height: useFillMode ? size.height : nil)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(cornerRadius ?? 8)
            } else {
                // Placeholder when no image
                RoundedRectangle(cornerRadius: cornerRadius ?? 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: useFillMode ? size.width : nil, height: useFillMode ? size.height : nil)
                    .overlay(
                        Image(systemName: "book.closed")
                            .font(.system(size: isLargeView ? 42 : 20))
                            .foregroundColor(.gray.opacity(0.5))
                    )
            }
        }
        // Add the bottom-right rectangle overlay sized proportionally to the cover
        .overlay {
            GeometryReader { proxy in
                let w = proxy.size.width * overlayWidthRatio
                let h = proxy.size.height * overlayHeightRatio
                Rectangle()
                    .fill(averageColor ?? Color.gray.opacity(0.2))
                    .frame(width: w, height: h)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .clipShape(
            cornerRadius != nil
                ? AnyShape(RoundedRectangle(cornerRadius: cornerRadius!, style: .continuous))
                : AnyShape(Rectangle())
        )
        .onAppear {
            loadImagesProgressively(target: size)
        }
        // Recompute overlay color when the displayed image changes
        .onChange(of: lowResImage) { _, newValue in
            if let img = newValue { averageColor = computeAverageColor(from: img) }
        }
        .onChange(of: highResImage) { _, newValue in
            if let img = newValue { averageColor = computeAverageColor(from: img) }
        }
    }
    
    private func loadImagesProgressively(target: CGSize) {
        // Determine URLs
        let thumb = thumbnailUrl
        let cover = isLargeView ? (coverUrl ?? thumbnailUrl) : nil // only upgrade to hi-res in large contexts

        // Nothing to load
        if thumb == nil && cover == nil { return }

        isLoading = true

        // Load thumbnail first
        if let thumbStr = thumb {
            if let cached = ImageCache.shared.getImage(for: thumbStr) {
                self.lowResImage = cached
                self.isLoading = false
            } else if let url = URL(string: thumbStr) {
                Task {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let scale = await currentDisplayScale()
                        if let img = downsampledImage(data: data, to: target, scale: scale) {
                            await MainActor.run {
                                self.lowResImage = img
                                self.averageColor = self.computeAverageColor(from: img)
                                self.isLoading = false
                                ImageCache.shared.setImage(img, for: thumbStr)
                            }
                        }
                    } catch {
                        await MainActor.run { self.isLoading = cover == nil }
                    }
                }
            }
        }

        // Load high-res cover in background (if provided)
        if let coverStr = cover, let url = URL(string: coverStr) {
            if let cached = ImageCache.shared.getImage(for: coverStr) {
                self.highResImage = cached
                self.isLoading = false
            } else {
                Task {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let scale = await currentDisplayScale()
                        if let img = downsampledImage(data: data, to: target, scale: scale) {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    self.highResImage = img
                                }
                                self.averageColor = self.computeAverageColor(from: img)
                                self.isLoading = false
                                ImageCache.shared.setImage(img, for: coverStr)
                            }
                        }
                    } catch {
                        // Keep low-res visible; don't flip back to spinner
                    }
                }
            }
        }
    }

}

// MARK: - Average color sampling
extension BookCoverView {
    /// Computes a quick average color from a downsampled version of the image.
    /// Ignores fully transparent pixels.
    fileprivate func computeAverageColor(from image: PlatformImage) -> Color? {
        // Keep this small for performance; we just need an approximate tone.
        let maxDim = 40
        guard let cg = ImageSampler.downsampleToCGImage(image, maxDimension: maxDim) else { return nil }
        let pixels = ImageSampler.extractRGBAPixels(cg)
        if pixels.isEmpty { return nil }
        var rTotal: Double = 0
        var gTotal: Double = 0
        var bTotal: Double = 0
        var count: Double = 0
        var i = 0
        while i < pixels.count {
            let a = pixels[i+3]
            if a > 8 { // exclude near-transparent
                rTotal += Double(pixels[i])
                gTotal += Double(pixels[i+1])
                bTotal += Double(pixels[i+2])
                count += 1
            }
            i += 4
        }
        guard count > 0 else { return nil }
        let r = rTotal / (255.0 * count)
        let g = gTotal / (255.0 * count)
        let b = bTotal / (255.0 * count)
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Downsampling helper
private func downsampledImage(data: Data, to pointSize: CGSize, scale: CGFloat) -> PlatformImage? {
    let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: Int(maxDimensionInPixels)
    ]
    guard let cfData = data as CFData?,
          let source = CGImageSourceCreateWithData(cfData, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return nil
    }
    #if canImport(UIKit)
    return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    #elseif canImport(AppKit)
    let size = NSSize(width: pointSize.width, height: pointSize.height)
    let image = NSImage(cgImage: cgImage, size: size)
    return image
    #else
    return nil
    #endif
}

// Simple image cache to avoid re-downloading
class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, PlatformImage>()
    
    private init() {
        cache.countLimit = 100 // Cache up to 100 images
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }
    
    func getImage(for key: String) -> PlatformImage? {
        return cache.object(forKey: key as NSString)
    }
    
    func setImage(_ image: PlatformImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    // Prefetch and cache a downsampled image in the background
    func prefetch(urlString: String, targetSize: CGSize) {
        if self.getImage(for: urlString) != nil { return }
        guard let url = URL(string: urlString) else { return }
        Task.detached(priority: .background) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let scale = await currentDisplayScale()
                if let img = downsampledImage(data: data, to: targetSize, scale: scale) {
                    await MainActor.run {
                        self.setImage(img, for: urlString)
                    }
                }
            } catch {
                // Silently ignore prefetch errors
            }
        }
    }
}

private func currentDisplayScale() async -> CGFloat {
#if canImport(UIKit)
    return await MainActor.run { UIScreen.main.scale }
#elseif canImport(AppKit)
    return await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }
#else
    return 2.0
#endif
}
