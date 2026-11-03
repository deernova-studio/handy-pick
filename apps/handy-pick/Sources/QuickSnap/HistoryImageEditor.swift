import AppKit

/// The same annotation canvas as screenshot editing, with an external toolbar
/// so small images and window resizing never shrink or obscure the controls.
final class HistoryImageEditor: PaperlightSurface {
    let editor: SelectionView
    let toolbar: PaperlightGlass
    private let logicalSize: NSSize

    init(image: CGImage, size: NSSize) {
        // Match initial display points so text and strokes start at the same
        // readable size as the screenshot editor, regardless of image resolution.
        let scale = min(max(1, size.width-32) / CGFloat(image.width), max(1, size.height-88) / CGFloat(image.height))
        logicalSize = NSSize(width: CGFloat(image.width)*scale, height: CGFloat(image.height)*scale)
        editor = SelectionView(image: image, editsWholeImage: true)
        toolbar = editor.makeToolbar()
        super.init(frame: NSRect(origin: .zero, size: size))
        addSubview(editor); addSubview(toolbar)
        layout()
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    override func layout() {
        super.layout()
        let area = NSRect(x: 16, y: 16, width: max(1, bounds.width-32), height: max(1, bounds.height-88))
        let scale = min(area.width/logicalSize.width, area.height/logicalSize.height)
        let size = NSSize(width: logicalSize.width*scale, height: logicalSize.height*scale)
        editor.frame = NSRect(x: area.midX-size.width/2, y: area.midY-size.height/2, width: size.width, height: size.height)
        // Keep annotations in stable coordinates while the window is resized.
        editor.setBoundsSize(logicalSize)
        toolbar.frame = NSRect(x: (bounds.width-264)/2, y: bounds.height-60, width: 264, height: 44)
    }
}
