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
}

/// Widths.
enum Width {
    /// Pages stop growing here, so lines stay readable in a wide window.
    static let page: CGFloat = 720
    static let settings: CGFloat = 480
    static let sidebar: CGFloat = 200
}
