import UIKit
import QuartzCore

class DSScreenView: UIView {
    var renderer: MetalRenderer?

    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        metalLayer.contentsScale = UIScreen.main.scale
        renderer = MetalRenderer(metalLayer: metalLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.drawableSize = CGSize(
            width: bounds.width * metalLayer.contentsScale,
            height: bounds.height * metalLayer.contentsScale
        )
    }

    func configureForExternalDisplay(screen: UIScreen) {
        metalLayer.contentsScale = screen.scale
        setNeedsLayout()
        renderer = MetalRenderer(metalLayer: metalLayer)
    }

    /// Maps a touch point in this view's coordinate space to DS screen coordinates (0-255, 0-191).
    /// Returns nil if the touch is outside the rendered DS screen area.
    func mapTouchToDS(point: CGPoint) -> (x: UInt16, y: UInt16)? {
        let viewSize = bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }

        let dsAspect: CGFloat = 256.0 / 192.0
        let viewAspect = viewSize.width / viewSize.height

        var renderRect: CGRect
        if viewAspect > dsAspect {
            // Pillarboxed (wider than 4:3)
            let renderWidth = viewSize.height * dsAspect
            let xOffset = (viewSize.width - renderWidth) / 2
            renderRect = CGRect(x: xOffset, y: 0, width: renderWidth, height: viewSize.height)
        } else {
            // Letterboxed (taller than 4:3)
            let renderHeight = viewSize.width / dsAspect
            let yOffset = (viewSize.height - renderHeight) / 2
            renderRect = CGRect(x: 0, y: yOffset, width: viewSize.width, height: renderHeight)
        }

        guard renderRect.contains(point) else { return nil }

        let normalX = (point.x - renderRect.minX) / renderRect.width
        let normalY = (point.y - renderRect.minY) / renderRect.height

        let dsX = UInt16(max(0, min(255, normalX * 256)))
        let dsY = UInt16(max(0, min(191, normalY * 192)))
        return (dsX, dsY)
    }
}
