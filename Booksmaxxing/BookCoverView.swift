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
    
    @State private var image: PlatformImage? = nil
    @State private var isLoading = false
    
    init(thumbnailUrl: String? = nil, coverUrl: String? = nil, isLargeView: Bool = false, cornerRadius: CGFloat? = nil) {
        self.thumbnailUrl = thumbnailUrl
        self.coverUrl = coverUrl
        self.isLargeView = isLargeView
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        Group {
            if let image = image {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #elseif canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #else
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #endif
            } else if isLoading {
                ProgressView()
                    .frame(width: isLargeView ? 240 : 60, height: isLargeView ? 320 : 90)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(cornerRadius ?? 8)
            } else {
                // Placeholder when no image
                RoundedRectangle(cornerRadius: cornerRadius ?? 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: isLargeView ? 240 : 60, height: isLargeView ? 320 : 90)
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
            loadImage()
        }
    }
    
    private func loadImage() {
        // Select appropriate URL based on view size
        let urlString = isLargeView ? (coverUrl ?? thumbnailUrl) : thumbnailUrl
        
        guard let urlString = urlString,
              let url = URL(string: urlString) else {
            return
        }
        
        isLoading = true
        
        // Check cache first
        if let cachedImage = ImageCache.shared.getImage(for: urlString) {
            self.image = cachedImage
            self.isLoading = false
            return
        }
        
        // Download image
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                // Downsample to target view size to reduce memory and upload cost
                let targetSize = isLargeView ? CGSize(width: 240, height: 320) : CGSize(width: 60, height: 90)
                let scale: CGFloat = {
                    #if canImport(UIKit)
                    return UIScreen.main.scale
                    #elseif canImport(AppKit)
                    return NSScreen.main?.backingScaleFactor ?? 2.0
                    #else
                    return 2.0
                    #endif
                }()

                if let downloadedImage = downsampledImage(data: data, to: targetSize, scale: scale) {
                    await MainActor.run {
                        self.image = downloadedImage
                        self.isLoading = false
                        // Cache the image
                        ImageCache.shared.setImage(downloadedImage, for: urlString)
                    }
                }
            } catch {
                print("Error loading book cover: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
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
