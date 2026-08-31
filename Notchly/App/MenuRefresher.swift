import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuRefresher: NSObject, NSMenuDelegate {
    static let shared = MenuRefresher()
    var onOpen: ((NSMenu) -> Void)?
    func menuWillOpen(_ menu: NSMenu) { onOpen?(menu) }
}
