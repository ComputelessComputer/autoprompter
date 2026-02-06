import AppKit
import SwiftUI

struct TeleprompterTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var highlightRange: NSRange?
    let isEditable: Bool
    let fontSize: CGFloat
    let scrollAnimationDuration: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = NSColor.white
        textView.insertionPointColor = NSColor.white
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.delegate = context.coordinator
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable
        textView.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)

        context.coordinator.scrollAnimationDuration = scrollAnimationDuration
        context.coordinator.applyHighlight(range: highlightRange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: TeleprompterTextView
        weak var textView: NSTextView?
        private var lastHighlightRange: NSRange?
        var scrollAnimationDuration: Double = 0.18

        init(parent: TeleprompterTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
        }

        @MainActor func applyHighlight(range: NSRange?) {
            guard let textView, let textStorage = textView.textStorage else { return }

            if let last = lastHighlightRange, last.location != NSNotFound, last.length > 0 {
                textStorage.removeAttribute(.backgroundColor, range: last)
            }

            guard let range, range.location != NSNotFound, range.length > 0 else {
                lastHighlightRange = nil
                return
            }

            textStorage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: range)
            lastHighlightRange = range
            scrollToRange(range)
        }

        @MainActor private func scrollToRange(_ range: NSRange) {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else { return }

            layoutManager.ensureLayout(for: textContainer)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x = 0
            rect.size.width = textView.bounds.width

            let visible = scrollView.contentView.bounds
            let targetY = rect.midY - visible.height / 2
            let maxY = max(0, textView.bounds.height - visible.height)
            let clampedY = min(max(0, targetY), maxY)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = scrollAnimationDuration
                scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: clampedY))
            }
        }
    }
}
