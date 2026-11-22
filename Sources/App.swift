import SwiftUI
import EventKit

let cream = Color(red: 0.99, green: 0.975, blue: 0.944)
let ink = Color(red: 0.10, green: 0.20, blue: 0.34)
let muted = Color(red: 0.30, green: 0.39, blue: 0.49)
let sky = Color(red: 0.82, green: 0.89, blue: 0.98)
let pink = Color(red: 0.98, green: 0.86, blue: 0.88)
let mint = Color(red: 0.88, green: 0.93, blue: 0.86)
let paper = Color(red: 1, green: 0.995, blue: 0.981)

@main
@MainActor
struct TodayApp: App {
    @UIApplicationDelegateAdaptor(TodayDelegate.self) var delegate
    @StateObject private var store = TodayStore.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .preferredColorScheme(.light)
                .tint(store.theme.accent)
                .task { await store.refresh() }
                .onChange(of: phase) { _, value in
                    if value == .active { Task { await store.refresh() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                    store.calendarRevision += 1
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: TodayStore
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("今天", systemImage: "sun.max") }.tag(0)
            NavigationStack { FoodView() }
                .tabItem { Label("吃什么", systemImage: "fork.knife") }.tag(1)
            NavigationStack { AgendaView() }
                .tabItem { Label("日程", systemImage: "calendar") }.tag(2)
            NavigationStack { HistoryView() }
                .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }.tag(3)
        }
        .onChange(of: store.showToday) { _, _ in tab = 0 }
        .alert("今天干什么", isPresented: Binding(get: { !store.notice.isEmpty }, set: { if !$0 { store.notice = "" } })) {
            Button("知道了", role: .cancel) { store.notice = "" }
        } message: { Text(store.notice) }
    }
}

struct SoftPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct Pill: View {
    var text: String
    var fill: Color = pink
    var body: some View {
        Text(text).font(.caption.weight(.semibold))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(fill, in: Capsule())
    }
}

struct HomeView: View {
    @EnvironmentObject var store: TodayStore
    @State private var sheet: HomeSheet?
    @State private var quick = ""
    @State private var weather: DailyWeather?
    @State private var weatherFor: String?
    @State private var suggestionOffset = 0
    @State private var planExpanded = false
    @State private var quickExpanded = false
    @FocusState private var quickFocused: Bool

