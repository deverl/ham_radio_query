import SwiftUI

/// Wraps subviews onto as many rows as the proposed width requires.
struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let rows = rows(for: subviews, maxWidth: maxWidth)
        let contentWidth = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? contentWidth, height: height(of: rows))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct Item {
        var subview: LayoutSubview
        var size: CGSize
    }

    private struct Row {
        var items: [Item]
        var width: CGFloat
        var height: CGFloat
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current: [Item] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        func closeRow() {
            guard !current.isEmpty else { return }
            rows.append(Row(items: current, width: rowWidth, height: rowHeight))
            current = []
            rowWidth = 0
            rowHeight = 0
        }

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !current.isEmpty, rowWidth + spacing + size.width > maxWidth {
                closeRow()
            }
            let gap: CGFloat = current.isEmpty ? 0 : spacing
            current.append(Item(subview: subview, size: size))
            rowWidth += gap + size.width
            rowHeight = max(rowHeight, size.height)
        }
        closeRow()
        return rows
    }

    private func height(of rows: [Row]) -> CGFloat {
        let content = rows.map(\.height).reduce(0, +)
        let gaps = rowSpacing * CGFloat(max(0, rows.count - 1))
        return content + gaps
    }
}
