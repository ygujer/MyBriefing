import SwiftUI

struct StripedBackground: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let step: CGFloat = 12
                for i in stride(from: -height, to: width, by: step) {
                    path.move(to: CGPoint(x: i, y: 0))
                    path.addLine(to: CGPoint(x: i + height, y: height))
                }
            }
            .stroke(Color.gray.opacity(0.15), lineWidth: 4)
        }
        .clipped()
    }
}
