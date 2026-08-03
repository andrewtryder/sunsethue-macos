import Foundation
import WidgetKit
import SunsetHueCore

enum WidgetReload {
    static func timelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: SunsetHueConstants.widgetKind)
    }
}
