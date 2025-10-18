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
    private let pathBuilder: (CGRect) -> Path
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
        .clipShape(
            cornerRadius != nil
                ? AnyShape(RoundedRectangle(cornerRadius: cornerRadius!, style: .continuous))
                : AnyShape(Rectangle())
        )
        .onAppear {
            loadImagesProgressively(target: size)
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
                        let scale = currentScale()
                        if let img = downsampledImage(data: data, to: target, scale: scale) {
                            await MainActor.run {
                                self.lowResImage = img
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
                        let scale = currentScale()
                        if let img = downsampledImage(data: data, to: target, scale: scale) {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    self.highResImage = img
                                }
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

    private func currentScale() -> CGFloat {
        #if canImport(UIKit)
        return UIScreen.main.scale
        #elseif canImport(AppKit)
        return NSScreen.main?.backingScaleFactor ?? 2.0
        #else
        return 2.0
        #endif
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
                let scale: CGFloat = {
                    #if canImport(UIKit)
                    return UIScreen.main.scale
                    #elseif canImport(AppKit)
                    return NSScreen.main?.backingScaleFactor ?? 2.0
                    #else
                    return 2.0
                    #endif
                }()
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
