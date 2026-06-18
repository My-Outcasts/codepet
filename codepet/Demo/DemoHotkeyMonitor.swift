import AppKit
import Combine

/// Listens for ⌥1..⌥8 and ⌥0 while the app is frontmost and DemoMode is on.
/// Routes the keys to `DemoScriptController`. Uses a local NSEvent monitor
/// so we don't grab keys when the app is in the background.
@MainActor
final class DemoHotkeyMonitor: ObservableObject {

    private weak var controller: DemoScriptController?
    private var monitor: Any?

    /// Called when ⌥9 is pressed. Set by CodePetApp to wire tipsState/petId.
    var onTipsDemo: (() -> Void)?

    func bind(controller: DemoScriptController) {
        self.controller = controller
    }

    /// Begin listening. Safe to call multiple times — second call is a no-op.
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Returns nil to swallow the event, or the original event to pass through.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.contains(.option) else { return event }
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1 else { return event }
        // ⌥+digit on US keyboards produces special chars (¡™£¢…) so we use
        // event.keyCode instead. Mapping:
        //   18=1, 19=2, 20=3, 21=4, 23=5, 22=6, 26=7, 28=8, 29=0
        let keyCode = event.keyCode
        switch keyCode {
        case 18: controller?.fireMilestone(index: 1); return nil
        case 19: controller?.fireMilestone(index: 2); return nil
        case 20: controller?.fireMilestone(index: 3); return nil
        case 21: controller?.fireMilestone(index: 4); return nil
        case 23: controller?.revealReflection();     return nil
        case 22: controller?.fireHealthStage(index: 1); return nil
        case 26: controller?.fireHealthStage(index: 2); return nil
        case 28: controller?.fireHealthStage(index: 3); return nil
        case 25: onTipsDemo?(); return nil                    // ⌥9 = Tips demo
        case 29: controller?.panicSkip(); return nil           // ⌥0 = panic skip
        default: return event
        }
    }
}
