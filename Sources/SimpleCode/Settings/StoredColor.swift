import AppKit
import SwiftUI

/// Serializable sRGB color for settings persistence.
struct StoredColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = Double(converted.redComponent)
        self.green = Double(converted.greenComponent)
        self.blue = Double(converted.blueComponent)
        self.alpha = Double(converted.alphaComponent)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var swiftUIColor: Color { Color(nsColor: nsColor) }

    var isEditorForegroundReadable: Bool {
        alpha >= 0.5
    }
}

struct StoredColorPair: Codable, Equatable, Sendable {
    var light: StoredColor
    var dark: StoredColor

    var colorRolePair: ColorRolePair {
        ColorRolePair(light: light.nsColor, dark: dark.nsColor)
    }

    init(light: StoredColor, dark: StoredColor) {
        self.light = light
        self.dark = dark
    }

    init(pair: ColorRolePair) {
        self.light = StoredColor(nsColor: pair.light)
        self.dark = StoredColor(nsColor: pair.dark)
    }
}
