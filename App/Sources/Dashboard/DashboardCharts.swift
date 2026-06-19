import SwiftUI

/// Small, dependency-free chart primitives for the Dashboard, styled with `Theme`
/// tokens so they read as part of the same app as the Library.

/// Proportional bar height: scales `value` to `[minH, maxH]` against `max`.
/// Zero-safe (max == 0 → flat baseline at `minH`).
private func barHeight(_ value: Int, max maxValue: Int, minH: CGFloat, maxH: CGFloat) -> CGFloat {
    guard maxValue > 0, value > 0 else { return minH }
    let frac = CGFloat(value) / CGFloat(maxValue)
    return minH + frac * (maxH - minH)
}

/// A card showing a big value (or a ring) above a small caption — matches the
/// Library statcard chrome (bgSecondary, radiusMd, hairline border).
struct StatTile: View {
    let value: String
    let label: String
    var accent: Color = Theme.accent
    /// When set, shows a `DailyLimitRing`-style donut at `0...1` instead of `value`.
    var ring: Double? = nil
    /// Used + limit when a ring is shown (drives the ring's % / count faces).
    var ringUsed: Int = 0
    var ringLimit: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if ring != nil {
                HStack(spacing: 6) {
                    DailyLimitRing(used: ringUsed, limit: ringLimit, color: accent)
                    Text(value)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            } else {
                Text(value)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .frame(minWidth: 104, alignment: .leading)
        .padding(12)
        .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd)
            .strokeBorder(Theme.borderTertiary, lineWidth: Theme.hairline))
    }
}

/// A horizontal row of thin proportional bars (e.g. a 56-day activity strip).
struct BarRow: View {
    let values: [Int]
    var color: Color = Theme.accent

    var body: some View {
        let maxV = values.max() ?? 0
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(values.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(values[i] > 0 ? color : Theme.borderTertiary)
                        .frame(height: barHeight(values[i], max: maxV, minH: 2, maxH: geo.size.height))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 44)
    }
}

/// 14 forecast bars with a sparse `+N` caption under a few columns.
struct ForecastBars: View {
    let values: [Int]

    var body: some View {
        let maxV = values.max() ?? 0
        VStack(spacing: 4) {
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(values.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(values[i] > 0 ? Theme.accent : Theme.borderTertiary)
                            .frame(height: barHeight(values[i], max: maxV, minH: 2, maxH: geo.size.height))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 56)
            HStack(spacing: 3) {
                ForEach(values.indices, id: \.self) { i in
                    Text(i % 2 == 0 ? "+\(i)" : "")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// A vertical list of labeled horizontal bars: label left, proportional fill,
/// count right (e.g. CEFR / language / category composition).
struct CompositionBars: View {
    let rows: [(label: String, count: Int, color: Color)]

    var body: some View {
        let maxV = rows.map(\.count).max() ?? 0
        VStack(alignment: .leading, spacing: 7) {
            ForEach(rows.indices, id: \.self) { i in
                let row = rows[i]
                HStack(spacing: 8) {
                    Text(row.label)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 56, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.borderTertiary).frame(height: 6)
                            Capsule().fill(row.color)
                                .frame(width: geo.size.width * fraction(row.count, max: maxV), height: 6)
                        }
                    }
                    .frame(height: 6)
                    Text("\(row.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    private func fraction(_ value: Int, max maxValue: Int) -> CGFloat {
        guard maxValue > 0, value > 0 else { return 0 }
        return CGFloat(value) / CGFloat(maxValue)
    }
}
