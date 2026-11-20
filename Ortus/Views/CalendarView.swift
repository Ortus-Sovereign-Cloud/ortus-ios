import OrtusKit
import SwiftUI

/// MobileCalendar: the week as a strip of days, the chosen day's events
/// in time order with now marked, invitations to answer.
struct CalendarView: View {
    @EnvironmentObject var model: AppModel
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var events: [Event] = []

    private var week: [Date] {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(day.formatted(.dateTime.month(.wide).year())).font(.subheadline).foregroundStyle(Theme.text2)
                    Text(day.formatted(.dateTime.weekday(.wide))).font(.largeTitle.bold()).foregroundStyle(Theme.text)
                    HStack(spacing: 6) {
                        ForEach(week, id: \.self) { d in
                            let chosen = Calendar.current.isDate(d, inSameDayAs: day)
                            Button {
                                day = d
                                Task { await load() }
                            } label: {
                                VStack(spacing: 4) {
                                    Text(d.formatted(.dateTime.weekday(.abbreviated))).font(.caption)
                                    Text(d.formatted(.dateTime.day())).font(.headline)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .foregroundStyle(chosen ? Theme.background : Theme.text)
                                .background(chosen ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                    if events.isEmpty {
                        Text("calendar.free").foregroundStyle(Theme.text2)
                    }
                    ForEach(events) { e in Item(event: e) { await answer(e, $0) } }
                }
                .padding(16)
            }
            .background(Theme.background)
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        events = (try? await client.events(from: day, to: end)) ?? []
    }

    private func answer(_ e: Event, _ a: String) async {
        try? await model.client?.answer(e, a)
        await load()
    }
}

private struct Item: View {
    let event: Event
    let answer: (String) async -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing) {
                Text(event.startDate.formatted(date: .omitted, time: .shortened))
                Text(event.endDate.formatted(date: .omitted, time: .shortened))
            }
            .font(.footnote).foregroundStyle(Theme.text2).frame(width: 52, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) {
                Text(event.summary).font(.headline).foregroundStyle(Theme.text)
                if let place = event.location, !place.isEmpty {
                    Text(place).font(.subheadline).foregroundStyle(Theme.text2)
                }
                if event.waiting {
                    HStack(spacing: 8) {
                        button("rsvp.yes", "accepted")
                        button("rsvp.maybe", "tentative")
                        button("rsvp.no", "declined")
                    }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Theme.accent).frame(width: 3).padding(.vertical, 8) }
        }
    }

    private func button(_ label: LocalizedStringKey, _ value: String) -> some View {
        Button { Task { await answer(value) } } label: {
            Text(label).font(.subheadline.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
    }
}
