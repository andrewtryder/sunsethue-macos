import Foundation
import SunsetHueCore
import WidgetKit

enum WidgetReload {
    static func timelines() {
        WidgetReloadStateTracker.shared.recordReloadRequest()
        WidgetCenter.shared.reloadTimelines(ofKind: SunsetHueConstants.widgetKind)
    }
}
