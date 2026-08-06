import AppKit

/// Ikona trójkąta do paska menu, kolorowana stanem zbiorczym.
public enum StatusIconRenderer {

    /// Alpha pulsu ikony przy buildzie: 0,55 → 1,0 → 0,55 (cosinusoida, okres = faza 0…1).
    public static func pulseAlpha(phase: Double) -> Double {
        0.55 + 0.45 * (0.5 - 0.5 * cos(2 * .pi * phase))
    }

    public static func color(for state: AggregateState) -> NSColor {
        switch state {
        case .ready: return Theme.ready
        case .building: return Theme.building
        case .error: return Theme.error
        case .idle: return Theme.gray
        }
    }

    /// Trójkąt 15×13 pt (proporcje logo Vercela, viewBox 26×23 z makiet) — wierzchołek u góry.
    public static func image(state: AggregateState, alpha: Double = 1) -> NSImage {
        let size = NSSize(width: 15, height: 13)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.midX, y: rect.maxY - 0.5))
            path.line(to: NSPoint(x: rect.maxX - 0.3, y: rect.minY + 0.5))
            path.line(to: NSPoint(x: rect.minX + 0.3, y: rect.minY + 0.5))
            path.close()
            color(for: state).withAlphaComponent(alpha).setFill()
            path.fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
