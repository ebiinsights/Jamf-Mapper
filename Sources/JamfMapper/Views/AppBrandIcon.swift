import AppKit
import SwiftUI

struct AppBrandIcon: View {
    private static let icon = AppIconFactory.makeIcon(size: 512)

    var body: some View {
        Image(nsImage: Self.icon)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .accessibilityLabel("Jamf Mapper")
        .aspectRatio(1, contentMode: .fit)
    }
}
