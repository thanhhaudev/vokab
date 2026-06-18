import SwiftUI

/// Daily request-limit indicator with two separate faces:
/// • front — a usage ring with the used **percentage** in the centre,
/// • back  — the absolute **used/limit** count (text only).
/// Tapping flips (3D) between them. Ring fill + colour track usage.
struct DailyLimitRing: View {
    let used: Int
    let limit: Int
    let color: Color
    @State private var flipped = false

    private var frac: Double { limit > 0 ? min(1, max(0, Double(used) / Double(limit))) : 0 }
    private var pct: Int { Int((frac * 100).rounded()) }

    var body: some View {
        ZStack {
            // Front: ring + % inside.
            ZStack {
                Circle().stroke(Theme.borderTertiary, lineWidth: 2)
                Circle().trim(from: 0, to: frac)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(pct)%")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .frame(width: 16, height: 16)
            .opacity(flipped ? 0 : 1)

            // Back: the count, a separate face (pre-rotated so it reads correctly).
            Text("\(used)/\(limit)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(height: 16)
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.35)) { flipped.toggle() }
        }
        .help(L.t("Tap to flip · requests today vs warn threshold",
                  "Bấm để lật · request hôm nay so với ngưỡng cảnh báo"))
    }
}
