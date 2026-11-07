import MacRemoteKit
import SwiftUI

/// The on-screen keyboard's keys, the highlighted one in the accent color,
/// with a line saying which remote button does what.
struct KeyboardView: View {
    @ObservedObject var controller: KeyboardController

    var body: some View {
        let keyboard = controller.keyboard
        VStack(spacing: Space.md) {
            VStack(spacing: Space.xs) {
                ForEach(Array(keyboard.rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: Space.xs) {
                        ForEach(Array(row.enumerated()), id: \.element.id) { column, key in
                            KeyCap(label: keyboard.label(for: key), symbol: symbol(for: key, in: keyboard),
                                   width: key.width,
                                   focused: rowIndex == keyboard.row && column == keyboard.column)
                                .onTapGesture { controller.tap(row: rowIndex, column: column) }
                        }
                    }
                }
            }
            Text("Select types  ·  Rewind deletes  ·  Fast Forward adds a space  ·  Back closes")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(Space.lg)
        .modifier(KeyboardBackground())
        .padding(Space.xl)
    }

    private func symbol(for key: KeyboardKey, in keyboard: OnScreenKeyboard) -> String? {
        switch key.kind {
        case .shift:
            switch keyboard.shift {
            case .off: "shift"
            case .once: "shift.fill"
            case .locked: "capslock.fill"
            }
        case .delete: "delete.left"
        case .returnKey: "return"
        case .hide: "keyboard.chevron.compact.down"
        case .character, .layer, .space: nil
        }
    }
}

private struct KeyCap: View {
    let label: String
    let symbol: String?
    let width: Int
    let focused: Bool

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: Symbol.named(symbol))
                    .accessibilityLabel(label)
            } else {
                Text(label)
            }
        }
        .font(.title3.weight(focused ? .semibold : .regular))
        .foregroundColor(focused ? .white : .primary)
        .frame(width: Width.key * CGFloat(width) + Space.xs * CGFloat(width - 1), height: Width.key)
        .background(
            RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                .fill(focused ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .scaleEffect(focused ? 1.06 : 1)
        .animation(.easeOut(duration: 0.08), value: focused)
        .contentShape(Rectangle())
    }
}

/// Liquid Glass on macOS 26, a HUD material before it.
private struct KeyboardBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: Radius.panel))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        }
    }
}
