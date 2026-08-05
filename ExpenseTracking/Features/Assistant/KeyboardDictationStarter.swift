import UIKit

/// Best-effort trigger for system keyboard dictation after a text field is focused.
enum KeyboardDictationStarter {
    /// Call after making the composer first responder so the software keyboard is up.
    static func start() {
        UITextInputContext.current()?.isDictationInputExpected = true
        // Keyboard presentation is async; dictation targets the current first responder.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let selector = Selector(("startDictation:"))
            UIApplication.shared.sendAction(selector, to: nil, from: nil, for: nil)
        }
    }
}
