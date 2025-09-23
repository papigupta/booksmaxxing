import SwiftUI
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ImageSampler {
    static func downsampleToCGImage(_ image: PlatformImage, maxDimension: Int = 64) -> CGImage? {
        #if canImport(UIKit)
        let size = image.size
        let scale = min(CGFloat(maxDimension)/max(size.width, size.height), 1)
        let target = CGSize(width: max(1, size.width*scale), height: max(1, size.height*scale))
        UIGraphicsBeginImageContextWithOptions(target, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: target))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized?.cgImage
        #elseif canImport(AppKit)
        let size = image.size
        let scale = min(CGFloat(maxDimension)/max(size.width, size.height), 1)
        let target = NSSize(width: max(1, size.width*scale), height: max(1, size.height*scale))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep = rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
        #else
        return nil
        #endif
    }

    static func extractRGBAPixels(_ cgImage: CGImage) -> [UInt8] {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        var data = [UInt8](repeating: 0, count: Int(height * bytesPerRow))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return []
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }
}
