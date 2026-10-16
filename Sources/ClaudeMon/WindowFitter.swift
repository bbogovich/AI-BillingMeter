import AppKit
import SwiftUI

/// Keeps the `MenuBarExtra` window the height of its content, anchored under the menu bar.
///
/// A `.window`-style MenuBarExtra grows when its content grows but never shrinks back.
/// Shorter content is then centred in the oversized window, so the popover appears to
/// drop away from the menu bar. This resizes the window to the measured content height
/// and keeps its top edge where it was.
extension View {
    func fitsMenuBarWindow() -> some View {
        modifier(WindowFitter())
    }
}

private struct WindowFitter: ViewModifier {
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                resize(to: height)
            }
            .background(WindowReader(window: $window))
            .frame(maxHeight: .infinity, alignment: .top)
            .onChange(of: window) { resize(to: nil) }
    }

    private func resize(to height: CGFloat?) {
        guard let window, let view = window.contentView else { return }
        let target = height ?? view.fittingSize.height
        guard target > 0 else { return }
        var frame = window.frame
        let contentHeight = window.contentRect(forFrameRect: frame).height
        let delta = target - contentHeight
        guard abs(delta) > 0.5 else { return }
        let top = frame.maxY
        frame.size.height += delta
        frame.origin.y = top - frame.size.height
        window.setFrame(frame, display: true, animate: false)
    }
}

private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if view.window !== window {
            DispatchQueue.main.async { window = view.window }
        }
    }
}
