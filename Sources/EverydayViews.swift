import SwiftUI
import UIKit
import LocalAuthentication

struct ActivityDetail: View {
    @EnvironmentObject var store: TodayStore
    @Environment(\.dismiss) private var dismiss
    var activity: Activity
    @State private var outsideOverride: Bool?
    @State private var placeName = ""

    private var outside: Bool { outsideOverride ?? activity.outside }

    private var place: String {
        let name = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? (outside ? "出门" : "在家") : name
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("活动", value: "\(activity.emoji) \(activity.name)")
                LabeledContent("用时", value: "\(activity.minutes) 分钟")
                Picker("这次的地点", selection: Binding(get: { outside }, set: { outsideOverride = $0 })) {
                    Text("在家").tag(false)
                    Text("出门").tag(true)
                }
                TextField("具体地点（选填）", text: $placeName)
            }
            Section {
                Button("加到今日日程") {
                    let now = Date()
                    let end = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: now) ?? now
                    guard let slot = Planner.slot(minutes: activity.minutes, from: now, until: end, around: store.busy(on: now)) else {
                        store.notice = "今天没有足够的空档。可以在日程中手动添加。"
                        return
                    }
                    store.save(Item(title: activity.name, kind: .activity, date: slot, minutes: activity.minutes, requiresOuting: outside, activityLocation: place))
                    store.notice = "已加到今天 \(time(slot))。"
                    dismiss()
                }
                ShareLink(item: "\(activity.emoji) \(activity.name) · \(activity.minutes) 分钟 · \(place)") {
                    Label("发给朋友", systemImage: "square.and.arrow.up")
                }
                Button("做完了") {
                    store.finish(Item(title: activity.name, kind: .activity, minutes: activity.minutes, requiresOuting: outside, activityLocation: place))
                    store.notice = "已记入历史。"
                    dismiss()
                }
            }
        }.navigationTitle(activity.name)
    }
}

struct ActivityDraw: View {
    @EnvironmentObject var store: TodayStore
    @Environment(\.dismiss) private var dismiss
    @State private var place = 0
    @State private var available = 60
    @State private var includeTasks = true
    @State private var activity: Activity?
    @State private var task: Item?
    @State private var drew = false

    var body: some View {
        Form {
            Section("现在的空档") {
                Picker("地点", selection: $place) {
                    Text("都可以").tag(0)
                    Text("在家").tag(1)
                    Text("出门").tag(2)
                }.pickerStyle(.segmented)
                Stepper("最多 \(available) 分钟", value: $available, in: 5...240, step: 5)
                Toggle("也抽「有空再做」", isOn: $includeTasks)
                Button(drew ? "再抽一签" : "抽一签") { draw() }
            }
            if let activity {
                NavigationLink { ActivityDetail(activity: activity) } label: {
                    Label("\(activity.emoji) \(activity.name) · \(activity.minutes) 分钟", systemImage: "sparkles")
                }
            } else if let task {
                Section {
                    ScheduleLabel(item: task, detail: "\(task.minutes) 分钟 · 有空再做")
                    Button("完成并记入历史") {
                        store.finish(task)
                        store.notice = "已记入历史。"
                        dismiss()
                    }
                }
            } else if drew {
                Text("没有符合条件的项目，试试增加空闲时长。").foregroundStyle(muted)
            }
        }
        .navigationTitle("抽一签")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        .onChange(of: place) { _, _ in reset() }
        .onChange(of: available) { _, _ in reset() }
        .onChange(of: includeTasks) { _, _ in reset() }
    }

    private func reset() { activity = nil; task = nil; drew = false }

    private func draw() {
        let activities = store.data.activities.filter { $0.minutes <= available && (place == 0 || $0.outside == (place == 2)) }
        let tasks = includeTasks && place != 2 ? store.data.items.filter {
            $0.kind == .task && $0.workflow == .later && $0.minutes <= available && !store.data.completed($0)
        } : []
        let ids = activities.map(\.id) + tasks.map(\.id)
        let alternatives = ids.filter { $0 != activity?.id && $0 != task?.id }
        let choice = alternatives.randomElement() ?? ids.first
        activity = activities.first { $0.id == choice }
        task = tasks.first { $0.id == choice }
        drew = true
    }
}

