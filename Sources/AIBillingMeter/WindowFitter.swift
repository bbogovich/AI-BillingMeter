import SwiftUI

/// Reports the usage panel's content height so `StatusBarController` can size the panel to it.
///
/// The controller owns the panel's frame: it keeps the top edge under the menu bar and uses the
/// last reported height both when the panel opens and whenever the content changes (a tab switch).
/// The view never resizes its window itself; two owners of one frame fought each other before.
extension View {
    func fitsMenuBarWindow() -> some View {
        modifier(WindowFitter())
    }
}

private struct WindowFitter: ViewModifier {
    @Environment(\.contentHeightChanged) private var report

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { report($0) }
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Receives the panel content's measured height. Injected by `StatusBarController`.
struct ContentHeightAction {
    let action: (CGFloat) -> Void
    init(_ action: @escaping (CGFloat) -> Void = { _ in }) { self.action = action }
    func callAsFunction(_ height: CGFloat) { action(height) }
}

private struct ContentHeightKey: EnvironmentKey {
    static let defaultValue = ContentHeightAction()
}

extension EnvironmentValues {
    var contentHeightChanged: ContentHeightAction {
        get { self[ContentHeightKey.self] }
        set { self[ContentHeightKey.self] = newValue }
    }
}
