import Foundation
import WidgetKit
import SunsetHueCore

enum WidgetReload {
    static func timelines() {
        WidgetReloadStateTracker.shared.recordReloadRequest()
        WidgetCenter.shared.reloadTimelines(ofKind: SunsetHueConstants.widgetKind)
    }
}
