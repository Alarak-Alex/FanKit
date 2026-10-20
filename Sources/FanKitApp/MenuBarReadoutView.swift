import AppKit
import FanKitCore
import SwiftUI

/// The two-line readout drawn inside the menu bar button.
///
/// `NSStatusBarButton` sizes itself from the title, which makes a two-line
/// attributed title collapse onto one line. Drawing the label in a custom view
/// gives exact control over both lines and a fixed width.
final class MenuBarReadoutView: NSView {
    var temperature: Double? {
        didSet { needsDisplay = true }
    }
    var rpm: Double = 0 {
        didSet { needsDisplay = true }
    }
    var style: MenuBarStyle = .both {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    var twoLines = true {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    var showsIcon = true {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    private let iconSize: CGFloat = 14
    private let gap: CGFloat = 3

    override var intrinsicContentSize: NSSize {
        let text = textSize()
        let width = (showsIcon ? iconSize + gap : 0) + text.width + 6
        return NSSize(width: ceil(width), height: NSStatusBar.system.thickness)
    }

    private func primaryText() -> String? {
        switch style {
        case .temperature:
            return temperature.map { String(format: "%.0f°", $0) }
        case .fanSpeed:
            return "\(Int(rpm.rounded()))"
        case .both:
            return temperature.map { String(format: "%.0f°", $0) }
        }
    }

    private func secondaryText() -> String? {
        guard twoLines else { return nil }
        switch style {
        case .temperature:
            return "\(Int(rpm.rounded()))"
        case .fanSpeed:
            return temperature.map { String(format: "%.0f°", $0) }
        case .both:
            return "\(Int(rpm.rounded()))"
        }
    }

    private var primaryFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    }

    private var secondaryFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium)
    }

    private func textSize() -> NSSize {
        guard let primary = primaryText() else { return .zero }
        let primarySize = (primary as NSString).size(withAttributes: [.font: primaryFont])
        guard let secondary = secondaryText() else { return primarySize }
        let secondarySize = (secondary as NSString).size(withAttributes: [.font: secondaryFont])
        return NSSize(width: max(primarySize.width, secondarySize.width),
                      height: primarySize.height + secondarySize.height - 3)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let primary = primaryText() else { return }
        let color = NSColor.labelColor

        var x: CGFloat = 2
        if showsIcon, let icon = iconImage() {
            let y = (bounds.height - iconSize) / 2
            icon.draw(in: NSRect(x: x, y: y, width: iconSize, height: iconSize))
            x += iconSize + gap
        }

        let secondary = secondaryText()
        if let secondary {
            let primarySize = primary.size(withAttributes: [.font: primaryFont])
            let secondarySize = secondary.size(withAttributes: [.font: secondaryFont])
            let stackHeight = primarySize.height + secondarySize.height - 3
            let topY = (bounds.height - stackHeight) / 2
            primary.draw(at: NSPoint(x: x, y: topY + secondarySize.height - 3),
                         withAttributes: [.font: primaryFont, .foregroundColor: color])
            secondary.draw(at: NSPoint(x: x, y: topY),
                           withAttributes: [.font: secondaryFont,
                                            .foregroundColor: color.withAlphaComponent(0.75)])
        } else {
            let height = primary.size(withAttributes: [.font: primaryFont]).height
            primary.draw(at: NSPoint(x: x, y: (bounds.height - height) / 2),
                         withAttributes: [.font: primaryFont, .foregroundColor: color])
        }
    }

    private func iconImage() -> NSImage? {
        let name: String
        guard let celsius = temperature else { return symbol("fanblades") }
        switch celsius {
        case ..<60: name = "fanblades"
        case ..<80: name = "fanblades.fill"
        default: name = "flame.fill"
        }
        return symbol(name)
    }

    /// Symbols draw in black by default, which disappears on a dark menu bar.
    private func symbol(_ name: String) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: "FanKit") else {
            return nil
        }
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let config = NSImage.SymbolConfiguration(pointSize: iconSize - 2, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [isDark ? .white : .black]))
        return base.withSymbolConfiguration(config) ?? base
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
