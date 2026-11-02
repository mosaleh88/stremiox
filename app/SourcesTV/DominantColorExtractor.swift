import UIKit
import SwiftUI

/// Extracts the dominant tint color from an image URL asynchronously once per item.
/// Caches the result in-memory so Apple TV HD (A8) never incurs repeated processing or live blurs.
@MainActor
final class DominantColorExtractor: ObservableObject {
    static let shared = DominantColorExtractor()

    private let cache = NSCache<NSString, UIColor>()

    private init() {
        cache.countLimit = 200
    }

    /// Extract dominant color from image URL asynchronously with lightweight 16x16 downsampling.
    func extractColor(for urlString: String?) async -> Color? {
        guard let urlString = urlString, let url = URL(string: urlString) else { return nil }
        let key = urlString as NSString
        if let cached = cache.object(forKey: key) {
            return Color(cached)
        }

        return await Task.detached(priority: .background) { () -> Color? in
            var req = URLRequest(url: url)
            req.cachePolicy = .returnCacheDataElseLoad
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let image = UIImage(data: data) else { return nil }

            let size = CGSize(width: 16, height: 16)
            UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: size))
            guard let context = UIGraphicsGetCurrentContext(),
                  let pixelBuffer = context.data else {
                UIGraphicsEndImageContext()
                return nil
            }
            UIGraphicsEndImageContext()

            let pixelPointer = pixelBuffer.bindMemory(to: UInt8.self, capacity: 16 * 16 * 4)
            var rTotal: UInt64 = 0
            var gTotal: UInt64 = 0
            var bTotal: UInt64 = 0
            let totalPixels: UInt64 = 16 * 16

            for i in 0..<Int(totalPixels) {
                let offset = i * 4
                // RGBA / BGRA format depending on graphics context
                rTotal += UInt64(pixelPointer[offset])
                gTotal += UInt64(pixelPointer[offset + 1])
                bTotal += UInt64(pixelPointer[offset + 2])
            }

            let avgR = CGFloat(rTotal / totalPixels) / 255.0
            let avgG = CGFloat(gTotal / totalPixels) / 255.0
            let avgB = CGFloat(bTotal / totalPixels) / 255.0

            let uiColor = UIColor(red: avgR, green: avgG, blue: avgB, alpha: 1.0)
            await MainActor.run {
                DominantColorExtractor.shared.cache.setObject(uiColor, forKey: key)
            }
            return Color(uiColor)
        }.value
    }
}

