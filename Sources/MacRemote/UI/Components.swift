import AppKit
import SwiftUI

// The app's page parts. They use only SwiftUI from macOS 12, so every page
// looks the same from macOS 12 to 26. (Grouped forms, LabeledContent, and
// ContentUnavailableView need macOS 13 or 14.)

/// A scrolling page of cards with the standard margins.
struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                content
            }
            .padding(Space.margin)
            .frame(maxWidth: Width.page, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// A titled group of rows on a rounded background, with an optional note below.
/// Put `CardDivider()` between rows.
struct Card<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let title {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, Space.xs)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, Space.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            if let footer {
                Text(footer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xs)
            }
        }
    }
}

struct CardDivider: View {
    var body: some View { Divider() }
}

/// One row: an optional symbol, a title with an optional second line, and
/// a control or value on the trailing side.
struct Row<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var symbol: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.md) {
            if let symbol {
                Image(systemName: Symbol.named(symbol))
                    .frame(width: Space.xl)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.md)
            trailing
        }
        .padding(.vertical, Space.sm)
        .frame(minHeight: Space.section + Space.xs)
    }
}

extension Row where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, symbol: String? = nil) {
        self.init(title: title, subtitle: subtitle, symbol: symbol) { EmptyView() }
    }
}

/// An empty page: a symbol, a title, and what to do next.
struct EmptyState: View {
    var title: String
    var symbol: String
    var message: String

    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: Symbol.named(symbol))
                .font(.system(size: Space.section + Space.lg))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Width.settings)
        }
        .padding(Space.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// SF Symbols with a fallback, for symbols that are newer than macOS 12.
enum Symbol {
    private static let fallbacks: [String: String] = [
        "av.remote": "appletvremote.gen4",
        "av.remote.fill": "appletvremote.gen4.fill",
        "appletvremote.gen4": "rectangle.portrait",
        "appletvremote.gen4.fill": "rectangle.portrait.fill",
    ]
    private static var cache: [String: String] = [:]

    static func named(_ name: String) -> String {
        if let known = cache[name] { return known }
        var candidate = name
        while NSImage(systemSymbolName: candidate, accessibilityDescription: nil) == nil {
            guard let next = fallbacks[candidate] else {
                candidate = "circle"
                break
            }
            candidate = next
        }
        cache[name] = candidate
        return candidate
    }
}
