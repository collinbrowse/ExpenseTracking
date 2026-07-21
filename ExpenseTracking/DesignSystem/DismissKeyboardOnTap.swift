import SwiftUI
import UIKit

extension View {
    /// Dismisses the keyboard when tapping empty space.
    /// Taps on controls, text fields, and other interactive views are left alone.
    func dismissKeyboardOnEmptyTap() -> some View {
        background(DismissKeyboardOnEmptyTapInstaller())
    }
}

private struct DismissKeyboardOnEmptyTapInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        context.coordinator.hostView = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.installIfNeeded()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var hostView: UIView?
        private var recognizer: UITapGestureRecognizer?
        private weak var installedWindow: UIWindow?

        func installIfNeeded() {
            guard recognizer == nil else { return }
            // Window is available after the representable joins the hierarchy.
            DispatchQueue.main.async { [weak self] in
                self?.attachToWindow()
            }
        }

        private func attachToWindow() {
            guard recognizer == nil, let window = hostView?.window else { return }

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            recognizer = tap
            installedWindow = window
        }

        func uninstall() {
            if let recognizer, let window = installedWindow {
                window.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            installedWindow = nil
        }

        @objc private func handleTap() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            var view = touch.view
            while let current = view {
                if Self.isInteractive(current) {
                    return false
                }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private static func isInteractive(_ view: UIView) -> Bool {
            if view is UIControl { return true }
            if view is UITextField { return true }
            if view is UITextView { return true }
            if view is UISearchBar { return true }

            let className = String(describing: type(of: view))
            if className.contains("Button") { return true }
            if className.contains("Switch") { return true }
            if className.contains("Slider") { return true }
            if className.contains("Stepper") { return true }
            if className.contains("Picker") { return true }
            if className.contains("TextField") { return true }
            if className.contains("TextEditor") { return true }
            if className.contains("Menu") { return true }
            return false
        }
    }
}
