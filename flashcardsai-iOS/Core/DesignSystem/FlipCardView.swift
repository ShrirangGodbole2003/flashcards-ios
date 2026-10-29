import SwiftUI

/// A card that flips around its vertical axis. Drive it with `isFlipped` and attach
/// an `.animation(_, value:)` from the parent.
///
/// While a finger drags the card, pass the live rotation as `dragAngle` (degrees, no
/// animation). When the drag ends, set `isFlipped` (and `flipDirection` = the sign of the
/// drag) and reset `dragAngle` to 0 inside one animation: the card glides on from where
/// the finger left it. `flipDirection` is -1 when the card was pulled leftwards so it keeps
/// turning the same way instead of unwinding first.
///
/// It conforms to `Animatable` so SwiftUI feeds it every intermediate angle; the face
/// switches at 90 degrees, where the card is edge-on and nothing is visible. The back
/// face is pre-rotated by 180 degrees so its content isn't mirrored.
struct FlipCardView<Front: View, Back: View>: View, Animatable {
    var angle: Double
    private let front: Front
    private let back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    init(isFlipped: Bool,
         flipDirection: Double = 1,
         dragAngle: Double = 0,
         @ViewBuilder front: () -> Front,
         @ViewBuilder back: () -> Back) {
        self.angle = isFlipped ? 180 * (flipDirection < 0 ? -1 : 1) : dragAngle
        self.front = front()
        self.back = back()
    }

    var body: some View {
        ZStack {
            if abs(angle) < 90 {
                front
            } else {
                back.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }
}
