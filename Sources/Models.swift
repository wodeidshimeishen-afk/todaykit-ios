import Foundation

let calendar = Calendar.current

enum Kind: String, Codable, CaseIterable, Identifiable {
    case activity = "活动", meal = "吃饭", habit = "小习惯", water = "喝水", medicine = "吃药"
    case exam = "考试", study = "复习", routine = "固定日常", task = "待办", outing = "出门"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .activity: "sparkles"
        case .meal: "fork.knife"
        case .habit: "leaf.fill"
        case .water: "drop.fill"
        case .medicine: "pill.fill"
        case .exam: "graduationcap.fill"
        case .study: "book.fill"
        case .routine: "calendar"
        case .task: "checklist"
        case .outing: "figure.walk"
        }
    }
    var completion: String {
        switch self {
        case .water: "喝了"
        case .medicine: "已服用"
        default: "完成"
        }
    }
}

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case once = "仅一次", daily = "每天", weekly = "每周"
    var id: String { rawValue }
}

enum Workflow: String, Codable, CaseIterable, Identifiable {
    case now = "立即处理", plan = "计划安排", waiting = "委派／等回复", later = "有空再做"
    var id: String { rawValue }
}

struct Item: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var kind = Kind.task
    var date = Date()
    var minutes = 30
    var timed = true
    var repeatRule = RepeatRule.once
    var alert = false
    var workflow = Workflow.plan
    var contact = ""
    var examID: UUID?
    var taskID: UUID?
    var example = false
    var requiresOuting: Bool?
    var activityLocation: String?
    var isOuting: Bool { kind == .outing || requiresOuting == true }
    var end: Date { date.addingTimeInterval(Double(minutes) * 60) }

    func occurrence(on day: Date) -> Item? {
        guard timed else { return nil }
        if repeatRule == .once {
            let start = calendar.startOfDay(for: day)
            let finish = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return date < finish && end > start ? self : nil
        }
        guard calendar.startOfDay(for: day) >= calendar.startOfDay(for: date) else { return nil }
        if repeatRule == .weekly && calendar.component(.weekday, from: day) != calendar.component(.weekday, from: date) {
            return nil
        }
        var occurrence = self
        occurrence.date = clockTime(on: day, at: date)
        return occurrence
    }
}

func clockTime(on day: Date, at source: Date) -> Date {
    let parts = calendar.dateComponents([.hour, .minute], from: source)
    return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
}

func time(_ date: Date) -> String {
    date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "zh_CN")))
}

struct Activity: Codable, Identifiable {
    var id = UUID()
    var name = ""
    var emoji = "✨"
    var minutes = 30
    var outside = false
}

extension Activity {
    static func suggestions(from activities: [Self], offset: Int) -> [Self] {
        guard !activities.isEmpty else { return [] }
        let count = activities.count
        let first = (offset % count + count) % count
        return (0..<min(2, count)).map { activities[(first + $0) % count] }
    }

    static let additions: [Self] = [
        .init(name: "跟着做一组拉伸", emoji: "🧘", minutes: 10),
        .init(name: "听一期播客", emoji: "🎧", minutes: 25),
        .init(name: "看一部电影", emoji: "🍿", minutes: 120),
        .init(name: "看一集纪录片", emoji: "🎬", minutes: 45),
        .init(name: "拼一个拼豆小图案", emoji: "🧩", minutes: 30),
        .init(name: "写一页日记", emoji: "📔", minutes: 10),
        .init(name: "临摹一页字帖", emoji: "✍️", minutes: 15),
        .init(name: "用 Excel 做一张开销表", emoji: "📊", minutes: 25),
        .init(name: "找三张喜欢的海报，看看配色", emoji: "🎨", minutes: 20),
        .init(name: "打扫一个角落", emoji: "🧹", minutes: 15),
        .init(name: "换床单、晒被子", emoji: "🛏️", minutes: 20),
        .init(name: "读十页书", emoji: "📖", minutes: 15),
        .init(name: "折一只纸鹤", emoji: "🕊️", minutes: 10),
        .init(name: "画一张桌面小物速写", emoji: "✏️", minutes: 20),
        .init(name: "整理十张想留的照片", emoji: "🖼️", minutes: 15),
        .init(name: "泡一杯茶，坐着歇会儿", emoji: "🍵", minutes: 5),
        .init(name: "到楼下走一圈", emoji: "🚶", minutes: 10, outside: true),
        .init(name: "出门买一杯奶茶", emoji: "🧋", minutes: 20, outside: true),
        .init(name: "逛附近的早市", emoji: "🥬", minutes: 30, outside: true),
        .init(name: "去公园散步", emoji: "🌳", minutes: 30, outside: true),
        .init(name: "去书店翻翻新书", emoji: "📚", minutes: 30, outside: true),
        .init(name: "去花店看看当季的花", emoji: "🌷", minutes: 20, outside: true),
        .init(name: "拍三张街景", emoji: "📷", minutes: 25, outside: true),
        .init(name: "到附近骑一小圈", emoji: "🚲", minutes: 25, outside: true),
        .init(name: "去湖边或河边坐坐", emoji: "🌿", minutes: 35, outside: true),
        .init(name: "去图书馆看半小时书", emoji: "📗", minutes: 45, outside: true),
        .init(name: "看看附近的小展览", emoji: "🖼️", minutes: 60, outside: true)
    ]
}

