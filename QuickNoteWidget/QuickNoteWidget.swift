import WidgetKit
import SwiftUI

// MARK: - Timeline

struct PinnedNotesEntry: TimelineEntry {
    let date: Date
    let notes: [PinnedNoteSnapshot]
}

struct PinnedNotesProvider: TimelineProvider {
    func placeholder(in context: Context) -> PinnedNotesEntry {
        PinnedNotesEntry(date: Date(), notes: Self.sampleNotes)
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedNotesEntry) -> Void) {
        let notes = context.isPreview ? Self.sampleNotes : SharedStore.loadPinned()
        completion(PinnedNotesEntry(date: Date(), notes: notes))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedNotesEntry>) -> Void) {
        let entry = PinnedNotesEntry(date: Date(), notes: SharedStore.loadPinned())
        // The app pushes reloads via WidgetCenter whenever pinned notes change;
        // this hourly refresh is just a safety net if that ever gets missed.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    static let sampleNotes: [PinnedNoteSnapshot] = [
        PinnedNoteSnapshot(id: UUID(), content: "Call the pharmacy\nrefill before Friday", updatedAt: Date()),
        PinnedNoteSnapshot(id: UUID(), content: "Wifi password\nhunter2-guest", updatedAt: Date()),
        PinnedNoteSnapshot(id: UUID(), content: "Book flights for August", updatedAt: Date())
    ]
}

// MARK: - Widget

struct PinnedNotesWidget: Widget {
    private let kind = "PinnedNotesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinnedNotesProvider()) { entry in
            PinnedNotesWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Pinned Notes")
        .description("Your pinned QuickNotes, always a glance away.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // Take over the insets ourselves — the default content margins left the
        // "Pinned" header crowding the top edge on some devices.
        .contentMarginsDisabled()
    }
}

// MARK: - Views

struct PinnedNotesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PinnedNotesEntry

    private var visibleCount: Int {
        switch family {
        case .systemSmall:  return 2
        case .systemMedium: return 3
        default:            return 7
        }
    }

    var body: some View {
        Group {
            if entry.notes.isEmpty {
                EmptyStateView()
            } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
                    header
                    ForEach(entry.notes.prefix(visibleCount)) { note in
                        NoteRow(note: note, compact: family == .systemSmall)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        // Explicit insets now that default content margins are disabled, so the
        // header always has breathing room from the widget's edges.
        .padding(family == .systemSmall ? 14 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Small widgets can't host per-row links, so the whole tile opens the
        // top pinned note. Medium/large use per-row `Link`s instead.
        .modifier(SmallWidgetLink(url: family == .systemSmall ? topNoteURL : nil))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Brand.accent)
            Text("Pinned")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.accent)
            Spacer(minLength: 0)
            if entry.notes.count > visibleCount {
                Text("+\(entry.notes.count - visibleCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One pinned note. On medium/large each row deep-links to its own note; on the
/// small family the whole widget links to the top note (rows can't each be a
/// separate tap target there), handled by `widgetURL` below.
private struct NoteRow: View {
    let note: PinnedNoteSnapshot
    let compact: Bool

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
                .font(.system(size: compact ? 13 : 14, weight: .medium))
                .foregroundStyle(Brand.title)
                .lineLimit(1)
            if !compact, !note.preview.isEmpty {
                Text(note.preview)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if compact {
            content
        } else if let url = SharedStore.deepLinkURL(for: note.id) {
            Link(destination: url) { content }
        } else {
            content
        }
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "pin.slash")
                .font(.system(size: 26))
                .foregroundStyle(Brand.accent.opacity(0.7))
            Text("No pinned notes")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.title)
            Text("Pin a note to see it here")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Styling

/// The app is locked to a light look; the widget mirrors that with an explicit
/// near-white background and the same indigo/purple brand accent.
private struct WidgetBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.white, Color(red: 0.93, green: 0.93, blue: 0.99)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private enum Brand {
    static let accent = Color.indigo
    static let title = Color.black.opacity(0.85)
}

/// Applies `widgetURL` only when a URL is provided (small family). A no-op
/// otherwise, so medium/large keep their per-row links.
private struct SmallWidgetLink: ViewModifier {
    let url: URL?
    func body(content: Content) -> some View {
        if let url {
            content.widgetURL(url)
        } else {
            content
        }
    }
}

// MARK: - Deep link (small family)

extension PinnedNotesWidgetView {
    /// Links the whole small widget to its top pinned note.
    var topNoteURL: URL? {
        entry.notes.first.flatMap { SharedStore.deepLinkURL(for: $0.id) }
    }
}

#Preview(as: .systemMedium) {
    PinnedNotesWidget()
} timeline: {
    PinnedNotesEntry(date: .now, notes: PinnedNotesProvider.sampleNotes)
    PinnedNotesEntry(date: .now, notes: [])
}
