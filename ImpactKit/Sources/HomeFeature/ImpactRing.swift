import SwiftUI

/// Today's Impacts: one segment per chance, filled per Impact (UX.md → Home).
struct ImpactRing: View {
    let filled: Int
    let segments: Int
    var lineWidth: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height) - lineWidth
            // Round caps reach past each segment's end, so the gap covers a line width; on busy days
            // it shrinks to at most half a segment so every segment stays visible.
            let gap = segments > 1 ? min((lineWidth + 3) / (.pi * diameter), 0.5 / Double(segments)) : 0
            ZStack {
                if segments == 0 {
                    Circle().stroke(.quaternary, lineWidth: lineWidth)
                }
                ForEach(0..<segments, id: \.self) { index in
                    Circle()
                        .trim(from: Double(index) / Double(segments) + gap / 2,
                              to: Double(index + 1) / Double(segments) - gap / 2)
                        .stroke(index < filled ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: diameter, height: diameter)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .overlay {
            Text(filled, format: .number)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filled) \(filled == 1 ? "Impact" : "Impacts") today")
    }
}