struct MealEnergy: Codable {
    var kilocalories: Int
    var estimated: Bool
    var portion: String

    static func estimate(parts: [(grams: Double, per100g: Double)], portions: Double) -> Int? {
        guard !parts.isEmpty, portions.isFinite, portions > 0,
              parts.allSatisfy({ $0.grams.isFinite && $0.grams > 0 && (0...1000).contains($0.per100g) }) else { return nil }
        let total = parts.reduce(0.0) { $0 + $1.grams * $1.per100g / 100 } / portions
        guard total.isFinite, total <= 100_000 else { return nil }
        return Int(total.rounded())
    }
}

struct Bedtime: Codable, Equatable {
    var enabled = false
    var time = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
    var before15 = true
    var before10 = true
    var atTime = true

    var reminders: [(offset: Int, message: String)] {
        guard enabled else { return [] }
        var result: [(Int, String)] = []
        if before15 { result.append((15, "还有 15 分钟就该睡啦，可以去洗漱、换睡衣了。")) }
        if before10 { result.append((10, "还有 10 分钟。把手头的事收个尾，准备放下手机吧。")) }
        if atTime { result.append((0, "到睡觉时间啦。晚安 🌙")) }
        return result
    }

    func clockComponents(minutesBefore offset: Int) -> DateComponents {
        let total = (calendar.component(.hour, from: time) * 60 + calendar.component(.minute, from: time) - offset + 1440) % 1440
        return DateComponents(hour: total / 60, minute: total % 60)
    }
}

struct PrivateNote: Codable, Identifiable {
    var id = UUID()
    var title = ""
    var body = ""
    var created = Date()
}

struct MealDetails: Codable {
    var name = ""
    var shop = ""
    var photo: Data?
    var paid: Int?

    var title: String { shop.isEmpty ? name : "\(name) · \(shop)" }
}

enum MealMoney {
    static var code: String { Locale.current.currency?.identifier ?? "AUD" }

    static func cents(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard value.range(of: #"^[0-9]{1,6}(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }

    static func input(_ cents: Int?) -> String {
        guard let cents else { return "" }
        return String(format: "%d.%02d", cents / 100, cents % 100)
    }

    static func display(_ cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: code))
    }
}

struct Dish: Codable, Identifiable {
    var id = UUID()
    var name = ""
    var shops: [String] = []
    var cover: Data?
    var prices: [String: Int]?
}

struct Done: Codable, Identifiable {
    var id = UUID()
    var item: Item
    var date: Date
    var energy: MealEnergy?
    var meal: MealDetails?
}

enum DayPlace: String, Codable, CaseIterable, Identifiable {
    case outside = "出门"
    case home = "呆在家"

    var id: String { rawValue }
    var icon: String { self == .outside ? "figure.walk" : "house" }
}

struct DayPlaceSelection: Codable {
    var date: Date
    var place: DayPlace
    var outingID: UUID?
}

struct LocalData: Codable {
    var items: [Item] = []
    var history: [Done] = []
    var activities: [Activity] = []
    var dishes: [Dish] = []
    var pantry = ""
    var overview = false
    var overviewTime = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    var outingNudge = true
    var outingDays = 3
    var studyMinutes = 45
    var examples = true
    var created = Date()
    var expandedActivities: Bool?
    var bedtime: Bedtime?
    var privateNotes: [PrivateNote]?
    var notesLocked: Bool?
    var theme: String?
    var weatherCity: WeatherCity?
    var mealLimit: Int?
    var dailyMealLimit: Int?
    var dayPlace: DayPlaceSelection?

