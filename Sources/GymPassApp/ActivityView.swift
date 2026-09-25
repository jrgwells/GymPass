import SwiftUI
import GymPassShared

struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if model.activity.isEmpty {
                ContentUnavailableView("No activity yet", systemImage: "clock.arrow.circlepath", description: Text("GymPass will record refresh, pass and notification events here."))
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.events) { event in
                        ActivityRow(event: event)
                    }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Activity")
    }

    private struct Group: Identifiable {
        let id: String
        let title: String
        let events: [ActivityEvent]
    }

    private var groups: [Group] {
        let calendar = Calendar.current
        let now = Date()
        var today: [ActivityEvent] = []
        var yesterday: [ActivityEvent] = []
        var earlier: [ActivityEvent] = []
        for event in model.activity {
            if calendar.isDateInToday(event.occurredAt) {
                today.append(event)
            } else if calendar.isDateInYesterday(event.occurredAt) {
                yesterday.append(event)
            } else {
                earlier.append(event)
            }
        }
        _ = now
        var result: [Group] = []
        if !today.isEmpty { result.append(Group(id: "today", title: "Today", events: today)) }
        if !yesterday.isEmpty { result.append(Group(id: "yesterday", title: "Yesterday", events: yesterday)) }
        if !earlier.isEmpty { result.append(Group(id: "earlier", title: "Earlier", events: earlier)) }
        return result
    }
}

struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Text(event.occurredAt.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)

            Image(systemName: event.kind.symbolName)
                .foregroundStyle(event.kind.isProblem ? .orange : Theme.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.medium))
                if let detail = event.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Copy Details") {
                var text = "\(event.occurredAt.formatted())\n\(event.title)"
                if let detail = event.detail { text += "\n\(detail)" }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
}
