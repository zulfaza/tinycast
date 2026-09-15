import SwiftUI

struct SnippetsList: View {

    @Environment(\.metrics) private var metrics
    let results: [StoredSnippet]
    let usage: SnippetUsageStore
    let selectedID: StoredSnippet.ID?
    let scroll: ScrollIntent
    let onSelect: (StoredSnippet) -> Void
    let onActivate: () -> Void
    let onActions: (StoredSnippet) -> Void

    private struct Section: Identifiable {
        let group: SnippetUsageGroup
        let records: [StoredSnippet]
        var id: SnippetUsageGroup { group }
    }

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    private var sections: [Section] {
        let grouped = Dictionary(grouping: results) { usage.group(for: $0.id) }
        return SnippetUsageGroup.allCases.compactMap { group in
            guard let records = grouped[group], !records.isEmpty else { return nil }
            return Section(group: group, records: records)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sections) { section in
                        Text(section.group.title)
                            .font(metrics.typography.sectionHeader)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, metrics.spacing.md)
                            .padding(
                                .top,
                                section.id == sections.first?.id
                                    ? metrics.spacing.xs : metrics.spacing.lg)
                            .padding(.bottom, metrics.spacing.xs)
                        ForEach(section.records) { record in
                            SnippetRow(record: record, selected: record.id == selectedID)
                                .selectionFrame(record.id == selectedID)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(record) }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        onSelect(record)
                                        onActivate()
                                    }
                                )
                                .onRightClick { onActions(record) }
                        }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

private struct SnippetRow: View {

    @Environment(\.metrics) private var metrics
    let record: StoredSnippet
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous)
                .fill(Theme.Colors.controlSurface)
                .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary))
            Text(record.snippet.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: metrics.spacing.lg)
            if let keyword = record.snippet.keyword, !keyword.isEmpty {
                Text(keyword)
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
    }
}

struct SnippetPreview: View {
    @Environment(\.metrics) private var metrics
    let record: StoredSnippet?
    let usage: SnippetUsageStore

    var body: some View {
        if let record {
            VStack(alignment: .leading, spacing: 0) {
                // The raw template: expanding here would read the clipboard on every arrow key.
                ScrollView {
                    Text(record.snippet.text)
                        .font(metrics.typography.rowTitle)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                SnippetInfoSection(record: record, usage: usage)
            }
            .padding(.horizontal, 12)
        } else {
            Color.clear
        }
    }
}

/// The "Information" block; everything in it is already in memory, so nothing is gathered off-main.
private struct SnippetInfoSection: View {
    @Environment(\.metrics) private var metrics
    let record: StoredSnippet
    let usage: SnippetUsageStore

    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private var rows: [InfoRow] {
        var rows = [
            InfoRow(label: "Name", value: record.snippet.name),
            InfoRow(label: "Content Type", value: "Text"),
            InfoRow(label: "Times Copied", value: usage.records[record.id]?.count.formatted() ?? "0")
        ]
        if let lastUsed = usage.lastUsed(for: record.id) {
            rows.append(InfoRow(label: "Last Copied", value: Self.dateFormatter.string(from: lastUsed)))
        }
        return rows
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text("Information")
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: metrics.spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: metrics.spacing.lg)
                        Text(row.value).lineLimit(1).truncationMode(.middle)
                    }
                    .font(metrics.typography.keyCap)
                    .padding(.horizontal, metrics.spacing.md)
                    .padding(.vertical, metrics.spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                            .fill(index.isMultiple(of: 2) ? Theme.Colors.cardFill : .clear))
                }
            }
        }
        .padding(.vertical, metrics.spacing.md)
    }
}
