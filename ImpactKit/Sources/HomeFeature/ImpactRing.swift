import SwiftUI

/// Today's Impacts: one segment per chance, filled per Impact (UX.md → Home).
struct ImpactRing: View {
    let filled: Int
    let segments: Int
    var lineWidth: CGFloat = 5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height) - lineWidth
            // Round caps reach past each segment's end, so the gap covers a line width. On very busy
            // days the gap is capped below a segment's length, so each segment still draws as a dot.
            let gap = segments > 1 ? min((lineWidth + 3) / (.pi * diameter), 1 / Double(segments) - 0.001) : 0
            ZStack {
                if segments == 0 {
                    Circle().stroke(.quaternary, lineWidth: lineWidth)
                }
                ForEach(0..<segments, id: \.self) { index in
                    let start = Double(index) / Double(segments) + gap / 2
                    let end = Double(index + 1) / Double(segments) - gap / 2
                    let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    Circle().trim(from: start, to: end).stroke(.quaternary, style: style)
                    // A new Impact sweeps its segment in; Reduce Motion fades it in instead.
                    Circle().trim(from: start, to: index < filled || reduceMotion ? end : start)
                        .stroke(.tint, style: style)
                        .opacity(index < filled ? 1 : 0)
                }
                .rotationEffect(.degrees(-90))
            }
            .frame(width: diameter, height: diameter)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .overlay {
            Text(filled, format: .number)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(filled)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filled) \(filled == 1 ? "Impact" : "Impacts") today")
    }
}

#if DEBUG
#Preview("Busy day") { ImpactRing(filled: 6, segments: 20).frame(width: 46, height: 46).padding() }
#endif
