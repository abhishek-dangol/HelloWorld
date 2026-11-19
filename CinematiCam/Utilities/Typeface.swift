import CoreText
import SwiftUI

/// The app's one typeface: Bricolage Grotesque (a variable font, SIL Open Font License: see Fonts/BricolageGrotesque-OFL.txt).
/// Same font and setup as the DoomLess app. If the file is missing,
/// text falls back to the system font.
enum Typeface {
    /// Read straight from the bundled file, so nothing depends on an Info.plist font list.
    private static let base: CTFontDescriptor? = {
        guard let url = Bundle.main.url(forResource: "BricolageGrotesque", withExtension: "ttf"),
              let all = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return all.first
    }()

    // The font's 'wght' and 'opsz' axis tags as numbers, the way Core Text wants them.
    private static let weightAxis = 2_003_265_652
    private static let opticalSizeAxis = 1_869_640_570

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard let base else { return .system(size: size, weight: weight) }
        let variation: [NSNumber: NSNumber] = [
            NSNumber(value: weightAxis): NSNumber(value: axisValue(weight)),
            // Small text gets the sturdier small-size drawing, big text the tighter display drawing.
            NSNumber(value: opticalSizeAxis): NSNumber(value: Double(min(max(size, 12), 96))),
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute: variation] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }

    /// The font runs from 200 (extra light) to 800 (extra bold).
    private static func axisValue(_ weight: Font.Weight) -> Double {
        switch weight {
        case .ultraLight, .thin: 200
        case .light: 300
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy, .black: 800
        default: 400
        }
    }
}

extension Font {
    /// The app typeface at a fixed size.
    static func app(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { Typeface.font(size, weight: weight) }
}