    func place(on day: Date) -> DayPlace? {
        guard let dayPlace, calendar.isDate(dayPlace.date, inSameDayAs: day) else { return nil }
        return dayPlace.place
    }

    mutating func selectPlace(_ place: DayPlace, at date: Date = .now) {
        let sameDay = dayPlace.map { calendar.isDate($0.date, inSameDayAs: date) } ?? false
        if sameDay && dayPlace?.place == place { return }

        if sameDay, let outingID = dayPlace?.outingID {
            history.removeAll { $0.id == outingID }
        }
        var selection = DayPlaceSelection(date: date, place: place)
        if place == .outside {
            let record = Done(item: Item(title: "出门走走", kind: .outing, date: date, minutes: 10), date: date)
            history.append(record)
            selection.outingID = record.id
        }
        dayPlace = selection
    }

    func mealSpending(on day: Date) -> Int {
        history.reduce(0) { total, entry in
            guard entry.item.kind == .meal, calendar.isDate(entry.date, inSameDayAs: day) else { return total }
            return total + (entry.meal?.paid ?? 0)
        }
    }

    func remainingMealBudget(on day: Date) -> Int? {
        let daily = dailyMealLimit.map { max(0, $0 - mealSpending(on: day)) }
        return [mealLimit, daily].compactMap { $0 }.min()
    }

    mutating func expandActivityLibrary() {
        guard expandedActivities != true else { return }
        var names = Set(activities.map(\.name))
        activities += Activity.additions.filter { names.insert($0.name).inserted }
        expandedActivities = true
    }

    static func sample(now: Date = Date()) -> Self {
        var data = Self()
        data.created = now
        let gap: TimeInterval = 45 * 60
        data.items = [
            Item(title: "设计课 · 小组讨论", kind: .routine, date: now.addingTimeInterval(gap), minutes: 45, example: true),
            Item(title: "英语测验", kind: .exam, date: calendar.date(byAdding: .day, value: 4, to: now) ?? now, minutes: 60, example: true),
            Item(title: "背 5 个单词", kind: .habit, date: now, minutes: 5, timed: false, example: true),
            Item(title: "整理课件", kind: .task, date: now, minutes: 20, timed: false, example: true)
        ]
        data.activities = [
            Activity(name: "喝杯咖啡", emoji: "☕", minutes: 30, outside: false),
            Activity(name: "去游泳", emoji: "🏊", minutes: 60, outside: true),
            Activity(name: "吃顿早午餐", emoji: "🥐", minutes: 60, outside: true),
            Activity(name: "跟朋友聊天", emoji: "💬", minutes: 20, outside: false),
            Activity(name: "去健身", emoji: "🏋️", minutes: 45, outside: true),
            Activity(name: "打游戏", emoji: "🎮", minutes: 30, outside: false)
        ]
        data.expandActivityLibrary()
        data.dishes = [
            Dish(name: "越南牛肉河粉", shops: ["示例 · 小河越南粉", "示例 · 西街河粉"]),
            Dish(name: "照烧鸡饭", shops: ["示例 · 木禾食堂"]),
            Dish(name: "番茄牛腩面", shops: ["示例 · 巷口面馆"])
        ]
        return data
    }

    func completed(_ item: Item) -> Bool {
        let original = items.first { $0.id == (item.taskID ?? item.id) } ?? item
        let sourceID = item.taskID ?? item.id
        let repeats = original.repeatRule != .once || (original.kind == .habit && !original.timed)
        return history.contains { record in
            let sameSource = (record.item.taskID ?? record.item.id) == sourceID
            return sameSource && (!repeats || calendar.isDate(record.item.date, inSameDayAs: item.date))
        }
    }

    mutating func finish(_ item: Item, at date: Date = Date(), energy: MealEnergy? = nil, meal: MealDetails? = nil) {
        guard !completed(item) else { return }
        history.append(Done(item: item, date: date, energy: energy, meal: meal))
    }

    mutating func save(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    mutating func scheduleAgain(_ record: Done, at date: Date = Date()) {
        var copy = record.item
        copy.id = UUID()
        copy.date = date
        copy.timed = true
        copy.repeatRule = .once
        copy.alert = false
        copy.examID = nil
        copy.taskID = nil
        items.append(copy)
    }
}

struct WeatherCity: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let admin1: String?
    let country: String?

    var region: String { [admin1, country].compactMap { $0 }.joined(separator: " · ") }
}
