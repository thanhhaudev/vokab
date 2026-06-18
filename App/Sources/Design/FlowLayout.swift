import SwiftUI

/// A simple wrapping layout (left-aligned rows) for chips and tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.last.map { $0.y + $0.rowHeight } ?? 0
        let width = rows.map { $0.maxX }.max() ?? 0
        rows.removeAll()
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        for row in rows {
            for item in row.items {
                // Center each item vertically within its row so mixed-height
                // items (text + padded chips + buttons) share a visual midline.
                let dy = (row.rowHeight - item.size.height) / 2
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y + dy),
                    proposal: ProposedViewSize(item.size))
            }
        }
    }

    private struct RowItem { let index: Int; let x: CGFloat; let size: CGSize }
    private struct Row { var items: [RowItem] = []; var y: CGFloat = 0; var rowHeight: CGFloat = 0
        var maxX: CGFloat { (items.last.map { $0.x + $0.size.width }) ?? 0 } }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !current.items.isEmpty {
                rows.append(current)
                let y = current.y + current.rowHeight + lineSpacing
                current = Row(items: [], y: y, rowHeight: 0)
                x = 0
            }
            current.items.append(RowItem(index: index, x: x, size: size))
            current.rowHeight = max(current.rowHeight, size.height)
            x += size.width + spacing
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
