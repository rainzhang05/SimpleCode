import AppKit

@MainActor
enum BracketHighlightRenderer {
    static func drawBracketPair(
        in textView: NSTextView,
        openLocation: Int,
        closeLocation: Int
    ) {
        let color = ColorRole.editorSelectionNSColor.withAlphaComponent(0.45)
        for location in [openLocation, closeLocation] {
            guard location >= 0, location < (textView.string as NSString).length else { continue }
            var rect = textView.firstRect(forCharacterRange: NSRange(location: location, length: 1), actualRange: nil)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            color.setFill()
            rect.fill()
        }
    }
}
