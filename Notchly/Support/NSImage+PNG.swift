import AppKit
import Combine
import CryptoKit

extension NSImage {
    func notchlyPNGData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
