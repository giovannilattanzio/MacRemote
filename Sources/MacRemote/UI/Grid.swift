import SwiftUI

/// The spacing scale. Every padding, spacing, and size sits on a 4 pt grid
/// (tools/grid-lint.sh checks the numbers in views).
enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let section: CGFloat = 32
    /// Window and page margins.
    static let margin: CGFloat = 20
}

/// Corner radii.
enum Radius {
    static let card: CGFloat = 10
    /// On-screen keyboard keys.
    static let key: CGFloat = 8
    /// The on-screen keyboard's panel.
    static let panel: CGFloat = 20
}

/// Widths.
enum Width {
    /// Pages stop growing here, so lines stay readable in a wide window.
    static let page: CGFloat = 720
    static let settings: CGFloat = 480
    static let sidebar: CGFloat = 200
    /// The remote drawing on the Remote page, and its thumbnail in Devices.
    static let remotePicture: CGFloat = 72
    static let remoteThumbnail: CGFloat = 16
    /// One unit of the on-screen keyboard: a letter key is this wide and tall.
    static let key: CGFloat = 48
}
