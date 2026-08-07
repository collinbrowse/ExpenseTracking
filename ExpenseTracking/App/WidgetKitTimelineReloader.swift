import Foundation
import WidgetKit
import CashFlowKit

/// Production WidgetKit bridge — constructed only from `DependencyContainer`.
struct WidgetKitTimelineReloader: WidgetTimelineReloading {
    func reloadCashFlowWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetCashFlowTimeFrame.widgetKind)
    }
}
