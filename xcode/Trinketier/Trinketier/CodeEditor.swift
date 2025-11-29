//
//  CodeEditor.swift
//  Trinketier
//
//  Created by Marijn Brussel on 29/11/2025.
//

import SwiftUI
import AppKit

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var disabled: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isEditable = !disabled
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = NSColor(red: 0.99, green: 0.99, blue: 0.99, alpha: 1.0) // Retro White
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 8, height: 8) // Inner padding
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.backgroundColor = NSColor(red: 0.99, green: 0.99, blue: 0.99, alpha: 1.0) // Retro White
        scrollView.drawsBackground = true

        // Initial content
        context.coordinator.applyHighlighting(text, to: textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            context.coordinator.applyHighlighting(text, to: textView)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        private var isUpdatingFromCode = false

        init(_ parent: CodeEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromCode,
                  let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            parent.text = newText
            applyHighlighting(newText, to: textView)
        }

        func applyHighlighting(_ text: String, to textView: NSTextView) {
            isUpdatingFromCode = true
            defer { isUpdatingFromCode = false }

            let attributed = NSMutableAttributedString(string: text)
            let fullRange = NSRange(location: 0, length: (text as NSString).length)

            // Base attributes
            attributed.addAttribute(.font,
                                    value: NSFont.monospacedSystemFont(ofSize: 14,
                                                                       weight: .regular),
                                    range: fullRange)
            attributed.addAttribute(.foregroundColor, value: NSColor.black, range: fullRange)

            // Very simple Python keywords highlighter
            let keywords = ["def", "class", "import", "from", "for", "while", "if", "elif", "else",
                            "return", "try", "except", "with", "as", "True", "False", "None", "print"]
            let keywordColor = NSColor(red: 0.0, green: 0.0, blue: 0.8, alpha: 1.0) // Dark Blue
            let keywordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"

            if let regex = try? NSRegularExpression(pattern: keywordPattern, options: []) {
                regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                    if let matchRange = match?.range(at: 1) {
                        attributed.addAttribute(.foregroundColor, value: keywordColor, range: matchRange)
                    }
                }
            }

            // Strings
            if let stringRegex = try? NSRegularExpression(pattern: #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'"#,
                                                          options: []) {
                let stringColor = NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0) // Dark Red
                stringRegex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                    if let r = match?.range {
                        attributed.addAttribute(.foregroundColor, value: stringColor, range: r)
                    }
                }
            }

            // Comments (# ...)
            if let commentRegex = try? NSRegularExpression(pattern: "#.*$", options: [.anchorsMatchLines]) {
                let commentColor = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0) // Dark Green
                commentRegex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                    if let r = match?.range {
                        attributed.addAttribute(.foregroundColor, value: commentColor, range: r)
                    }
                }
            }

            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributed)
            
            // Restore selection if valid
            if selectedRange.location + selectedRange.length <= attributed.length {
                textView.setSelectedRange(selectedRange)
            }
        }
    }
}
