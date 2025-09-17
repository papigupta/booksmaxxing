import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

struct BookCoverView: View {
    let thumbnailUrl: String?
    let coverUrl: String?
    let isLargeView: Bool
    
    @State private var image: PlatformImage? = nil
    @State private var isLoading = false
    
    init(thumbnailUrl: String? = nil, coverUrl: String? = nil, isLargeView: Bool = false) {
        self.thumbnailUrl = thumbnailUrl
        self.coverUrl = coverUrl
        self.isLargeView = isLargeView
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
                    .frame(width: isLargeView ? 200 : 60, height: isLargeView ? 300 : 90)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            } else {
                // Placeholder when no image
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: isLargeView ? 200 : 60, height: isLargeView ? 300 : 90)
                    .overlay(
                        Image(systemName: "book.closed")
                            .font(.system(size: isLargeView ? 40 : 20))
                            .foregroundColor(.gray.opacity(0.5))
                    )
            }
        }
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
                
                #if canImport(UIKit)
                let downloadedImage = UIImage(data: data)
                #elseif canImport(AppKit)
                let downloadedImage = NSImage(data: data)
                #else
                let downloadedImage: PlatformImage? = nil
                #endif
                
                if let downloadedImage = downloadedImage {
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
}