    enum HomeSheet: String, Identifiable {
        case draft, draw, add
        var id: String { rawValue }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            let city = store.data.weatherCity
            let weatherKey = city.map { "\($0.id)/\(calendar.startOfDay(for: now).timeIntervalSinceReferenceDate)" }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    heading(now, weather: weatherFor == weatherKey ? weather : nil)
                    placeCard(now)
                    nextCard(now)
                    planMenu
                    suggestions(now)
                    privateNotes
                    due(now)
                    utilities
                    if quickExpanded { quickAdd }
                }
                .padding(.horizontal, 20).padding(.top, 13).padding(.bottom, 24)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
                .foregroundStyle(ink)
            }
            .scrollDismissesKeyboard(.interactively)
            .task(id: weatherKey) {
                guard let city, weatherFor != weatherKey else { return }
                do {
                    let forecast = try await OpenMeteo.weather(for: city)
                    guard !Task.isCancelled else { return }
                    weather = forecast
                    weatherFor = weatherKey
                } catch {
                    if !Task.isCancelled { weather = nil }
                }
            }
        }
        .background(store.theme.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { page in
            NavigationStack {
                switch page {
                case .draft: DraftView()
                case .draw: ActivityDraw()
                case .add: ItemEditor(item: ItemEditor.quickItem(quick))
                }
            }
        }
    }

    private func heading(_ now: Date, weather: DailyWeather?) -> some View {
        HStack(alignment: .center, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                Text(now.formatted(.dateTime.month(.wide).day().weekday(.abbreviated).locale(Locale(identifier: "zh_CN"))))
                    .font(.footnote.weight(.medium)).foregroundStyle(muted)
                Text("今天干什么").font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let weather, weather.code != nil {
                VStack(alignment: .trailing, spacing: 3) {
                    Label(weather.label, systemImage: weather.symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ink)
                    if let range = weather.range {
                        Text(range).font(.caption2.monospacedDigit()).foregroundStyle(muted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
            }
            .accessibilityLabel("设置")
            .buttonStyle(SoftPress())
        }
        .padding(.bottom, 3)
    }

    private func placeCard(_ now: Date) -> some View {
        HStack(spacing: 4) {
            ForEach(DayPlace.allCases) { place in
                let selected = store.data.place(on: now) == place
                Button {
                    store.data.selectPlace(place)
                    Task { await store.syncNotifications() }
                } label: {
                    Label(place.rawValue, systemImage: place.icon)
                        .font(.subheadline.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? store.theme.accent : ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            selected ? store.theme.accent.opacity(0.10) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(SoftPress())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("今天的状态")
    }

    private func nextCard(_ now: Date) -> some View {
        let agenda = store.agenda(on: now)
        let local = agenda.filter { !store.data.completed($0) && $0.end > now }
        let ids = Set(agenda.map { $0.id.uuidString })
        let system = store.phoneEvents(on: now).filter { event in
            guard !event.isAllDay, event.endDate > now else { return false }
            if let url = event.url, url.scheme == "todaykit", url.host == "schedule" {
                return !ids.contains(url.lastPathComponent)
            }
            return true
        }.map(store.fromEvent)
        let next = (local + system).min { $0.date < $1.date }
        return NavigationLink {
            AgendaView()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("下一件事").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(muted).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(next?.title ?? "今天还有空档")
                        .font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 7) {
                        Text(next.map { "\(time($0.date))–\(time($0.end))" } ?? "查看完整日程")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(muted)
                        if next?.example == true { Pill(text: "示例", fill: store.theme.base) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 25))
        }
        .buttonStyle(SoftPress())
    }

    private var planMenu: some View {
        VStack(spacing: 6) {
            Button { planExpanded.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar.badge.plus")
                    Text("帮我安排今天")
                    Image(systemName: planExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(store.theme.accent, in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(SoftPress())
            .accessibilityValue(planExpanded ? "已展开" : "已收起")
            if planExpanded {
                VStack(spacing: 0) {
                    planOption("生成今日日程", icon: "calendar.badge.checkmark", destination: .draft)
                    Divider()
                    planOption("抽一签", icon: "shuffle", destination: .draw)
                }
                .padding(.horizontal, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 17))
            }
        }
    }

    private func planOption(_ title: String, icon: String, destination: HomeSheet) -> some View {
        Button {
            planExpanded = false
            sheet = destination
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(SoftPress())
    }

    private func suggestions(_ now: Date) -> some View {
        let activities = store.data.activities
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        let initial = calendar.ordinality(of: .day, in: .era, for: store.data.created) ?? day
        let picks = Activity.suggestions(from: activities, offset: day - initial + suggestionOffset)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("现在可以做").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                if activities.count > 2 {
                    Button {
                        suggestionOffset = (suggestionOffset + 2) % activities.count
                    } label: {
                        Label("换一换", systemImage: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(store.theme.accent)
                            .padding(.leading, 8)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(SoftPress())
                }
            }
            if picks.isEmpty {
                Text("可以在设置里添加活动。").font(.subheadline).foregroundStyle(muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(picks) { activity in
                        if activity.id != picks.first?.id { Divider() }
                        NavigationLink {
                            ActivityDetail(activity: activity)
                        } label: {
                            HStack(spacing: 9) {
                                Text(activity.emoji).accessibilityHidden(true)
                                Text(activity.name).font(.subheadline.weight(.medium))
                                Spacer(minLength: 4)
                                Text("\(activity.minutes) 分钟").font(.caption).foregroundStyle(muted)
                            }
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SoftPress())
                    }
                }
                .padding(.horizontal, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 22))
            }
        }
    }

    private var privateNotes: some View {
        NavigationLink {
            PrivateNotesView()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "square.and.pencil").font(.subheadline)
                    .foregroundStyle(store.theme.accent)
                    .frame(width: 36, height: 36)
                    .background(store.theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("碎碎念").font(.subheadline.weight(.semibold))
                    Text("写点什么，仅自己可见").font(.caption).foregroundStyle(muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(muted).accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(SoftPress())
    }

    private var utilities: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                quickAddLink
                Divider().frame(height: 22)
                habitsLink
            }
            VStack(spacing: 0) {
                quickAddLink
                Divider().padding(.horizontal, 12)
                habitsLink
            }
        }
        .padding(5)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .font(.footnote.weight(.medium))
    }

    private var quickAddLink: some View {
        Button { quickExpanded.toggle() } label: {
            Label("随手添加", systemImage: "plus")
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SoftPress())
        .accessibilityValue(quickExpanded ? "已展开" : "已收起")
    }

    private var habitsLink: some View {
        NavigationLink {
            HabitsView()
        } label: {
            Label("小习惯", systemImage: "leaf")
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SoftPress())
    }

    @ViewBuilder
    private func due(_ now: Date) -> some View {
        let items = store.agenda(on: now).filter {
            [.water, .medicine].contains($0.kind) && $0.date <= now && !store.data.completed($0)
        }
        if !items.isEmpty {
            VStack(spacing: 8) {
                ForEach(items) { item in
                    HStack {
                        Label(item.title, systemImage: item.kind.icon)
                        Spacer()
                        Button(item.kind.completion) { store.finish(item) }.buttonStyle(.borderedProminent)
                    }
                    .font(.subheadline)
                }
            }
            .padding(14).background(sky, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("周五提醒我问组员 PPT", text: $quick)
                    .focused($quickFocused)
                    .submitLabel(.continue).onSubmit { sheet = .add }
                Button { sheet = .add } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }.accessibilityLabel("继续添加")
            }
            .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
            .onAppear { quickFocused = true }
        }
    }
}
