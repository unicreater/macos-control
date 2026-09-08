import Foundation

/// Global landscape rotation angle. Read from UserDefaults so any view can access it.
enum LandscapeDirection {
    private static let key = "com.noso.nosodeck.landscapeAngle"

    static var angle: Double {
        (UserDefaults.standard.object(forKey: key) as? Double) ?? -90
    }
}
