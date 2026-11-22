import SwiftUI
import UIKit
import EventKit
import UserNotifications

@MainActor
final class TodayStore: ObservableObject {
    static let shared = TodayStore()
    @Published var data: LocalData {
        didSet { persist() }
    }
    @Published var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var notificationsAllowed = false
    @Published var calendarRevision = 0
    @Published var notice = ""
    @Published var showToday = UUID()
    private let events = EKEventStore()
    private let center = UNUserNotificationCenter.current()
    private let storage = URL.applicationSupportDirectory.appending(path: "TodayKit.json")
    private var syncingNotifications = false
    private var needsNotificationSync = false

    private init() {
        if FileManager.default.fileExists(atPath: storage.path) {
            do {
                var loaded = try JSONDecoder().decode(LocalData.self, from: Data(contentsOf: storage))
                let needsUpgrade = loaded.expandedActivities != true
                loaded.expandActivityLibrary()
                data = loaded
                if needsUpgrade { persist() }
            } catch {
                data = LocalData()
                notice = "无法读取本地数据。原文件已保留，当前改动只保留到关闭 App。"
                storageReadable = false
            }
        } else {
            data = .sample()
            persist()
        }
    }

    private var storageReadable = true

    private func persist() {
        guard storageReadable else { return }
        do {
            try FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(data).write(to: storage, options: .atomic)
        } catch {
            notice = "本地保存失败，请检查设备可用空间。"
        }
    }

    var calendarAllowed: Bool { calendarStatus == .fullAccess }

    func refresh() async {
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        calendarRevision += 1
        await syncNotifications()
    }

    func authorizeCalendar() async {
        do {
            let granted = try await events.requestFullAccessToEvents()
            calendarStatus = EKEventStore.authorizationStatus(for: .event)
            calendarRevision += 1
            if !granted { notice = "日历权限未开启。你仍可手动安排，也可在 iPhone 设置中更改权限。" }
        } catch {
            notice = "无法访问日历，可以继续手动安排。"
        }
    }

    func phoneEvents(on day: Date) -> [EKEvent] {
        guard calendarAllowed else { return [] }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.events(matching: events.predicateForEvents(withStart: start, end: end, calendars: nil))
    }

    func fromEvent(_ event: EKEvent) -> Item {
        Item(title: event.title ?? "日历事项", kind: .routine, date: event.startDate,
             minutes: max(1, Int(ceil(event.endDate.timeIntervalSince(event.startDate) / 60))))
    }

    func agenda(on day: Date) -> [Item] {
        data.items.compactMap { $0.occurrence(on: day) }.sorted { $0.date < $1.date }
    }

    func busy(on day: Date) -> [Item] {
        agenda(on: day).filter { !data.completed($0) } + phoneEvents(on: day)
            .filter { !$0.isAllDay && $0.availability != .free }.map(fromEvent)
    }

    func export(_ items: [Item]) {
        guard calendarAllowed, let destination = events.defaultCalendarForNewEvents else {
            notice = "已保存到 App。写入手机日历需要开启日历权限和可写入的默认日历。"
            return
        }
        do {
            for item in items {
                let event = EKEvent(eventStore: events)
                event.title = item.title
                event.startDate = item.date
                event.endDate = item.end
                event.calendar = destination
                event.url = URL(string: "todaykit://schedule/\(item.id.uuidString)")
                try events.save(event, span: .thisEvent, commit: false)
            }
            try events.commit()
            calendarRevision += 1
        } catch {
            events.reset()
            notice = "已保存到 App。写入手机日历失败：\(error.localizedDescription)"
        }
    }

    func save(_ item: Item) {
        if let previous = data.items.first(where: { $0.id == item.id }),
           previous.date != item.date || previous.repeatRule != item.repeatRule || !item.alert {
            center.removePendingNotificationRequests(withIdentifiers: [identifier(item) + ".later"])
            center.removeDeliveredNotifications(withIdentifiers: [identifier(item), identifier(item) + ".later"])
        }
        data.save(item)
        if item.kind == .exam {
            data.items.removeAll { $0.examID == item.id && $0.date > Date() && $0.end > item.date }
        }
        Task { await syncNotifications() }
    }

    func remove(_ item: Item) {
        let removed = data.items.filter { $0.id == item.id || $0.examID == item.id || $0.taskID == item.id }
        data.items.removeAll { candidate in removed.contains { $0.id == candidate.id } }
        let identifiers = removed.flatMap { [identifier($0), identifier($0) + ".later"] }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        Task { await syncNotifications() }
    }