struct HabitsView: View {
    @EnvironmentObject var store: TodayStore
    @State private var editing: Item?

    var body: some View {
        List {
            Section("小习惯") {
                let habits = store.data.items.filter { [.habit, .water, .medicine].contains($0.kind) }
                if habits.isEmpty { Text("添加一件每天想做的小事。").foregroundStyle(muted) }
                ForEach(habits) { item in
                    let occurrence = item.occurrence(on: .now) ?? item
                    let canFinish = !item.timed || item.occurrence(on: .now) != nil
                    let done = item.timed ? store.data.completed(occurrence) : store.data.history.contains {
                        $0.item.id == item.id && calendar.isDateInToday($0.date)
                    }
                    HStack {
                        Button { editing = item } label: {
                            ScheduleLabel(item: item, detail: item.timed ? "\(item.repeatRule.rawValue) · \(time(item.date))" : "\(item.minutes) 分钟 · 随每日总览")
                        }.buttonStyle(.plain)
                        Spacer()
                        if done {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("已完成")
                        } else if canFinish {
                            Button(item.kind.completion) {
                                var record = occurrence
                                if !item.timed { record.date = .now; record.repeatRule = .daily }
                                store.finish(record)
                            }.buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .navigationTitle("每天做一点")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("新增小习惯") { editing = Item(kind: .habit, minutes: 5, timed: false) }
                    Button("新增喝水提醒") { editing = newReminder("喝杯水", kind: .water) }
                    Button("新增吃药提醒") { editing = newReminder("吃药", kind: .medicine) }
                } label: { Label("添加习惯", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { item in NavigationStack { ItemEditor(item: item) } }
    }

    private func newReminder(_ title: String, kind: Kind) -> Item {
        Item(title: title, kind: kind, date: .now.addingTimeInterval(300), minutes: 1, repeatRule: .daily, alert: true)
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: TodayStore
    @State private var date = Date()
    @State private var filter = false
    @State private var backfill = false
    @State private var outing = Date()

    var body: some View {
        List {
            Section {
                Toggle("按日期查看", isOn: $filter)
                if filter { DatePicker("日期", selection: $date, displayedComponents: .date) }
            }
            let energyDay = filter ? date : Date()
            let meals = store.data.history.filter { $0.item.kind == .meal && calendar.isDate($0.date, inSameDayAs: energyDay) }
            let enteredEnergy = meals.compactMap(\.energy)
            if !meals.isEmpty {
                Section(filter ? "所选日期 · 餐食热量" : "今日餐食热量") {
                    if !enteredEnergy.isEmpty {
                        Text("已记录 \(enteredEnergy.reduce(0) { $0 + $1.kilocalories }) 千卡")
                            .font(.headline)
                    }
                    Text("\(enteredEnergy.count) / \(meals.count) 餐填写了热量")
                        .font(.footnote).foregroundStyle(muted)
                }
            }
            Section("做过的事") {
                let records = store.data.history.filter { !filter || calendar.isDate($0.date, inSameDayAs: date) }
                    .sorted { $0.date > $1.date }
                if records.isEmpty { Text("完成的事会出现在这里。").foregroundStyle(muted) }
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 7) {
                        ScheduleLabel(item: record.item, detail: record.date.formatted(.dateTime.month().day().hour().minute()))
                        if let meal = record.meal {
                            if let paid = meal.paid {
                                Text("实际花费 " + MealMoney.display(paid)).font(.footnote).foregroundStyle(muted)
                            }
                            MealPhoto(data: meal.photo)
                        }
                        if let energy = record.energy {
                            Text((energy.estimated ? "估算 " : "") + "\(energy.kilocalories) 千卡 · \(energy.portion)")
                                .font(.footnote).foregroundStyle(muted)
                        }
                        Button("再加到今天") { repeatToday(record) }.font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(store.theme.base)
        .navigationTitle("历史")
        .toolbar { Button("补记出门") { outing = .now; backfill = true } }
        .sheet(isPresented: $backfill) {
            NavigationStack {
                Form {
                    DatePicker("出门时间", selection: $outing, in: ...Date())
                }
                .navigationTitle("补记出门")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { backfill = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("记录") {
                            store.data.finish(Item(title: "出门走走", kind: .outing, date: outing, minutes: 10), at: outing)
                            Task { await store.syncNotifications() }
                            backfill = false
                        }
                    }
                }
            }
        }
    }

    private func repeatToday(_ record: Done) {
        let now = Date()
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: now) ?? now
        guard let date = Planner.slot(minutes: record.item.minutes, from: now, until: end, around: store.busy(on: now)) else {
            store.notice = "今天没有足够的空档。可在日程中手动添加。"
            return
        }
        store.data.scheduleAgain(record, at: date)
        store.notice = "已加到今天 \(time(date))。"
    }
}

struct FoodView: View {
    @EnvironmentObject var store: TodayStore
    @State private var selection: UUID?
    @State private var shop = ""
    @State private var pantry = ""
    @State private var pantryLoaded = false
    @State private var cook = false
    @State private var finished = false
    @State private var mealToLog: MealDraft?

    struct MealDraft: Identifiable {
        var id = UUID()
        var meal = MealDetails()
        var drawn = false
        var example = false
    }

    var body: some View {
        List {
            Picker("用餐方式", selection: $cook) {
                Text("抽外卖").tag(false)
                Text("自己做").tag(true)
            }.pickerStyle(.segmented)
            if cook { homeCooking } else { takeout }
        }
        .scrollContentBackground(.hidden)
        .background(store.theme.base)
        .navigationTitle("吃什么")
        .toolbar {
            Button { mealToLog = MealDraft() } label: { Label("记录一餐", systemImage: "plus.circle") }
        }
        .sheet(item: $mealToLog) { draft in
            NavigationStack {
                MealLogView(meal: draft.meal) { meal, energy in
                    let isExample = draft.example && draft.meal.shop == meal.shop
                    store.finish(Item(title: meal.title, kind: .meal, minutes: 30, example: isExample), energy: energy, meal: meal)
                    if draft.drawn { finished = true }
                }
            }
        }
        .onAppear {
            guard !pantryLoaded else { return }
            pantry = store.data.pantry
            pantryLoaded = true
        }
    }

    private var budget: Int? { store.data.remainingMealBudget(on: .now) }

    private var availableDishes: [Dish] {
        store.data.dishes.filter { !availableShops(for: $0).isEmpty }
    }

    private func availableShops(for dish: Dish) -> [String] {
        let shops = dish.shops.isEmpty ? [""] : dish.shops
        guard let budget else { return shops }
        return shops.filter { name in dish.prices?[name].map { $0 <= budget } ?? false }
    }

    private var takeout: some View {
        Group {
            Section {
                NavigationLink { MealBudgetView() } label: {
                    LabeledContent("餐费预算", value: budget.map(MealMoney.display) ?? "不限")
                }
            }
            Section("抽外卖") {
                if let dish = availableDishes.first(where: { $0.id == selection }), availableShops(for: dish).contains(shop) {
                    VStack(alignment: .leading, spacing: 8) {
                        MealPhoto(data: dish.cover)
                        Text(dish.name).font(.title2.weight(.bold)).foregroundStyle(ink)
                        if !shop.isEmpty { Text(shop).font(.subheadline).foregroundStyle(muted) }
                        Text(dish.prices?[shop].map { "预计 " + MealMoney.display($0) } ?? "价格未知")
                            .font(.caption).foregroundStyle(muted)
                    }
                    Button(finished ? "已记入历史" : "就吃这个 · 记入历史") {
                        mealToLog = MealDraft(meal: MealDetails(name: dish.name, shop: shop), drawn: true,
                                              example: shop.hasPrefix("示例 · "))
                    }.disabled(finished)
                    if availableDishes.count > 1 { Button("换道菜") { draw() } }
                    if availableShops(for: dish).count > 1 {
                        Button("换家店") {
                            shop = availableShops(for: dish).filter { $0 != shop }.randomElement() ?? shop
                            finished = false
                        }
                    }
                    ShareLink(item: MealDetails(name: dish.name, shop: shop).title) {
                        Label("发给朋友", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button("抽一道菜") { draw() }.disabled(availableDishes.isEmpty)
                    if availableDishes.isEmpty {
                        Text(budget == nil ? "先收藏一道菜，就能开始抽。" : "没有已标价且符合预算的外卖。可以补填价格，或看看「自己做」。")
                            .foregroundStyle(muted)
                    }
                }
                NavigationLink("外卖收藏") { DishLibrary() }
            }
        }
    }

    private var homeCooking: some View {
        let recipes = Recipe.recommendations(from: pantry, limit: 12)
        let hasIngredients = !Recipe.availableIngredients(in: pantry).isEmpty
        return Group {
            Section("冰箱里的食材") {
                TextField("例如 鸡蛋、卤牛肉、面条", text: $pantry, axis: .vertical)
                Button("保存食材") { store.data.pantry = pantry }
                    .disabled(pantry == store.data.pantry)
            }
            Section {
                if !hasIngredients {
                    Text("输入食材后就会显示能做的菜。食材可以用空格、顿号或换行分开。")
                        .foregroundStyle(muted)
                } else if recipes.isEmpty {
                    Text("按这些食材暂时没找到能直接做的菜。可以再补充几样你手边已有的食材。")
                        .foregroundStyle(muted)
                }
                ForEach(recipes) { recipe in
                    NavigationLink {
                        RecipeDetail(recipe: recipe)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(recipe.name).font(.headline)
                            Text("\(recipe.minutes) 分钟 · " + recipe.ingredients.joined(separator: "、"))
                                .font(.caption).foregroundStyle(muted)
                        }
                    }
                }
            } header: {
                Text("用现有食材可以做")
            } footer: {
                if !recipes.isEmpty { Text("默认可用清水。需要用油等调料的菜，会在你填入后才推荐。") }
            }
        }
    }

    private func draw() {
        let list = availableDishes
        guard let dish = list.filter({ $0.id != selection }).randomElement() ?? list.first else { return }
        selection = dish.id
        shop = availableShops(for: dish).randomElement() ?? ""
        finished = false
    }
}

struct RecipeDetail: View {
    @EnvironmentObject var store: TodayStore
    @State private var logged = false
    @State private var logging = false
    var recipe: Recipe

    var body: some View {
        List {
            Section("食材 · \(recipe.minutes) 分钟") {
                ForEach(recipe.ingredients, id: \.self) { ingredient in
                    LabeledContent(ingredient, value: "已有")
                }
            }
            Section("做法") {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                }
            }
            Button(logged ? "已记入历史" : "做过了") {
                logging = true
            }.disabled(logged)
        }
        .navigationTitle(recipe.name)
        .sheet(isPresented: $logging) {
            NavigationStack {
                MealLogView(meal: MealDetails(name: recipe.name), ingredients: recipe.ingredients) { meal, energy in
                    store.finish(Item(title: meal.title, kind: .meal, minutes: recipe.minutes), energy: energy, meal: meal)
                    logged = true
                }
            }
        }
    }
}

struct DishLibrary: View {
    @EnvironmentObject var store: TodayStore
    @State private var edit: Dish?

    var body: some View {
        List {
            ForEach(store.data.dishes) { dish in
                Button { edit = dish } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        MealPhoto(data: dish.cover, height: 100)
                        Text(dish.name).font(.headline)
                        Text(dish.shops.isEmpty ? "未添加店名" : dish.shops.joined(separator: "、"))
                            .font(.caption).foregroundStyle(muted)
                    }
                }
            }
            .onDelete { store.data.dishes.remove(atOffsets: $0) }
        }
        .navigationTitle("外卖收藏")
        .toolbar { Button { edit = Dish() } label: { Label("收藏一道菜", systemImage: "plus") } }
        .sheet(item: $edit) { dish in NavigationStack { DishEditor(dish: dish, shops: dish.shops.joined(separator: "\n")) } }
    }
}

struct DishEditor: View {
    @EnvironmentObject var store: TodayStore
    @Environment(\.dismiss) private var dismiss
    @State var dish: Dish
    @State var shops: String
    @State private var prices: [String: String] = [:]

    private var shopNames: [String] {
        var seen = Set<String>()
        return shops.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var priceKeys: [String] { shopNames.isEmpty ? [""] : shopNames }

    var body: some View {
        Form {
            TextField("菜名", text: $dish.name)
            Section("每行写一家店") { TextEditor(text: $shops).frame(minHeight: 80) }
            Section {
                ForEach(priceKeys, id: \.self) { key in
                    TextField(key.isEmpty ? "预计实付（\(MealMoney.code)）" : key, text: Binding(
                        get: { prices[key] ?? "" }, set: { prices[key] = $0 }))
                        .keyboardType(.decimalPad)
                }
            } header: {
                Text("预计实付（\(MealMoney.code)）")
            } footer: {
                Text("可填含配送费的预计金额，作为预算筛选依据。")
            }
            MealPhotoEditor(photo: $dish.cover)
        }
        .navigationTitle("编辑收藏")
        .onAppear {
            if prices.isEmpty { prices = (dish.prices ?? [:]).mapValues { MealMoney.input($0) } }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    dish.name = dish.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    dish.shops = shopNames
                    dish.prices = Dictionary(uniqueKeysWithValues: priceKeys.compactMap { key in
                        MealMoney.cents(prices[key] ?? "").map { (key, $0) }
                    })
                    if let index = store.data.dishes.firstIndex(where: { $0.id == dish.id }) { store.data.dishes[index] = dish }
                    else { store.data.dishes.append(dish) }
                    dismiss()
                }
                .disabled(dish.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          priceKeys.contains { key in
                              let value = prices[key] ?? ""
                              return !value.isEmpty && MealMoney.cents(value) == nil
                          })
            }
        }
    }
}

struct MealBudgetView: View {
    @EnvironmentObject private var store: TodayStore
    @Environment(\.dismiss) private var dismiss
    @State private var daily = ""
    @State private var perMeal = ""

    var body: some View {
        Form {
            Section {
                TextField("这顿最多花多少", text: $perMeal).keyboardType(.decimalPad)
                TextField("每日餐费预算", text: $daily).keyboardType(.decimalPad)
                LabeledContent("今天已记实付", value: MealMoney.display(store.data.mealSpending(on: .now)))
            } header: {
                Text("金额（\(MealMoney.code)）")
            } footer: {
                Text("可只设一项。两项都设时，按这顿上限与今日剩余预算中较低的金额筛选。留空表示不限。")
            }
        }
        .navigationTitle("餐费预算")
        .onAppear {
            daily = MealMoney.input(store.data.dailyMealLimit)
            perMeal = MealMoney.input(store.data.mealLimit)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    store.data.dailyMealLimit = MealMoney.cents(daily)
                    store.data.mealLimit = MealMoney.cents(perMeal)
                    dismiss()
                }.disabled([daily, perMeal].contains { !$0.isEmpty && MealMoney.cents($0) == nil })
            }
        }
    }
}

struct ActivityLibrary: View {
    @EnvironmentObject var store: TodayStore
    @State private var edit: Activity?

    var body: some View {
        List {
            ForEach(store.data.activities) { activity in
                Button { edit = activity } label: {
                    LabeledContent("\(activity.emoji) \(activity.name)", value: "\(activity.minutes) 分钟")
                }
            }.onDelete { store.data.activities.remove(atOffsets: $0) }
        }
        .navigationTitle("活动库")
        .toolbar { Button { edit = Activity() } label: { Label("添加活动", systemImage: "plus") } }
        .sheet(item: $edit) { activity in NavigationStack { ActivityEditor(activity: activity) } }
    }
}

struct ActivityEditor: View {
    @EnvironmentObject var store: TodayStore
    @Environment(\.dismiss) private var dismiss
    @State var activity: Activity

    var body: some View {
        Form {
            TextField("活动名称", text: $activity.name)
            TextField("表情图标", text: $activity.emoji)
            Toggle("需要出门", isOn: $activity.outside)
            Stepper("\(activity.minutes) 分钟", value: $activity.minutes, in: 5...240, step: 5)
        }
        .navigationTitle("编辑活动")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    activity.name = activity.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    activity.emoji = activity.emoji.first.map(String.init) ?? "✨"
                    if let index = store.data.activities.firstIndex(where: { $0.id == activity.id }) { store.data.activities[index] = activity }
                    else { store.data.activities.append(activity) }
                    dismiss()
                }.disabled(activity.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: TodayStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section("外观与天气") {
                NavigationLink("外观主题") { AppearanceView() }
                NavigationLink("今日天气") { WeatherCityView() }
            }
            Section("每日提醒") {
                Toggle("每日总览", isOn: $store.data.overview)
                if store.data.overview {
                    DatePicker("提醒时间", selection: $store.data.overviewTime, displayedComponents: .hourAndMinute)
                    Toggle("出门小提醒", isOn: $store.data.outingNudge)
                    if store.data.outingNudge { Stepper("连续 \(store.data.outingDays) 天没出门", value: $store.data.outingDays, in: 1...30) }
                }
                if !store.notificationsAllowed {
                    Button("开启通知权限") { Task { await store.authorizeNotifications() } }
                    Text("通知权限未开启，仍可在 App 内查看并确认。").font(.footnote).foregroundStyle(muted)
                }
                NavigationLink("管理小习惯、喝水和吃药") { HabitsView() }
            }
            Section {
                Toggle("每天提醒睡觉", isOn: bedtimeBinding.enabled)
                if bedtime.enabled {
                    DatePicker("计划睡觉时间", selection: bedtimeBinding.time, displayedComponents: .hourAndMinute)
                    ForEach([15, 10, 0], id: \.self) { offset in
                        Toggle(bedtimeLabel(offset), isOn: offset == 15 ? bedtimeBinding.before15 :
                                offset == 10 ? bedtimeBinding.before10 : bedtimeBinding.atTime)
                    }
                }
            } header: {
                Text("睡前提醒")
            } footer: {
                Text(store.notificationsAllowed ? "每天按所选时间提醒。" : "请先开启上方的通知权限。")
            }
            Section("日历与复习") {
                LabeledContent("iPhone 日历", value: store.calendarAllowed ? "已连接" : "未连接")
                if !store.calendarAllowed { Button("连接 iPhone 日历") { Task { await store.authorizeCalendar() } } }
                Stepper("每天复习 \(store.data.studyMinutes) 分钟", value: $store.data.studyMinutes, in: 15...180, step: 5)
                Button("打开 iPhone 权限设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Section("我的清单") {
                NavigationLink("活动库") { ActivityLibrary() }
                NavigationLink("外卖收藏") { DishLibrary() }
                NavigationLink("待办清单") { TaskListView() }
            }
            if store.data.examples {
                Section("首次体验") {
                    Text("标有「示例」的日程和店名可清除。内置活动和菜名仍可编辑。").font(.footnote)
                    Button("清除示例", role: .destructive) {
                        let ids = Set(store.data.items.filter(\.example).map(\.id))
                        store.data.items.removeAll { $0.example || $0.examID.map(ids.contains) == true || $0.taskID.map(ids.contains) == true }
                        for index in store.data.dishes.indices { store.data.dishes[index].shops.removeAll { $0.hasPrefix("示例 · ") } }
                        store.data.examples = false
                        Task { await store.syncNotifications() }
                    }
                }
            }
        }
        .navigationTitle("设置")
        .onChange(of: store.data.overview) { _, _ in sync() }
        .onChange(of: store.data.overviewTime) { _, _ in sync() }
        .onChange(of: store.data.outingNudge) { _, _ in sync() }
        .onChange(of: store.data.outingDays) { _, _ in sync() }
    }

    private var bedtime: Bedtime { store.data.bedtime ?? Bedtime() }

    private var bedtimeBinding: Binding<Bedtime> {
        Binding(get: { bedtime }, set: { value in
            store.data.bedtime = value
            Task { await store.syncNotifications() }
        })
    }

    private func bedtimeLabel(_ offset: Int) -> String {
        let label = offset == 0 ? "到点" : "提前 \(offset) 分钟"
        let parts = bedtime.clockComponents(minutesBefore: offset)
        return label + " · " + String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private func sync() {
        store.clearOverviewSnooze()
        Task { await store.syncNotifications() }
    }
}

struct MealLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State var meal: MealDetails
    var ingredients: [String] = []
    var onSave: (MealDetails, MealEnergy?) -> Void
    @State private var price = ""
    @State private var kilocalories = ""
    @State private var portion = "1 份"
    @State private var portions = 1
    @State private var calculate = false
    @State private var amounts: [IngredientAmount] = []

    struct IngredientAmount: Identifiable {
        var id = UUID()
        var name: String
        var grams = ""
        var energy = ""
    }

    var body: some View {
        Form {
            Section("餐食") {
                TextField("菜名", text: $meal.name)
                TextField("店名或地点（选填）", text: $meal.shop)
                TextField("实际花费（\(MealMoney.code)，选填）", text: $price).keyboardType(.decimalPad)
            }
            MealPhotoEditor(photo: $meal.photo)
            if !ingredients.isEmpty {
                Toggle("按食材用量估算", isOn: $calculate)
            }
            if calculate {
                Section {
                    Stepper("整道菜分成 \(portions) 份", value: $portions, in: 1...30)
                    ForEach($amounts) { $amount in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("食材名称", text: $amount.name).font(.headline)
                            TextField("整道菜用了多少克", text: $amount.grams)
                                .keyboardType(.decimalPad)
                            TextField("每 100 克的热量（千卡）", text: $amount.energy)
                                .keyboardType(.decimalPad)
                        }
                    }
                    .onDelete { amounts.remove(atOffsets: $0) }
                    Button("添加调料或其他食材") { amounts.append(IngredientAmount(name: "")) }
                } header: {
                    Text("按包装上的热量填写")
                } footer: {
                    Text("填写整道菜的食材克数，记入历史的是其中一份的估算值。实际吃了更多或更少时，可关掉估算并手填。")
                }
                if let value = energy {
                    LabeledContent("每份约", value: "\(value.kilocalories) 千卡")
                }
            } else {
                Section {
                    TextField("份量，例如 半碗", text: $portion)
                    TextField("这餐的热量（千卡）", text: $kilocalories).keyboardType(.numberPad)
                } footer: {
                    Text("可填写商家或包装标注的热量。")
                }
            }
            if !kilocalories.isEmpty && !calculate && energy == nil {
                Text("请输入有效的热量，或清空后跳过。").font(.footnote).foregroundStyle(muted)
            }
        }
        .navigationTitle("记录这餐")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save(energy)
                }.disabled(meal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            (!price.isEmpty && MealMoney.cents(price) == nil) ||
                            ((calculate || !kilocalories.isEmpty) && energy == nil))
            }
        }
        .onAppear {
            if amounts.isEmpty { amounts = ingredients.map { IngredientAmount(name: $0) } }
        }
    }

    private var energy: MealEnergy? {
        if calculate {
            let parts = amounts.compactMap { amount -> (grams: Double, per100g: Double)? in
                guard !amount.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let grams = decimal(amount.grams), let energy = decimal(amount.energy) else { return nil }
                return (grams, energy)
            }
            guard parts.count == amounts.count,
                  let result = MealEnergy.estimate(parts: parts, portions: Double(portions)) else { return nil }
            return MealEnergy(kilocalories: result, estimated: true, portion: "1 份")
        }
        guard let input = Int(kilocalories.trimmingCharacters(in: .whitespaces)), (0...100_000).contains(input) else { return nil }
        let label = portion.trimmingCharacters(in: .whitespacesAndNewlines)
        return MealEnergy(kilocalories: input, estimated: false, portion: label.isEmpty ? "1 份" : label)
    }

    private func decimal(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private func save(_ energy: MealEnergy?) {
        meal.name = meal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        meal.shop = meal.shop.trimmingCharacters(in: .whitespacesAndNewlines)
        meal.paid = MealMoney.cents(price)
        onSave(meal, energy)
        dismiss()
    }
}

