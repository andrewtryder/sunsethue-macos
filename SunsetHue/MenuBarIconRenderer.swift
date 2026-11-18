import AppKit
import SunsetHueCore
import SwiftUI

extension MenuBarAppearanceVariant {
    static func from(_ colorScheme: ColorScheme) -> MenuBarAppearanceVariant {
        colorScheme == .dark ? .dark : .light
    }
}

/// Renders and caches compact menu-bar status images in template or quality-tinted mode.
@MainActor
enum MenuBarIconRenderer {
    private static var cache: [MenuBarIconCacheKey: NSImage] = [:]
    private static let maxCacheEntries = 64
    private static let symbolConfiguration = NSImage.SymbolConfiguration(
        pointSize: 15,
        weight: .regular,
        scale: .medium
    )

    static func image(
        for descriptor: MenuBarIconDescriptor,
        appearance: MenuBarAppearanceVariant,
        isHighContrast: Bool
    ) -> NSImage {
        let key = descriptor.cacheKey(appearance: appearance, isHighContrast: isHighContrast)
        if let cached = cache[key] {
            return cached
        }

        let rendered = renderImage(
            for: descriptor,
            appearance: appearance,
            isHighContrast: isHighContrast
        )
        if cache.count >= maxCacheEntries {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = rendered
        return rendered
    }

    static func clearCache() {
        cache.removeAll(keepingCapacity: false)
    }

    static var cacheCount: Int {
        cache.count
    }

    private static func renderImage(
        for descriptor: MenuBarIconDescriptor,
        appearance: MenuBarAppearanceVariant,
        isHighContrast: Bool
    ) -> NSImage {
        let baseSymbol = configuredSymbolImage(named: descriptor.symbolName)

        guard let tier = descriptor.qualityTier, !descriptor.isTemplate else {
            let templateImage = (baseSymbol.copy() as? NSImage) ?? baseSymbol
            templateImage.isTemplate = true
            return templateImage
        }

        let tintCGColor = resolvedCGColor(
            for: tier,
            appearance: appearance,
            isHighContrast: isHighContrast
        )

        let pointSize = CGSize(
            width: max(1, ceil(baseSymbol.size.width)),
            height: max(1, ceil(baseSymbol.size.height))
        )
        let tinted = NSImage(size: pointSize)
        for scale in [1, 2] {
            if let rep = rasterizedTintedRep(
                symbol: baseSymbol,
                pointSize: pointSize,
                scale: scale,
                tintCGColor: tintCGColor
            ) {
                tinted.addRepresentation(rep)
            }
        }
        tinted.isTemplate = false
        tinted.alignmentRect = baseSymbol.alignmentRect
        return tinted
    }

    private static func configuredSymbolImage(named symbolName: String) -> NSImage {
        let raw = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "sun.horizon", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 16, height: 16))
        return raw.withSymbolConfiguration(symbolConfiguration) ?? raw
    }

    private static func resolvedCGColor(
        for tier: ForecastQualityTier,
        appearance variant: MenuBarAppearanceVariant,
        isHighContrast: Bool
    ) -> CGColor {
        if isHighContrast {
            return highContrastColor(for: tier, appearance: variant).cgColor
        }
        let baseColor = semanticNSColor(for: tier)
        guard let appearance = nsAppearance(for: variant) else {
            return baseColor.cgColor
        }
        var resolved = baseColor.cgColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = (baseColor.usingColorSpace(.sRGB) ?? baseColor).cgColor
        }
        return resolved
    }

    private static func highContrastColor(
        for tier: ForecastQualityTier,
        appearance variant: MenuBarAppearanceVariant
    ) -> NSColor {
        switch (tier, variant) {
        case (.poor, .light):
            NSColor(srgbRed: 0.84, green: 0.04, blue: 0.10, alpha: 1)
        case (.poor, .dark):
            NSColor(srgbRed: 1.00, green: 0.41, blue: 0.38, alpha: 1)
        case (.fair, .light):
            NSColor(srgbRed: 0.78, green: 0.33, blue: 0.00, alpha: 1)
        case (.fair, .dark):
            NSColor(srgbRed: 1.00, green: 0.70, blue: 0.25, alpha: 1)
        case (.good, .light):
            NSColor(srgbRed: 0.00, green: 0.32, blue: 0.85, alpha: 1)
        case (.good, .dark):
            NSColor(srgbRed: 0.30, green: 0.70, blue: 1.00, alpha: 1)
        case (.excellent, .light):
            NSColor(srgbRed: 0.08, green: 0.56, blue: 0.22, alpha: 1)
        case (.excellent, .dark):
            NSColor(srgbRed: 0.25, green: 0.90, blue: 0.45, alpha: 1)
        }
    }

    private static func nsAppearance(for variant: MenuBarAppearanceVariant) -> NSAppearance? {
        let name: NSAppearance.Name = switch variant {
        case .light: .aqua
        case .dark: .darkAqua
        }
        return NSAppearance(named: name)
    }

    private static func semanticNSColor(for tier: ForecastQualityTier) -> NSColor {
        switch tier {
        case .poor: .systemRed
        case .fair: .systemOrange
        case .good: .systemBlue
        case .excellent: .systemGreen
        }
    }

    private static func rasterizedTintedRep(
        symbol: NSImage,
        pointSize: CGSize,
        scale: Int,
        tintCGColor: CGColor
    ) -> NSBitmapImageRep? {
        let pixelWidth = max(1, Int(pointSize.width) * scale)
        let pixelHeight = max(1, Int(pointSize.height) * scale)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return nil
        }

        let drawRect = CGRect(origin: .zero, size: pointSize)
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.clear(drawRect)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        context.setBlendMode(.sourceAtop)
        context.setFillColor(tintCGColor)
        context.fill(drawRect)

        guard let cgImage = context.makeImage() else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = pointSize
        return rep
    }
}
