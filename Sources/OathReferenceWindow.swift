import AppKit

/// A selectable reference built from the same oath text the matcher tests use.
final class OathReferenceWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "The Lantern Oaths"
        window.minSize = NSSize(width: 400, height: 320)
        window.isReleasedWhenClosed = false

        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 24, height: 20)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width - 48, height: CGFloat.greatestFiniteMagnitude)
        text.setAccessibilityLabel("Lantern oath reference")

        let content = NSMutableAttributedString()
        func append(_ string: String, size: CGFloat = 14, weight: NSFont.Weight = .regular) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            paragraph.paragraphSpacing = 14
            content.append(NSAttributedString(string: string + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]))
        }
        append("The Lantern Oaths", size: 24, weight: .semibold)
        append("Switch on Listen for the Oath in the menu, then recite an oath below. "
               + "Listening switches off when an oath is accepted. Seal the Lantern releases "
               + "the chosen corps; unplugging releases it too. The oath changes the emblem, "
               + "while your battery continues charging normally.")
        for oath in OathListener.oaths {
            append(oath.name, size: 17, weight: .semibold)
            append(oath.text)
        }
        text.textStorage?.setAttributedString(content)
        scroll.documentView = text
        window.contentView?.addSubview(scroll)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}
