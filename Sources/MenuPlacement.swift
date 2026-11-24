import AppKit

enum MenuPlacement {
    static func volumeFrame(size: CGSize, horizontal: CGFloat, barBottom: CGFloat, screen: CGRect) -> CGRect {
        let x = max(screen.minX + 2, min(horizontal - size.width / 2, screen.maxX - size.width - 2))
        return CGRect(x: x.rounded(), y: (barBottom - 1 - size.height).rounded(), width: size.width, height: size.height)
    }

    static func menuTop(click: CGPoint, barBottom: CGFloat, width: CGFloat, screen: CGRect) -> CGPoint {
        CGPoint(x: max(screen.minX + 2, min(click.x, screen.maxX - width - 3)),
                y: min(click.y - 2, barBottom - 1))
    }
}