    func finish(_ item: Item, energy: MealEnergy? = nil, meal: MealDetails? = nil) {
        data.finish(item, energy: energy, meal: meal)
        let identifiers = item.repeatRule == .once ? [identifier(item), identifier(item) + ".later"] : [identifier(item) + ".later"]
        center.removeDeliveredNotifications(withIdentifiers: [identifier(item), identifier(item) + ".later"])
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        Task { await syncNotifications() }
    }

    func authorizeNotifications() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await syncNotifications()
            if !notificationsAllowed { notice = "通知未开启。设置会保存在 App，也可在 iPhone 设置中开启通知。" }
        } catch {
            notice = "无法开启通知，可以在 App 内查看和确认事项。"
        }
    }

    func configureActions() {
        let later = UNNotificationAction(identifier: "later", title: "10 分钟后提醒")
        let definitions = [("overview", "查看今天"), ("water", "喝了"), ("medicine", "已服用"), ("item", "完成")]
        center.setNotificationCategories(Set(definitions.map { key, title in
            let done = UNNotificationAction(identifier: "done", title: title, options: key == "overview" ? [.foreground] : [])
            return UNNotificationCategory(identifier: key, actions: [done, later], intentIdentifiers: [])
        }))
    }

    private func identifier(_ item: Item) -> String { "todaykit." + item.id.uuidString }

    private func notificationTrigger(for item: Item) -> UNCalendarNotificationTrigger {
        if item.repeatRule != .once {
            let keys: Set<Calendar.Component> = item.repeatRule == .daily ? [.hour, .minute] : [.weekday, .hour, .minute]
            let repeating = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents(keys, from: item.date), repeats: true)
            if let next = repeating.nextTriggerDate(), calendar.startOfDay(for: next) >= calendar.startOfDay(for: item.date) {
                return repeating
            }
        }
        let matching = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.date)
        return UNCalendarNotificationTrigger(dateMatching: matching, repeats: false)
    }

    private func overviewRequest(id: String, body: String, trigger: UNCalendarNotificationTrigger) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "今天干什么"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "overview"
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    func clearOverviewSnooze() {
        center.removePendingNotificationRequests(withIdentifiers: ["todaykit.overview.later"])
    }

    func syncNotifications() async {
        needsNotificationSync = true
        guard !syncingNotifications else { return }
        syncingNotifications = true
        defer { syncingNotifications = false }
        while needsNotificationSync {
            needsNotificationSync = false
            let status = await center.notificationSettings().authorizationStatus
            notificationsAllowed = [.authorized, .provisional, .ephemeral].contains(status)
            guard notificationsAllowed else { continue }

            let pending = await center.pendingNotificationRequests()
            let now = Date()
            var requests: [UNNotificationRequest] = []
            if data.overview {
                let last = data.history.filter { $0.item.isOuting }.map(\.date).max() ?? data.created
                let threshold = calendar.date(byAdding: .day, value: data.outingDays, to: calendar.startOfDay(for: last)) ?? now
                let habitNames = data.items.filter { $0.kind == .habit && !$0.timed }.prefix(2).map(\.title)
                let body = habitNames.isEmpty ? "看看今天的安排和两个现在可以做的建议。" :
                    "看看今天的安排。小习惯：" + habitNames.joined(separator: "、") + "。"
                let repeatMatching = calendar.dateComponents([.hour, .minute], from: data.overviewTime)
                let repeating = UNCalendarNotificationTrigger(dateMatching: repeatMatching, repeats: true)
                let next = repeating.nextTriggerDate() ?? now
                if !data.outingNudge || next >= threshold {
                    requests.append(overviewRequest(id: "todaykit.overview",
                        body: body + (data.outingNudge ? " 今天想出去走走吗？" : ""), trigger: repeating))
                } else {
                    // Schedule one overview per day through the transition. A later app visit
                    // or notification action replenishes this schedule or starts daily repeats.
                    for offset in 0..<36 {
                        guard let day = calendar.date(byAdding: .day, value: offset, to: next) else { continue }
                        let date = clockTime(on: day, at: data.overviewTime)
                        let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
                        let suffix = String(Int(date.timeIntervalSinceReferenceDate))
                        requests.append(overviewRequest(id: "todaykit.overview." + suffix,
                            body: body + (date >= threshold ? " 今天想出去走走吗？" : ""), trigger: trigger))
                    }
                }
            }
            if let bedtime = data.bedtime {
                for reminder in bedtime.reminders {
                    let content = UNMutableNotificationContent()
                    content.title = "睡前提醒"
                    content.body = reminder.message
                    content.sound = .default
                    let trigger = UNCalendarNotificationTrigger(
                        dateMatching: bedtime.clockComponents(minutesBefore: reminder.offset), repeats: true)
                    requests.append(UNNotificationRequest(identifier: "todaykit.bedtime.\(reminder.offset)", content: content, trigger: trigger))
                }
            }
            let candidates = data.items.filter { $0.alert && $0.timed && ($0.repeatRule != .once || (!data.completed($0) && $0.date > now)) }
            for item in candidates {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.contact.isEmpty ? item.kind.rawValue : "跟进 \(item.contact)"
                content.sound = .default
                content.userInfo = ["id": item.id.uuidString]
                content.categoryIdentifier = item.kind == .water ? "water" : item.kind == .medicine ? "medicine" : "item"
                requests.append(UNNotificationRequest(identifier: identifier(item), content: content, trigger: notificationTrigger(for: item)))
            }
            let keptSnoozes = pending.filter { request in
                guard request.identifier.hasSuffix(".later") else { return false }
                if request.identifier == "todaykit.overview.later" { return data.overview }
                return data.items.contains {
                    $0.alert && $0.timed && ($0.repeatRule != .once || !data.completed($0)) &&
                        request.identifier == identifier($0) + ".later"
                }
            }
            let ordered = requests.sorted {
                let first = $0.trigger as? UNCalendarNotificationTrigger
                let second = $1.trigger as? UNCalendarNotificationTrigger
                if first?.repeats != second?.repeats { return first?.repeats == true }
                return (first?.nextTriggerDate() ?? .distantFuture) < (second?.nextTriggerDate() ?? .distantFuture)
            }
            let limit = max(0, 64 - keptSnoozes.count)
            let selected = Array(ordered.prefix(limit))
            let wanted = Set((selected + keptSnoozes).map(\.identifier))
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("todaykit.") && !wanted.contains($0) })
            for request in selected {
                do { try await center.add(request) }
                catch { notice = "有提醒未能注册，请检查通知设置。" }
            }
            if ordered.count > limit { notice = "提醒过多，已按重复规则和时间优先注册 \(limit) 条。" }
        }
    }

    func handle(_ response: UNNotificationResponse) async {
        let request = response.notification.request
        let content = request.content
        if response.actionIdentifier == "later" {
            if request.identifier.hasPrefix("todaykit.overview") {
                guard data.overview else { return }
            } else {
                guard let id = content.userInfo["id"] as? String, data.items.contains(where: {
                    $0.id.uuidString == id && $0.alert && $0.timed && ($0.repeatRule != .once || !data.completed($0))
                }) else { return }
            }
            let base = request.identifier.hasPrefix("todaykit.overview") ? "todaykit.overview" :
                request.identifier.replacingOccurrences(of: ".later", with: "")
            do {
                guard let snooze = content.mutableCopy() as? UNMutableNotificationContent else { return }
                var info = snooze.userInfo
                if info["originalDelivery"] == nil {
                    info["originalDelivery"] = response.notification.date.timeIntervalSince1970
                    snooze.userInfo = info
                }
                try await center.add(UNNotificationRequest(identifier: base + ".later", content: snooze,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)))
            } catch {
                notice = "未能添加稍后提醒。"
            }
        } else if response.actionIdentifier == "done", let value = content.userInfo["id"] as? String,
                  let id = UUID(uuidString: value), let item = data.items.first(where: { $0.id == id }) {
            let originalDate = (content.userInfo["originalDelivery"] as? Double).map {
                Date(timeIntervalSince1970: $0)
            } ?? response.notification.date
            var occurrence = item
            if item.repeatRule != .once {
                let candidate = clockTime(on: originalDate, at: item.date)
                let offset = item.repeatRule == .daily ? 1 : 7
                let correctWeekday = item.repeatRule == .daily || calendar.component(.weekday, from: originalDate) == calendar.component(.weekday, from: item.date)
                let daysBack = correctWeekday ? (candidate.timeIntervalSince(originalDate) > 60 ? offset : 0) :
                    (calendar.component(.weekday, from: originalDate) - calendar.component(.weekday, from: item.date) + 7) % 7
                occurrence.date = calendar.date(byAdding: .day, value: -daysBack, to: candidate) ?? candidate
            }
            finish(occurrence)
        } else {
            showToday = UUID()
        }
        // A future-start recurring reminder switches to its repeating trigger after the first delivery or next app launch.
        await syncNotifications()
    }
}

final class TodayDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        TodayStore.shared.configureActions()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await TodayStore.shared.handle(response)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
