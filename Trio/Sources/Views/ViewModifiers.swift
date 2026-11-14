import Combine
import SwiftUI

struct RoundedBackground: ViewModifier {
    private let color: Color

    init(color: Color = Color("CapsuleColor")) {
        self.color = color
    }

    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill()
                    .foregroundColor(color)
            )
    }
}

struct CapsulaBackground: ViewModifier {
    private let color: Color

    init(color: Color = Color("CapsuleColor")) {
        self.color = color
    }

    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                Capsule()
                    .fill()
                    .foregroundColor(color)
            )
    }
}

private let navigationCache = LRUCache<Screen.ID, AnyView>(capacity: 10)

struct NavigationLazyView: View {
    let build: () -> AnyView
    let screen: Screen

    init(_ build: @autoclosure @escaping () -> AnyView, screen: Screen) {
        self.build = build
        self.screen = screen
    }

    var body: AnyView {
        if navigationCache[screen.id] == nil {
            navigationCache[screen.id] = build()
        }
        return navigationCache[screen.id]!
            .onDisappear {
                navigationCache[screen.id] = nil
            }.asAny()
    }
}

struct Link: ViewModifier {
    let screen: Screen

    init(screen: Screen) {
        self.screen = screen
    }

    func body(content: Content) -> some View {
        NavigationLink(value: screen, label: { content })
    }
}

struct ScreenNavigation<T>: ViewModifier where T: View {
    private let destination: (Screen) -> T

    init(destination: @escaping (Screen) -> T) {
        self.destination = destination
    }

    func body(content: Content) -> some View {
        content.navigationDestination(
            for: Screen.self,
            destination: { screen in NavigationLazyView(destination(screen).asAny(), screen: screen) }
        )
    }
}

struct AdaptsToSoftwareKeyboard: ViewModifier {
    @State var currentHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, currentHeight).animation(.easeOut(duration: 0.25))
            .edgesIgnoringSafeArea(currentHeight == 0 ? Edge.Set() : .bottom)
            .onAppear(perform: subscribeToKeyboardChanges)
    }

    private let keyboardHeightOnOpening = Foundation.NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillShowNotification)
        .map { $0.userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! CGRect }
        .map(\.height)

    private let keyboardHeightOnHiding = Foundation.NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillHideNotification)
        .map { _ in CGFloat(0) }

    private func subscribeToKeyboardChanges() {
        _ = Publishers.Merge(keyboardHeightOnOpening, keyboardHeightOnHiding)
            .subscribe(on: DispatchQueue.main)
            .sink { height in
                if self.currentHeight == 0 || height == 0 {
                    self.currentHeight = height
                }
            }
    }
}

struct ClearButton: ViewModifier {
    @Binding var text: String
    func body(content: Content) -> some View {
        HStack {
            content
            if !text.isEmpty {
                Button { self.text = "" }
                label: {
                    Image(systemName: "delete.left")
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

extension View {
    func roundedBackground() -> some View {
        modifier(RoundedBackground())
    }

    func buttonBackground() -> some View {
        modifier(RoundedBackground(color: .accentColor))
    }

    func navigationLink<V: BaseView>(to screen: Screen, from _: V) -> some View {
        modifier(Link(screen: screen))
    }

    func screenNavigation<V: BaseView>(_ view: V) -> some View {
        modifier(ScreenNavigation { screen in
            view.state.view(for: screen)
        })
    }

    func adaptsToSoftwareKeyboard() -> some View {
        modifier(AdaptsToSoftwareKeyboard())
    }

    func modal<V: BaseView>(for screen: Screen?, from view: V) -> some View {
        onTapGesture {
            view.state.showModal(for: screen)
        }
    }

    func asAny() -> AnyView { .init(self) }

    var backport: Backport<Self> { Backport(content: self) }
}

struct Backport<Content: View> {
    let content: Content
}

// MARK: - Sheet list top inset

/// Before iOS 27, Treatments and the override and temp target forms let their list run up under the sheet's
/// navigation bar, starting just below a top padding, to save space on small screens. iOS 27's navigation bar,
/// with its glass buttons, is taller than that padding plus the list's top margin, so the first row was hidden
/// under the bar and the bar drew its scroll-edge background. On iOS 27 the list keeps the safe area and starts
/// below the bar, like Add Glucose.
struct SheetListTopInset: ViewModifier {
    /// The top padding used before iOS 27, while the list runs under the bar.
    let legacyTopPadding: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content
        } else {
            content
                .padding(.top, legacyTopPadding)
                .ignoresSafeArea(edges: .top)
        }
    }
}

extension View {
    /// Places a sheet's list relative to its navigation bar; see `SheetListTopInset`.
    func sheetListTopInset(legacyTopPadding: CGFloat) -> some View {
        modifier(SheetListTopInset(legacyTopPadding: legacyTopPadding))
    }
}

/// The top content margin for those sheets' lists. iOS's default on iPhone is 35 pt (iPhone Duo defaults to 0,
/// which put the first row under the sheet's bar). On iOS 27, where the list starts below the bar, 35 pt left a
/// 44.5 pt gap under the bar's buttons; 6.5 pt makes it 16 pt, the same as the cards' side margins.
var sheetListTopMargin: CGFloat {
    if #available(iOS 27.0, *) {
        return 6.5
    }
    return 35
}
