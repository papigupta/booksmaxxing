import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#elseif os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

struct AutoGrowingTextView: View {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var isDisabled: Bool
    var font: PlatformFont
    var textColor: PlatformColor
    var kerning: CGFloat
    var onActivity: (() -> Void)?

    var body: some View {
        #if os(iOS)
        AutoGrowingTextViewRepresentable(
            text: $text,
            measuredHeight: $measuredHeight,
            minHeight: minHeight,
            maxHeight: maxHeight,
            isDisabled: isDisabled,
            font: font,
            textColor: textColor,
            kerning: kerning,
            onActivity: onActivity
        )
        .frame(height: measuredHeight)
        #elseif os(macOS)
        AutoGrowingTextViewRepresentable(
            text: $text,
            measuredHeight: $measuredHeight,
            minHeight: minHeight,
            maxHeight: maxHeight,
            isDisabled: isDisabled,
            font: font,
            textColor: textColor,
            kerning: kerning,
            onActivity: onActivity
        )
        .frame(height: measuredHeight)
        #endif
    }
}

#if os(iOS)
private struct AutoGrowingTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let isDisabled: Bool
    let font: UIFont
    let textColor: UIColor
    let kerning: CGFloat
    let onActivity: (() -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = context.coordinator
        textView.adjustsFontForContentSizeCategory = true
        textView.keyboardDismissMode = .interactive
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.accessibilityTraits.insert(.allowsDirectInteraction)
        context.coordinator.updateConfiguration(for: textView)
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
        }
        uiView.isEditable = !isDisabled
        uiView.isSelectable = !isDisabled
        context.coordinator.updateConfiguration(for: uiView)
        context.coordinator.refreshHeightIfNeeded(for: uiView)
        handleFocusIfNeeded(for: uiView, context: context)
    }
    
    private func handleFocusIfNeeded(for textView: UITextView, context: Context) {
        if context.environment.isFocused && !isDisabled {
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        } else if textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }
    
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoGrowingTextViewRepresentable
        private var cachedHeight: CGFloat = 0
        
        init(parent: AutoGrowingTextViewRepresentable) {
            self.parent = parent
            super.init()
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            onActivity()
            refreshHeightIfNeeded(for: textView)
            ensureCaretVisible(in: textView)
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            onActivity()
        }
        
        func updateConfiguration(for textView: UITextView) {
            textView.font = parent.font
            textView.textColor = parent.textColor
            let attributes: [NSAttributedString.Key: Any] = [
                .kern: parent.kerning,
                .font: parent.font,
                .foregroundColor: parent.textColor
            ]
            textView.typingAttributes = attributes
            textView.linkTextAttributes = attributes
        }
        
        func refreshHeightIfNeeded(for textView: UITextView) {
            let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
            guard size.height > 0 else { return }
            let clamped = min(max(parent.minHeight, size.height), parent.maxHeight)
            if abs(clamped - cachedHeight) > 0.5 {
                cachedHeight = clamped
                DispatchQueue.main.async {
                    parent.measuredHeight = clamped
                }
            }
            textView.isScrollEnabled = size.height > parent.maxHeight
            if textView.isScrollEnabled {
                ensureCaretVisible(in: textView)
            }
        }
        
        private func ensureCaretVisible(in textView: UITextView) {
            let range = textView.selectedRange
            textView.scrollRangeToVisible(range)
        }
        
        private func onActivity() {
            parent.onActivity?()
        }
    }
}
#elseif os(macOS)
private struct AutoGrowingTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let isDisabled: Bool
    let font: NSFont
    let textColor: NSColor
    let kerning: CGFloat
    let onActivity: (() -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView?.borderType = .noBorder
        scrollView?.hasVerticalScroller = false
        scrollView?.drawsBackground = false
        let textView = scrollView?.documentView as? NSTextView
        textView?.backgroundColor = .clear
        textView?.isVerticallyResizable = true
        textView?.isHorizontallyResizable = false
        textView?.textContainer?.widthTracksTextView = true
        textView?.textContainerInset = .zero
        textView?.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.updateConfiguration(for: textView)
        return scrollView!
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = !isDisabled
        textView.isSelectable = !isDisabled
        context.coordinator.updateConfiguration(for: textView)
        context.coordinator.refreshHeightIfNeeded(for: textView)
        handleFocusIfNeeded(for: textView, context: context)
    }
    
    private func handleFocusIfNeeded(for textView: NSTextView, context: Context) {
        if context.environment.isFocused && !isDisabled {
            if textView.window?.firstResponder != textView {
                textView.window?.makeFirstResponder(textView)
            }
        } else if textView.window?.firstResponder == textView {
            textView.window?.resignFirstResponder()
        }
    }
    
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoGrowingTextViewRepresentable
        weak var textView: NSTextView?
        private var cachedHeight: CGFloat = 0
        
        init(parent: AutoGrowingTextViewRepresentable) {
            self.parent = parent
            super.init()
        }
        
        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            onActivity()
            refreshHeightIfNeeded(for: tv)
            ensureCaretVisible(in: tv)
        }
        
        func textDidBeginEditing(_ notification: Notification) {
            onActivity()
        }
        
        func updateConfiguration(for textView: NSTextView?) {
            guard let textView = textView else { return }
            textView.font = parent.font
            textView.textColor = parent.textColor
            let attributes: [NSAttributedString.Key: Any] = [
                .kern: parent.kerning,
                .font: parent.font,
                .foregroundColor: parent.textColor
            ]
            textView.typingAttributes = attributes
        }
        
        func refreshHeightIfNeeded(for textView: NSTextView) {
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let size = textView.intrinsicContentSize
            guard size.height > 0 else { return }
            let clamped = min(max(parent.minHeight, size.height), parent.maxHeight)
            if abs(clamped - cachedHeight) > 0.5 {
                cachedHeight = clamped
                DispatchQueue.main.async {
                    parent.measuredHeight = clamped
                }
            }
            let needsScroll = size.height > parent.maxHeight
            textView.enclosingScrollView?.hasVerticalScroller = needsScroll
            if needsScroll {
                ensureCaretVisible(in: textView)
            }
        }
        
        private func ensureCaretVisible(in textView: NSTextView) {
            guard let range = textView.selectedRanges.first as? NSRange else { return }
            textView.scrollRangeToVisible(range)
        }
        
        private func onActivity() {
            parent.onActivity?()
        }
    }
}
#endif