struct PrivateNotesView: View {
    @EnvironmentObject private var store: TodayStore
    @Environment(\.scenePhase) private var phase
    @State private var unlocked = false
    @State private var authentication: LAContext?
    @State private var error = ""
    @State private var draft: PrivateNote?
    @State private var deletion: PrivateNote?

    private var locked: Bool { store.data.notesLocked == true }
    private var notes: [PrivateNote] { store.data.privateNotes ?? [] }

    var body: some View {
        Group {
            if phase != .active {
                cream.ignoresSafeArea().accessibilityHidden(true)
            } else if locked && !unlocked {
                VStack(spacing: 15) {
                    Image(systemName: "lock.fill").font(.largeTitle).accessibilityHidden(true)
                    Text("碎碎念已上锁").font(.headline)
                    Button("验证后打开") { authenticate { unlocked = true } }
                        .buttonStyle(.borderedProminent)
                        .disabled(authentication != nil)
                    if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(muted) }
                }
                .padding()
            } else if let note = draft {
                editor(note)
            } else {
                noteList
            }
        }
        .navigationTitle("碎碎念")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: phase) { _, next in
            if next == .background {
                unlocked = false
                authentication?.invalidate()
                authentication = nil
                deletion = nil
            }
        }
        .alert("删除这条碎碎念？", isPresented: Binding(
            get: { deletion != nil && phase == .active && (!locked || unlocked) },
            set: { if !$0 { deletion = nil } }
        ), presenting: deletion) { note in
            Button("删除", role: .destructive) {
                store.data.privateNotes = notes.filter { $0.id != note.id }
                deletion = nil
            }
            Button("取消", role: .cancel) { deletion = nil }
        }
    }

    private var noteList: some View {
        List {
            Section {
                Button {
                    authenticate {
                        let enable = !locked
                        unlocked = false
                        store.data.notesLocked = enable
                    }
                } label: {
                    Label(locked ? "关闭 Face ID 锁" : "开启 Face ID 锁", systemImage: "faceid")
                }
                .disabled(authentication != nil)
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(muted) }
            } footer: {
                Text("内容保存在 App 本地，不会显示在通知里。开启锁后可用 Face ID 或设备密码验证。")
            }
            Section {
                if notes.isEmpty { Text("有想说的话，可以先写一条。").foregroundStyle(muted) }
                ForEach(notes.sorted { $0.created > $1.created }) { note in
                    Button { draft = note } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title.isEmpty ? note.body : note.title).lineLimit(1).font(.headline)
                            Text(note.created.formatted(.dateTime.month().day().hour().minute()))
                                .font(.caption).foregroundStyle(muted)
                        }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) { deletion = note }
                    }
                }
            } header: {
                Text("仅自己可见")
            }
        }
        .toolbar {
            Button { draft = PrivateNote() } label: { Label("写一条", systemImage: "square.and.pencil") }
        }
    }

    private func editor(_ note: PrivateNote) -> some View {
        Form {
            TextField("标题（选填）", text: Binding(
                get: { draft?.title ?? "" }, set: { draft?.title = $0 }))
            TextField("想说点什么？", text: Binding(
                get: { draft?.body ?? "" }, set: { draft?.body = $0 }), axis: .vertical)
                .lineLimit(6...18)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { draft = nil } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    guard let current = draft else { return }
                    var updated = notes
                    if let index = updated.firstIndex(where: { $0.id == current.id }) { updated[index] = current }
                    else { updated.append(current) }
                    store.data.privateNotes = updated
                    draft = nil
                }
                .disabled(note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                          note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func authenticate(onSuccess: @escaping () -> Void) {
        guard authentication == nil else { return }
        let context = LAContext()
        let policy = LAPolicy.deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: nil) else {
            error = "设备验证暂不可用。请在系统设置启用设备密码或 Face ID 后再试。"
            return
        }
        error = ""
        authentication = context
        Task {
            defer { if authentication === context { authentication = nil } }
            do {
                if try await context.evaluatePolicy(policy, localizedReason: "保护你的碎碎念"),
                   authentication === context {
                    onSuccess()
                }
            } catch {
                guard authentication === context else { return }
                if let code = (error as? LAError)?.code,
                   [LAError.userCancel, .appCancel, .systemCancel].contains(code) { return }
                self.error = "验证未通过，请重试。"
            }
        }
    }
}
