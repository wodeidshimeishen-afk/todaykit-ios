import SwiftUI

struct ItemEditor: View {
    @EnvironmentObject var store: TodayStore
    @Environment(\.dismiss) private var dismiss
    @State var item: Item
    var onSave: ((Item) -> Void)? = nil

    static func quickItem(_ text: String) -> Item {
        var item = Item(title: text, timed: false)
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        if let index = weekdays.firstIndex(where: { text.hasPrefix($0) }) {
            item.title = String(text.dropFirst(2))
            if item.title.hasPrefix("提醒我") { item.title = String(item.title.dropFirst(3)) }
            let offset = (index + 1 - calendar.component(.weekday, from: Date()) + 7) % 7
            if let day = calendar.date(byAdding: .day, value: offset == 0 ? 7 : offset, to: .now),
               let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) {
                item.date = morning
                item.timed = true
                item.alert = true
            }
        }
        return item
    }

    var body: some View {
        Form {
            Section("事项") {
                TextField("输入要做的事", text: $item.title)
                if onSave == nil {
                    Picker("分类", selection: $item.kind) {
                        ForEach(Kind.allCases.filter { ![.study, .outing].contains($0) || $0 == item.kind }) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                }
                if item.kind == .task && onSave == nil {
                    Picker("处理方式", selection: $item.workflow) {
                        ForEach(Workflow.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if item.workflow == .waiting { TextField("跟进对象", text: $item.contact) }
                    if item.workflow == .now {
                        Button("1 分钟后提醒") {
                            item.date = .now.addingTimeInterval(60)
                            item.timed = true
                            item.alert = true
                        }
                    }
                }
            }
            Section("时间") {
                if onSave == nil && [.task, .habit, .meal, .activity].contains(item.kind) {
                    Toggle("指定时间", isOn: $item.timed)
                }
                if item.timed {
                    DatePicker(item.workflow == .waiting && item.kind == .task ? "跟进时间" : "开始", selection: $item.date)
                    if onSave == nil && [.routine, .habit, .water, .medicine].contains(item.kind) {
                        Picker("重复", selection: $item.repeatRule) {
                            ForEach(RepeatRule.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    if onSave == nil {
                        Toggle("本地提醒", isOn: $item.alert)
                        if item.alert && !store.notificationsAllowed {
                            Button("开启通知权限") { Task { await store.authorizeNotifications() } }
                            Text("通知权限未开启，仍可保存并在 App 内确认。").font(.footnote)
                        }
                    }
                } else if item.kind == .habit {
                    Text("开启设置里的每日总览后，可跟着总览提醒一起做。").font(.footnote)
                }
                Stepper("\(item.minutes) 分钟", value: $item.minutes, in: item.kind == .habit ? 5...10 : 1...720)
            }
            if onSave == nil, store.data.items.contains(where: { $0.id == item.id }) {
                Button("删除事项", role: .destructive) {
                    store.remove(item)
                    dismiss()
                }
            }
        }
        .navigationTitle(onSave == nil ? "事项详情" : "编辑安排")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !item.timed || ![.routine, .habit, .water, .medicine].contains(item.kind) { item.repeatRule = .once }
                    if !item.timed { item.alert = false }
                    if let onSave { onSave(item) } else { store.save(item) }
                    dismiss()
                }
                .disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onChange(of: item.kind) { _, kind in
            if kind == .habit { item.minutes = 5 }
            if [.exam, .routine, .water, .medicine].contains(kind) { item.timed = true }
        }
        .onChange(of: item.workflow) { _, workflow in
            if workflow == .waiting { item.timed = true; item.alert = true }
        }
    }
}

struct ScheduleLabel: View {
    var item: Item
    var detail: String? = nil
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.icon).frame(width: 31, height: 31)
                .background(sky.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(detail ?? "\(time(item.date))–\(time(item.end)) · \(item.minutes) 分钟")
                    .font(.caption).foregroundStyle(muted)
                if let place = item.activityLocation {
                    Label(place, systemImage: "mappin").font(.caption).foregroundStyle(muted)
                }
            }
            if item.example { Spacer(minLength: 4); Pill(text: "示例") }
        }.foregroundStyle(ink)
    }
}

struct DraftView: View {
    @EnvironmentObject var store: TodayStore
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [Item] = []
    @State private var editing: Item?
    @State private var export = false
    @State private var loaded = false
    var exam: Item? = nil
    var missed: Item? = nil

    var body: some View {
        List {
            Section {
                if drafts.isEmpty {
                    Text("目前没有合适的空档。可以下次再排，或手动添加一项。").foregroundStyle(muted)
                }
                ForEach(drafts) { draft in
                    Button { editing = draft } label: {
                        ScheduleLabel(item: draft, detail: "\(draft.date.formatted(.dateTime.month().day())) · \(time(draft.date)) · \(draft.minutes) 分钟")
                    }
                }
                .onDelete { drafts.remove(atOffsets: $0) }
            } header: {
                Text("可编辑草稿")
            } footer: {
                Text("点开可改时间或时长，左滑可删除。自动排程会尽量在事项之间预留休息和往返时间。")
            }
            if exam == nil {
                Section {
                    Button("今天轻松点") { build(light: true) }
                    Button("重排完整方案") { build(light: false) }
                }
            }
            Section {
                Toggle("同时写入 iPhone 日历", isOn: $export).disabled(!store.calendarAllowed)
                if !store.calendarAllowed {
                    Button("开启日历权限") { Task { await store.authorizeCalendar() } }
                }
                if hasOverlap { Text("草稿与其他安排有重叠，请先调整时间。").font(.footnote).foregroundStyle(.red) }
                if drafts.contains(where: { $0.date < Date() }) {
                    Text("草稿包含已过去的时间，请调整。").font(.footnote).foregroundStyle(.red)
                }
                if let exam, drafts.contains(where: { $0.end > exam.date }) {
                    Text("复习结束时间需早于考试。").font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(exam == nil ? "安排今天" : "考前复习")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("确认保存") {
                    var updated = store.data
                    if let missed { updated.items.removeAll { $0.id == missed.id } }
                    for item in drafts { updated.save(item) }
                    store.data = updated
                    if export { store.export(drafts) }
                    dismiss()
                }.disabled(drafts.isEmpty || hasOverlap || drafts.contains { item in
                    item.date < Date() || (exam.map { item.end > $0.date } ?? false)
                })
            }
        }
        .onAppear {
            if !loaded { build(light: false); loaded = true }
        }
        .sheet(item: $editing) { draft in
            NavigationStack {
                ItemEditor(item: draft) { saved in
                    if let index = drafts.firstIndex(where: { $0.id == saved.id }) {
                        drafts[index] = saved
                        drafts.sort { $0.date < $1.date }
                    }
                }
            }
        }
    }

    private var hasOverlap: Bool {
        drafts.contains { item in
            let endDay = calendar.startOfDay(for: item.end)
            var busy = store.busy(on: item.date)
            if !calendar.isDate(endDay, inSameDayAs: item.date) { busy += store.busy(on: endDay) }
            return (busy + drafts).contains { other in
                item.id != other.id && other.id != missed?.id && item.date < other.end && other.date < item.end
            }
        }
    }

    private func build(light: Bool) {
        let now = Date().addingTimeInterval(120)
        if let exam {
            drafts = Planner.review(exam: exam, now: now, minutes: missed?.minutes ?? store.data.studyMinutes,
                                    busy: { store.busy(on: $0) }, replacingMissed: missed != nil)
        } else {
            drafts = Planner.draft(now: now, busy: store.busy(on: now), data: store.data, light: light)
        }
    }
}

struct AgendaView: View {
    @EnvironmentObject var store: TodayStore
    @State private var date = Date()
    @State private var editing: Item?
    @State private var review: Item?
    @State private var missed: Item?

    var body: some View {
        List {
            NavigationLink { TaskListView() } label: { Label("待办清单", systemImage: "checklist") }
            DatePicker("查看日期", selection: $date, displayedComponents: .date)
            if !store.calendarAllowed {
                Section {
                    Text("可以查看和编辑 App 内的日程。").font(.footnote).foregroundStyle(muted)
                    Button("连接 iPhone 日历") { Task { await store.authorizeCalendar() } }
                } header: { Text("日历权限未开启") }
            }
            Section("当天安排") {
                let agenda = store.agenda(on: date)
                let localIDs = Set(agenda.map { $0.id.uuidString })
                let phone = store.phoneEvents(on: date).filter { event in
                    guard let url = event.url, url.scheme == "todaykit", url.host == "schedule" else { return true }
                    return !localIDs.contains(url.lastPathComponent)
                }
                if agenda.isEmpty && phone.isEmpty { Text("当天没有安排。").foregroundStyle(muted) }
                ForEach(agenda) { item in
                    let original = store.data.items.first { $0.id == item.id } ?? item
                    HStack {
                        Button { editing = original } label: { ScheduleLabel(item: item) }.buttonStyle(.plain)
                        Spacer()
                        if store.data.completed(item) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("已完成")
                        } else if !calendar.isDateInToday(item.date) && item.date > Date() && item.kind != .exam {
                            EmptyView()
                        } else if item.kind != .exam {
                            Button { store.finish(item) } label: { Image(systemName: "circle") }
                                .buttonStyle(.borderless).accessibilityLabel("完成 \(item.title)")
                        }
                    }
                }
                ForEach(phone, id: \.calendarItemIdentifier) { event in
                    let eventItem = store.fromEvent(event)
                    VStack(alignment: .leading, spacing: 6) {
                        ScheduleLabel(item: eventItem, detail: event.isAllDay ? "全天 · iPhone 日历" : "\(time(eventItem.date))–\(time(eventItem.end)) · iPhone 日历")
                        if ["考试", "测验", "期末", "期中", "exam", "quiz", "midterm"].contains(where: { eventItem.title.localizedCaseInsensitiveContains($0) }),
                           !store.data.items.contains(where: { $0.kind == .exam && $0.title == eventItem.title && $0.date == eventItem.date }) {
                            Button("确认这是考试") {
                                var exam = eventItem
                                exam.kind = .exam
                                editing = exam
                            }.font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            Section("待复习的考试") {
                let exams = store.data.items.filter { $0.kind == .exam && $0.date > Date() }.sorted { $0.date < $1.date }
                if exams.isEmpty { Text("添加考试后可生成复习安排。").foregroundStyle(muted) }
                ForEach(exams) { exam in
                    VStack(alignment: .leading, spacing: 8) {
                        ScheduleLabel(item: exam, detail: exam.date.formatted(.dateTime.month().day().hour().minute()))
                        Button("生成考前复习") { missed = nil; review = exam }.font(.subheadline.weight(.semibold))
                    }
                }
            }
            let overdue = store.data.items.filter { item in
                item.kind == .study && item.end < Date() && !store.data.completed(item)
                    && store.data.items.contains { $0.id == item.examID && $0.date > Date() }
            }
            if !overdue.isEmpty {
                Section("漏掉的复习") {
                    ForEach(overdue) { item in
                        Button("为「\(item.title)」找新时间") {
                            missed = item
                            review = store.data.items.first { $0.id == item.examID }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(store.theme.base)
        .navigationTitle("日程")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("新增事项") { editing = Item(date: selectionDate) }
                    Button("新增考试") { editing = Item(kind: .exam, date: selectionDate, minutes: 60) }
                    Button("新增固定日常") { editing = Item(kind: .routine, date: selectionDate, repeatRule: .daily) }
                } label: { Label("添加日程", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { item in NavigationStack { ItemEditor(item: item) } }
        .sheet(item: $review) { exam in NavigationStack { DraftView(exam: exam, missed: missed) } }
    }

    private var selectionDate: Date { calendar.isDateInToday(date) ? .now : clockTime(on: date, at: .now) }
}

struct TaskListView: View {
    @EnvironmentObject var store: TodayStore
    @State private var edit: Item?

    var body: some View {
        List {
            ForEach(Workflow.allCases) { workflow in
                Section(workflow.rawValue) {
                    let items = store.data.items.filter { $0.kind == .task && $0.workflow == workflow && !store.data.completed($0) }
                    if items.isEmpty { Text("暂无待办").foregroundStyle(muted) }
                    ForEach(items) { item in
                        HStack {
                            Button { edit = item } label: {
                                ScheduleLabel(item: item, detail: item.timed ? item.date.formatted(.dateTime.month().day().hour().minute()) + (item.contact.isEmpty ? "" : " · " + item.contact) : "\(item.minutes) 分钟")
                            }.buttonStyle(.plain)
                            Spacer()
                            Button { store.finish(item) } label: { Image(systemName: "checkmark.circle") }
                                .buttonStyle(.borderless).accessibilityLabel("完成 \(item.title)")
                        }
                    }
                }
            }
        }
        .navigationTitle("待办")
        .toolbar {
            Button { edit = Item(timed: false) } label: { Label("添加待办", systemImage: "plus") }
        }
        .sheet(item: $edit) { item in NavigationStack { ItemEditor(item: item) } }
    }
}
