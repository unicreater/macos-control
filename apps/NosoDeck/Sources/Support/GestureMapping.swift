import DeckKit
import Foundation

/// Maps 2-finger gesture directions to actions.
struct GestureMapping: Codable {
    var swipeUp: ActionKind
    var swipeDown: ActionKind
    var swipeLeft: ActionKind
    var swipeRight: ActionKind
    var doubleTap: ActionKind
    var longPress: ActionKind

    static let `default` = GestureMapping(
        swipeUp: .maximizeWindow,
        swipeDown: .minimizeWindow,
        swipeLeft: .copyClipboard,
        swipeRight: .pasteClipboard,
        doubleTap: .copyClipboard,
        longPress: .pasteClipboard
    )

    /// All gesture slots with labels for the settings UI.
    static let slots: [(key: WritableKeyPath<GestureMapping, ActionKind>, label: String, icon: String)] = [
        (\.swipeUp, "2-finger swipe up", "hand.point.up"),
        (\.swipeDown, "2-finger swipe down", "hand.point.down"),
        (\.swipeLeft, "2-finger swipe left", "hand.point.left"),
        (\.swipeRight, "2-finger swipe right", "hand.point.right"),
        (\.doubleTap, "2-finger double tap", "hand.tap"),
        (\.longPress, "2-finger long press", "hand.raised"),
    ]

    /// Actions available for gesture mapping.
    static let availableActions: [(action: ActionKind, label: String)] = [
        (.maximizeWindow, "Maximize"),
        (.minimizeWindow, "Minimize"),
        (.copyClipboard, "Copy"),
        (.pasteClipboard, "Paste"),
        (.mediaPlayPause, "Play / Pause"),
        (.volumeMute, "Mute"),
        (.volumeUp, "Volume Up"),
        (.volumeDown, "Volume Down"),
        (.goBack, "Back"),
        (.goForward, "Forward"),
        (.refreshPage, "Refresh"),
        (.closeTab, "Close Tab"),
        (.newTab, "New Tab"),
        (.scrollUp, "Scroll Up"),
        (.scrollDown, "Scroll Down"),
    ]

    /// Human-readable label for an action.
    static func label(for action: ActionKind) -> String {
        availableActions.first { $0.action == action }?.label ?? action.rawValue
    }

    /// SF Symbol icon for an action.
    static func icon(for action: ActionKind) -> String {
        switch action {
        case .maximizeWindow: return "arrow.up.left.and.arrow.down.right"
        case .minimizeWindow: return "arrow.down.right.and.arrow.up.left"
        case .copyClipboard: return "doc.on.doc"
        case .pasteClipboard: return "doc.on.clipboard"
        case .mediaPlayPause: return "playpause"
        case .volumeMute: return "speaker.slash"
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        case .goBack: return "chevron.left"
        case .goForward: return "chevron.right"
        case .refreshPage: return "arrow.clockwise"
        case .closeTab: return "xmark"
        case .newTab: return "plus"
        case .scrollUp: return "chevron.up"
        case .scrollDown: return "chevron.down"
        default: return "questionmark"
        }
    }
}
