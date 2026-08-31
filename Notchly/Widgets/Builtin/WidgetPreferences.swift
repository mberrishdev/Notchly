import Foundation
import SwiftUI

@MainActor
struct WidgetPreferences {
    let widgetID: String
    let environment: AppEnvironment

    func bool(_ key: String, default fallback: Bool) -> Bool {
        environment.widgetSetting(key: key, widgetID: widgetID)?.boolValue ?? fallback
    }
    func string(_ key: String, default fallback: String) -> String {
        environment.widgetSetting(key: key, widgetID: widgetID)?.stringValue ?? fallback
    }
    func number(_ key: String, default fallback: Double) -> Double {
        environment.widgetSetting(key: key, widgetID: widgetID)?.doubleValue ?? fallback
    }
    func int(_ key: String, default fallback: Int) -> Int {
        Int(number(key, default: Double(fallback)))
    }
}
