import AppKit
import Foundation

/// Renders a small Cursor mark followed by three usage bars.
enum BarsRenderer {
    private static let barCount = 3
    private static let barWidth: CGFloat = 7
    private static let innerGap: CGFloat = 2
    private static let sideInset: CGFloat = 1
    private static let height: CGFloat = 18
    private static let vInset: CGFloat = 0
    private static let corner: CGFloat = 1.5

    private static let letterFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 9, weight: .bold)
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.width: -0.4]
        ])
        return NSFont(descriptor: descriptor, size: 9) ?? base
    }()

    private static let iconWidth: CGFloat = 12
    private static let iconHeight: CGFloat = 14
    private static let iconGap: CGFloat = 3

    private static let trackAlpha: CGFloat = 0.28
    private static let fillAlpha: CGFloat = 1.0
    private static let cursorBlack = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.09, alpha: 1)

    private static var barsWidth: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * innerGap
    }

    private static func barsOriginX(showIcon: Bool) -> CGFloat {
        showIcon ? sideInset + iconWidth + iconGap : sideInset
    }

    private static func width(showIcon: Bool) -> CGFloat {
        barsOriginX(showIcon: showIcon) + barsWidth + sideInset
    }

    private static let countdownFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

    static func image(for bars: [BarSpec], monochrome: Bool, showLetters: Bool, showIcon: Bool, countdown: String?) -> NSImage {
        if let countdown = countdown {
            return renderCountdown(countdown, monochrome: monochrome, showIcon: showIcon)
        }
        return renderBars(for: bars, monochrome: monochrome, showLetters: showLetters, showIcon: showIcon)
    }

    private static func renderBars(for bars: [BarSpec], monochrome: Bool, showLetters: Bool, showIcon: Bool) -> NSImage {
        let fractions: [CGFloat?] = (0..<barCount).map { index in
            index < bars.count ? max(0, min(1, CGFloat(bars[index].percent / 100))) : nil
        }
        let letters: [String] = showLetters
            ? (0..<barCount).map { index in index < bars.count ? bars[index].letter : "" }
            : Array(repeating: "", count: barCount)
        let fillColors: [NSColor]? = monochrome ? nil : (0..<barCount).map { index in
            index < bars.count ? severityColor(bars[index]) : .clear
        }
        return render(fractions: fractions, letters: letters, fillColors: fillColors, showIcon: showIcon)
    }

    private static func renderCountdown(_ text: String, monochrome: Bool, showIcon: Bool) -> NSImage {
        let str = text as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: countdownFont]
        let textSize = str.size(withAttributes: attrs)
        let textOriginX = barsOriginX(showIcon: showIcon)
        let w = textOriginX + ceil(textSize.width) + sideInset
        let size = NSSize(width: w, height: height)

        let textColor: NSColor = monochrome ? .black : .systemRed
        let iconColor = monochrome ? NSColor.black.withAlphaComponent(fillAlpha) : cursorBlack

        let image = NSImage(size: size, flipped: false) { _ in
            if showIcon {
                let iconRect = NSRect(x: sideInset, y: (height - iconHeight) / 2, width: iconWidth, height: iconHeight)
                drawCursorGlyph(in: iconRect, color: iconColor)
            }

            let origin = NSPoint(x: textOriginX, y: (height - textSize.height) / 2)
            str.draw(at: origin, withAttributes: [.font: countdownFont, .foregroundColor: textColor])
            return true
        }
        image.isTemplate = monochrome
        return image
    }

    static func placeholder(monochrome: Bool, showLetters: Bool, showIcon: Bool) -> NSImage {
        render(
            fractions: Array(repeating: nil, count: barCount),
            letters: showLetters ? ["f", "a", "o"] : ["", "", ""],
            fillColors: monochrome ? nil : [],
            showIcon: showIcon
        )
    }

    private static func render(fractions: [CGFloat?], letters: [String], fillColors: [NSColor]?, showIcon: Bool) -> NSImage {
        let monochrome = fillColors == nil
        let size = NSSize(width: width(showIcon: showIcon), height: height)
        let usableHeight = height - vInset * 2
        let barsOriginX = barsOriginX(showIcon: showIcon)

        let image = NSImage(size: size, flipped: false) { _ in
            if showIcon {
                let iconRect = NSRect(x: sideInset, y: (height - iconHeight) / 2, width: iconWidth, height: iconHeight)
                let iconColor = monochrome ? NSColor.black.withAlphaComponent(fillAlpha) : cursorBlack
                drawCursorGlyph(in: iconRect, color: iconColor)
            }

            for index in 0..<barCount {
                let x = barsOriginX + CGFloat(index) * (barWidth + innerGap)
                let track = NSRect(x: x, y: vInset, width: barWidth, height: usableHeight)
                let trackColor = monochrome ? NSColor.black.withAlphaComponent(trackAlpha) : NSColor.tertiaryLabelColor
                trackColor.setFill()
                NSBezierPath(roundedRect: track, xRadius: corner, yRadius: corner).fill()

                let fraction = index < fractions.count ? fractions[index] : nil
                let fillHeight = (fraction ?? 0) > 0 ? max(1, usableHeight * (fraction ?? 0)) : 0
                if fillHeight > 0 {
                    let fill = NSRect(x: x, y: vInset, width: barWidth, height: fillHeight)
                    let fillColor = monochrome
                        ? NSColor.black.withAlphaComponent(fillAlpha)
                        : (index < (fillColors?.count ?? 0) ? fillColors![index] : .clear)
                    fillColor.setFill()
                    NSBezierPath(roundedRect: fill, xRadius: corner, yRadius: corner).fill()
                }

                guard index < letters.count, !letters[index].isEmpty else { continue }
                let letterCenter = NSPoint(x: x + barWidth / 2, y: vInset + usableHeight / 2)
                let overFill = fillHeight >= usableHeight / 2
                drawLetterInside(letters[index], center: letterCenter, monochrome: monochrome, overFill: overFill)
            }
            return true
        }
        image.isTemplate = monochrome
        return image
    }

    private static func drawLetterInside(_ s: String, center: NSPoint, monochrome: Bool, overFill: Bool) {
        let str = s as NSString
        let sizingAttrs: [NSAttributedString.Key: Any] = [.font: letterFont]
        let textSize = str.size(withAttributes: sizingAttrs)
        let origin = NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2)

        guard let ctx = NSGraphicsContext.current else { return }
        if monochrome {
            if overFill {
                let previous = ctx.compositingOperation
                ctx.compositingOperation = .destinationOut
                str.draw(at: origin, withAttributes: [.font: letterFont, .foregroundColor: NSColor.black])
                ctx.compositingOperation = previous
            } else {
                str.draw(at: origin, withAttributes: [.font: letterFont, .foregroundColor: NSColor.black])
            }
        } else {
            let color: NSColor = overFill ? .white : .labelColor
            str.draw(at: origin, withAttributes: [.font: letterFont, .foregroundColor: color])
        }
    }

    private static func drawCursorGlyph(in rect: NSRect, color: NSColor) {
        color.setFill()
        color.setStroke()

        // Cursor-style cube mark: dark hex body with a triangular cutout.
        let r = rect.insetBy(dx: 0.5, dy: 0.5)
        let body = NSBezierPath()
        body.move(to: NSPoint(x: r.midX, y: r.maxY))
        body.line(to: NSPoint(x: r.maxX, y: r.minY + r.height * 0.72))
        body.line(to: NSPoint(x: r.maxX, y: r.minY + r.height * 0.28))
        body.line(to: NSPoint(x: r.midX, y: r.minY))
        body.line(to: NSPoint(x: r.minX, y: r.minY + r.height * 0.28))
        body.line(to: NSPoint(x: r.minX, y: r.minY + r.height * 0.72))
        body.close()
        body.fill()

        guard let ctx = NSGraphicsContext.current else { return }
        let previous = ctx.compositingOperation
        ctx.compositingOperation = .destinationOut
        NSColor.black.setFill()

        let cutout = NSBezierPath()
        cutout.move(to: NSPoint(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.66))
        cutout.line(to: NSPoint(x: r.maxX - r.width * 0.12, y: r.minY + r.height * 0.66))
        cutout.line(to: NSPoint(x: r.minX + r.width * 0.52, y: r.minY + r.height * 0.08))
        cutout.line(to: NSPoint(x: r.minX + r.width * 0.52, y: r.minY + r.height * 0.46))
        cutout.close()
        cutout.fill()
        ctx.compositingOperation = previous
    }

    private static func severityColor(_ bar: BarSpec) -> NSColor {
        switch bar.severity.lowercased() {
        case "warning":
            return .systemOrange
        case "critical", "blocked", "exceeded", "over_limit", "overlimit", "exhausted", "limit_reached":
            return .systemRed
        default:
            if bar.percent >= 95 { return .systemRed }
            if bar.percent >= 80 { return .systemOrange }
            return .systemGreen
        }
    }
}
