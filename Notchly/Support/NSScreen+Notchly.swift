import AppKit
import SwiftUI
import Combine

extension NSScreen {
    var notchlyDisplayID: Int? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue
    }

    var notchlyName: String {
        localizedName
    }
}
