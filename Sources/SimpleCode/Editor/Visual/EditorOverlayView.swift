import AppKit

/// Draws editor visual guides and whitespace markers without mutating source text.
@MainActor
final class EditorOverlayView: NSView {
    weak var textView: CodeTextView?
    var showLongLineGuide = true
    var guideColumn = 100
    var showWhitespace = false
    var showTrailingWhitespace = false
    var findMatches: [NSRange] = []
    var activeFindMatch: NSRange?

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView else { return }
        if showLongLineGuide, let font = textView.font {
            let columnX = 6 + CGFloat(guideColumn) * ("0" as NSString).size(withAttributes: [.font: font]).width
            ColorRole.longLineGuideNSColor.setFill()
            NSRect(x: columnX, y: 0, width: 1, height: bounds.height).fill()
        }
        if showWhitespace || showTrailingWhitespace {
            drawWhitespaceMarkers(in: textView, dirtyRect: dirtyRect)
        }
        if !findMatches.isEmpty {
            drawFindMatches(in: textView, dirtyRect: dirtyRect)
        }
    }

    private func drawFindMatches(in textView: NSTextView, dirtyRect: NSRect) {
        for range in findMatches where range.length > 0 {
            let isActive = activeFindMatch == range
            let color = isActive
                ? NSColor.systemOrange.withAlphaComponent(0.34)
                : NSColor.systemYellow.withAlphaComponent(0.28)
            color.setFill()
            for rect in rects(forCharacterRange: range, in: textView) where rect.intersects(dirtyRect) {
                NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: 2, yRadius: 2).fill()
            }
        }
    }

    private func rects(forCharacterRange range: NSRange, in textView: NSTextView) -> [NSRect] {
        guard textView.window != nil else { return [] }
        var rects: [NSRect] = []
        var remaining = range

        while remaining.length > 0 {
            var actual = NSRange(location: NSNotFound, length: 0)
            let screenRect = textView.firstRect(forCharacterRange: remaining, actualRange: &actual)
            guard actual.location != NSNotFound, actual.length > 0, !screenRect.isEmpty else { break }
            let windowRect = textView.window?.convertFromScreen(screenRect) ?? screenRect
            rects.append(convert(windowRect, from: nil))

            let nextLocation = actual.location + actual.length
            let end = range.location + range.length
            guard nextLocation < end else { break }
            remaining = NSRange(location: nextLocation, length: end - nextLocation)
        }

        return rects
    }

    private func drawWhitespaceMarkers(in textView: NSTextView, dirtyRect: NSRect) {
        let color = ColorRole.whitespaceMarkerNSColor
        let text = textView.string as NSString
        let visibleRange = visibleCharacterRange(in: textView)
        let visibleEnd = NSMaxRange(visibleRange)

        var lineLocation = visibleRange.location
        while lineLocation < visibleEnd && lineLocation < text.length {
            let fullLineRange = text.lineRange(for: NSRange(location: lineLocation, length: 0))
            let contentRange = contentRangeExcludingLineEnding(fullLineRange, in: text)
            let trailingStart = trailingWhitespaceStart(in: contentRange, text: text)
            let drawStart = max(contentRange.location, visibleRange.location)
            let drawEnd = min(NSMaxRange(contentRange), visibleEnd)

            if drawStart < drawEnd {
                for location in drawStart..<drawEnd {
                    let codeUnit = text.character(at: location)
                    let isSpace = codeUnit == 32
                    let isTab = codeUnit == 9
                    guard isSpace || isTab else { continue }
                    let isTrailing = location >= trailingStart
                    guard showWhitespace || (showTrailingWhitespace && isTrailing) else { continue }
                    guard let rect = rects(forCharacterRange: NSRange(location: location, length: 1), in: textView).first,
                          rect.intersects(dirtyRect) else { continue }

                    if isSpace {
                        let dotRect = NSRect(x: rect.midX - 1, y: rect.midY - 1, width: 2, height: 2)
                        color.setFill()
                        NSBezierPath(ovalIn: dotRect).fill()
                    } else if showWhitespace {
                        let path = NSBezierPath()
                        path.move(to: NSPoint(x: rect.minX + 2, y: rect.midY))
                        path.line(to: NSPoint(x: rect.maxX - 2, y: rect.midY))
                        path.line(to: NSPoint(x: rect.maxX - 5, y: rect.midY + 3))
                        color.setStroke()
                        path.stroke()
                    }
                }
            }

            let nextLine = NSMaxRange(fullLineRange)
            if nextLine <= lineLocation { break }
            lineLocation = nextLine
        }
    }

    private func visibleCharacterRange(in textView: NSTextView) -> NSRange {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return NSRange(location: 0, length: (textView.string as NSString).length)
        }
        let glyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        if charRange.location == NSNotFound {
            return NSRange(location: 0, length: (textView.string as NSString).length)
        }
        return charRange
    }

    private func contentRangeExcludingLineEnding(_ lineRange: NSRange, in text: NSString) -> NSRange {
        var length = lineRange.length
        if length > 0 {
            let last = text.character(at: lineRange.location + length - 1)
            if last == 10 {
                length -= 1
                if length > 0, text.character(at: lineRange.location + length - 1) == 13 {
                    length -= 1
                }
            } else if last == 13 {
                length -= 1
            }
        }
        return NSRange(location: lineRange.location, length: length)
    }

    private func trailingWhitespaceStart(in contentRange: NSRange, text: NSString) -> Int {
        var location = NSMaxRange(contentRange)
        while location > contentRange.location {
            let previous = location - 1
            let codeUnit = text.character(at: previous)
            guard codeUnit == 32 || codeUnit == 9 else { break }
            location = previous
        }
        return location
    }
}
