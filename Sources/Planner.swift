import Foundation

enum Planner {
    static func slot(minutes: Int, from start: Date, until end: Date, around busy: [Item], padding: Int = 10) -> Date? {
        let duration = Double(minutes * 60)
        let margin = Double(padding * 60)
        var cursor = Date(timeIntervalSinceReferenceDate: ceil(start.timeIntervalSinceReferenceDate / 300) * 300)
        for item in busy.sorted(by: { $0.date < $1.date }) {
            if item.end.addingTimeInterval(margin) <= cursor { continue }
            if cursor.addingTimeInterval(duration) <= item.date.addingTimeInterval(-margin) { break }
            cursor = item.end.addingTimeInterval(margin)
        }
        return cursor.addingTimeInterval(duration) <= end ? cursor : nil
    }

    static func draft(now: Date, busy: [Item], data: LocalData, light: Bool) -> [Item] {
        let end = calendar.date(bySettingHour: 23, minute: 45, second: 0, of: now) ?? now
        let mealHour = calendar.component(.hour, from: now) < 14 ? 12 : 18
        let mealTime = calendar.date(bySettingHour: mealHour, minute: 0, second: 0, of: now) ?? now
        let habit = data.items.first { item in
            item.kind == .habit && !item.timed && !busy.contains { $0.taskID == item.id } &&
                !data.history.contains { $0.item.id == item.id && calendar.isDate($0.date, inSameDayAs: now) }
        }
        let exam = data.items.filter { $0.kind == .exam && $0.date > now }.min { $0.date < $1.date }
        let hasReview = busy.contains { $0.kind == .study }
        let alreadyPlannedToday = Set(busy.compactMap(\.taskID))
        let task = data.items.first { $0.kind == .task && !$0.timed && $0.workflow == .plan && !data.completed($0) && !alreadyPlannedToday.contains($0.id) }
        let activity = data.activities.first { !$0.outside } ?? data.activities.first
        var options: [Item] = []
        if !busy.contains(where: { $0.kind == .meal && $0.date >= now }) {
            options.append(Item(title: light ? "吃点喜欢的" : (mealHour == 12 ? "吃午饭" : "吃晚饭"), kind: .meal, date: max(now, mealTime), minutes: light ? 25 : 35))
        }
        if !light && !hasReview {
            options.append(Item(title: exam.map { "复习 · \($0.title)" } ?? "复习今天的笔记", kind: .study, date: now, minutes: data.studyMinutes, examID: exam?.id))
        }
        if let habit {
            options.append(Item(title: habit.title, kind: .habit, date: now, minutes: habit.minutes, taskID: habit.id, example: habit.example))
        }
        if let task, !light {
            options.append(Item(title: task.title, kind: .task, date: now, minutes: task.minutes, taskID: task.id, example: task.example))
        }
        options.append(Item(title: light ? "休息一下" : (activity?.name ?? "散散步"), kind: .activity, date: now, minutes: light ? 10 : (activity?.minutes ?? 20), requiresOuting: !light && (activity?.outside ?? true)))
        var result: [Item] = []
        for var item in options {
            if let start = slot(minutes: item.minutes, from: item.date, until: end, around: busy + result, padding: light || item.isOuting ? 15 : 10) {
                item.date = start
                result.append(item)
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    static func review(exam: Item, now: Date, minutes: Int, busy: (Date) -> [Item], limit: Int = 365, replacingMissed: Bool = false) -> [Item] {
        var result: [Item] = []
        for offset in 0..<limit {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  calendar.startOfDay(for: day) < exam.date else { break }
            let existing = busy(day)
            if !replacingMissed && existing.contains(where: { $0.examID == exam.id && $0.end > now }) { continue }
            let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            let evening = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: day) ?? day
            if let start = slot(minutes: minutes, from: max(morning, now), until: min(evening, exam.date.addingTimeInterval(-600)), around: existing) {
                result.append(Item(title: "复习 · \(exam.title)", kind: .study, date: start, minutes: minutes, examID: exam.id))
                if replacingMissed { break }
            }
        }
        return result
    }
}

struct Recipe: Identifiable {
    var id: String { name }
    var name: String
    var minutes: Int
    var ingredients: [String]
    var steps: [String]

    private static let aliases: [String: String] = [
        "西红柿": "番茄", "番茄仔": "番茄", "鸡子": "鸡蛋",
        "滷牛肉": "卤牛肉", "卤牛腱": "卤牛肉", "卤牛腱子": "卤牛肉",
        "挂面": "面条", "细面": "面条", "鲜面条": "面条", "宽面条": "面条",
        "香葱": "葱", "小葱": "葱", "剩饭": "米饭", "白米饭": "米饭", "燕麦片": "燕麦",
        "食用油": "油", "食盐": "盐", "小白菜": "青菜",
        "雞蛋": "鸡蛋", "生牛肉": "牛肉", "牛肉片": "牛肉", "牛肉丝": "牛肉",
        "牛肉末": "牛肉碎", "牛绞肉": "牛肉碎", "牛肉馅": "牛肉碎",
        "罗马生菜": "生菜", "球生菜": "生菜", "西生菜": "生菜",
        "蘑菇片": "蘑菇", "白蘑菇": "蘑菇", "口蘑": "蘑菇",
        "鸡胸": "鸡胸肉", "馬鈴薯": "土豆", "马铃薯": "土豆",
        "卷心菜": "包菜", "圆白菜": "包菜"
    ]

    static func availableIngredients(in pantry: String) -> Set<String> {
        let separators = ",，、;；/／。"
        return Set(pantry.split { $0.isWhitespace || separators.contains($0) }.map { piece in
            let name = String(piece)
            return aliases[name] ?? name
        })
    }

    static func recommendations(from pantry: String, limit: Int = 3) -> [Recipe] {
        let available = availableIngredients(in: pantry)
        var candidates = all + everydayRecipes
        if available.contains("面条") {
            candidates += noodleRecipes(using: available)
        }
        let staples: Set<String> = ["盐", "油", "生抽"]
        return Array(candidates
            .filter { available.isSuperset(of: $0.ingredients) }
            .sorted {
                let left = $0.ingredients.filter { !staples.contains($0) }.count
                let right = $1.ingredients.filter { !staples.contains($0) }.count
                return left == right ? $0.minutes < $1.minutes : left > right
            }
            .prefix(limit))
    }

    private static func noodleRecipes(using available: Set<String>) -> [Recipe] {
        let toppings: [(ingredient: String, name: String, step: String)] = [
            ("卤牛肉", "卤牛肉", "取约 80 克卤牛肉切薄片，放进面汤，煮到牛肉彻底热透。"),
            ("鸡蛋", "鸡蛋", "打入 1 个鸡蛋，小火煮到蛋白和蛋黄都凝固。"),
            ("青菜", "青菜", "取一小把青菜洗净，放进汤里煮熟。"),
            ("豆腐", "豆腐", "取约 100 克豆腐切小块，放进面汤中煮热。")
        ]
        let existing = toppings.filter { available.contains($0.ingredient) }
        var combinations = existing.map { [$0] }
        if existing.count >= 2 {
            combinations.append(Array(existing.prefix(3)))
        }
        return combinations.map { selection in
            Recipe(name: selection.map(\.name).joined() + "汤面",
                   minutes: 8 + selection.count * 2,
                   ingredients: ["面条"] + selection.map(\.ingredient),
                   steps: ["烧开约 500 毫升水，下 1 人份面条，按包装时间煮熟。面条先盛到碗里，锅里留汤。"]
                       + selection.map(\.step)
                       + ["把配料和热汤倒到面上。若用了卤牛肉，先尝一下汤，再决定是否调味。"])
        }
    }

    private static let all: [Self] = [
        Recipe(name: "卤牛肉鸡蛋盖饭", minutes: 12, ingredients: ["米饭", "卤牛肉", "鸡蛋"],
               steps: ["熟米饭 1 碗加热至整体冒热气；卤牛肉约 80 克切薄片。", "锅中加少量水煮开，放牛肉加热至热透，打入 1 个蛋，小火煮到蛋白蛋黄凝固。", "将牛肉和蛋放在饭上，可淋一点锅里的汁。"]),
        Recipe(name: "卤牛肉拌黄瓜", minutes: 10, ingredients: ["卤牛肉", "黄瓜"],
               steps: ["半根黄瓜洗净切片，用干净的刀和板把约 80 克卤牛肉切薄片。", "卤牛肉加热至热透，和黄瓜拌匀，可拌入少量卤汁。"]),
        Recipe(name: "卤牛肉番茄汤", minutes: 15, ingredients: ["卤牛肉", "番茄"],
               steps: ["番茄 1 个切块，加约 450 毫升水煮到软。", "约 80 克卤牛肉切薄片，下汤中煮至热透。先尝汤，再决定是否调味。"]),
        Recipe(name: "葱油拌面", minutes: 14, ingredients: ["面条", "葱", "油", "生抽"],
               steps: ["一把葱洗净擦干切段。1 人份面条按包装煮熟并沥水。", "锅内倒少量油，小火将葱炒香，关火后加入少量生抽。", "把葱油倒进面里，拌匀。"]),
        Recipe(name: "黄瓜鸡蛋拌面", minutes: 14, ingredients: ["面条", "黄瓜", "鸡蛋"],
               steps: ["鸡蛋 1 个煮至蛋黄完全凝固，去壳切开；半根黄瓜洗净切丝。", "煮熟一人份面条，沥水，拌入黄瓜丝和鸡蛋。手头有喜欢的调料可加少许。"]),
        Recipe(name: "番茄蛋花汤", minutes: 12, ingredients: ["番茄", "鸡蛋"],
               steps: ["1 个番茄切块，用约 450 毫升水煮软出汁。", "打散 1 个鸡蛋，边搅汤边倒入蛋液，煮到蛋花完全凝固。"]),
        Recipe(name: "青菜蛋花粥", minutes: 15, ingredients: ["米饭", "鸡蛋", "青菜"],
               steps: ["半碗熟米饭加 2 碗水煮开，小火煮到米粒软烂。", "一把青菜洗净切碎，放入粥里煮熟，再淋入 1 个打散的鸡蛋，煮到凝固。"]),
        Recipe(name: "豆腐蒸蛋", minutes: 18, ingredients: ["豆腐", "鸡蛋"],
               steps: ["约 100 克豆腐切小丁。2 个蛋打散，和约 130 毫升温水拌匀。", "豆腐放进耐热碗，倒入蛋液并盖盘，水开后蒸约 12 分钟。", "检查中间完全凝固后取出。"]),
        Recipe(name: "鸡蛋炒饭", minutes: 12, ingredients: ["米饭", "鸡蛋", "油"],
               steps: ["打散 1 个鸡蛋，准备 1 碗熟米饭。", "热锅倒少量油，下蛋炒到凝固，再下米饭炒散，炒到整锅热透。"]),
        Recipe(name: "番茄烩饭", minutes: 15, ingredients: ["米饭", "番茄"],
               steps: ["番茄 1 个切碎，加小半碗水煮软。", "加入一碗熟米饭拌匀，继续煮到米饭整体热透，收汁至喜欢的稠度。"]),
        Recipe(name: "紫菜蛋花汤", minutes: 10, ingredients: ["紫菜", "鸡蛋"],
               steps: ["烧开约 450 毫升水，放入一小把紫菜，按包装提示煮熟。", "1 个鸡蛋打散，淋入汤中，煮至蛋花完全凝固。"]),
        Recipe(name: "牛奶燕麦粥", minutes: 8, ingredients: ["牛奶", "燕麦"],
               steps: ["约 40 克燕麦加入约 220 毫升牛奶，小火加热。", "边煮边搅拌，燕麦煮到软稠即可。"]),
        Recipe(name: "番茄炒蛋", minutes: 12, ingredients: ["番茄", "鸡蛋", "油"],
               steps: ["1 个番茄切块，2 个鸡蛋打散。", "热锅倒少量油，把鸡蛋炒至凝固后盛出。", "番茄下锅炒出汁，倒回鸡蛋拌匀。"]),
        Recipe(name: "鸡蛋胡萝卜炒饭", minutes: 15, ingredients: ["米饭", "鸡蛋", "胡萝卜", "油"],
               steps: ["半根胡萝卜切小丁，1 个鸡蛋打散，准备 1 碗熟米饭。", "用少量油炒软胡萝卜，再下鸡蛋炒至凝固。", "加饭炒散，炒至整锅热透。"]),
        Recipe(name: "青菜豆腐汤", minutes: 12, ingredients: ["青菜", "豆腐"],
               steps: ["一把青菜洗净，约 150 克豆腐切块。", "烧开约 450 毫升水，放入豆腐煮约 5 分钟。", "放入青菜煮熟即可。"]),
        Recipe(name: "香蕉燕麦碗", minutes: 8, ingredients: ["香蕉", "燕麦", "牛奶"],
               steps: ["约 40 克燕麦和 200 毫升牛奶小火煮稠，中途搅拌。", "1 根香蕉切片，铺在燕麦上。"]),
        Recipe(name: "番茄鸡蛋面", minutes: 18, ingredients: ["面条", "番茄", "鸡蛋"],
               steps: ["1 个番茄切小块，加约 450 毫升水煮软。", "下 1 人份面条，按包装时间煮熟。", "淋入 1 个打散的鸡蛋。蛋液全部凝固后盛出。"]),
        Recipe(name: "蒸鸡蛋羹", minutes: 15, ingredients: ["鸡蛋"],
               steps: ["2 个鸡蛋打散，加约 150 毫升温水拌匀，撇去泡沫。", "蒸锅水开后，放入盖了耐热盘的蛋液碗，中小火蒸约 10 分钟。", "检查中间凝固后取出，避免被蒸汽烫到。"]),
        Recipe(name: "卤牛肉盖饭", minutes: 8, ingredients: ["卤牛肉", "米饭"],
               steps: ["把 1 碗熟米饭加热到整体冒热气。", "约 80 克卤牛肉切薄片，加少量水盖锅加热至热透。", "牛肉铺在饭上，淋一点锅里的汁。"]),
        Recipe(name: "卤牛肉蒸蛋", minutes: 16, ingredients: ["卤牛肉", "鸡蛋"],
               steps: ["约 60 克卤牛肉切碎，2 个鸡蛋打散后与约 140 毫升温水混匀。", "把蛋液倒入耐热碗，拌入牛肉，盖上耐热盘。", "水开后中小火蒸约 12 分钟，检查中间完全凝固、牛肉热透后取出。"]),
        Recipe(name: "鸡蛋粥", minutes: 12, ingredients: ["米饭", "鸡蛋"],
               steps: ["半碗熟米饭加 2 碗水煮开，小火煮到米粒软烂。", "慢慢倒入 1 个打散的鸡蛋，搅散。", "煮到蛋花完全凝固即可。"]),
        Recipe(name: "番茄豆腐汤", minutes: 13, ingredients: ["番茄", "豆腐"],
               steps: ["1 个番茄切小块，约 150 克豆腐切块。", "番茄和约 450 毫升水一起煮开，小火煮软。", "放入豆腐继续煮 5 分钟。"]),
        Recipe(name: "燕麦粥", minutes: 8, ingredients: ["燕麦"],
               steps: ["锅里放约 40 克燕麦和 220 毫升水。", "煮开后转小火，边煮边搅拌，煮到燕麦软稠。"])
    ]

    private static let everydayRecipes: [Self] = [
        Recipe(name: "生菜牛肉蛋花汤", minutes: 16, ingredients: ["生菜", "牛肉", "鸡蛋"],
               steps: ["生菜洗净撕开，牛肉约 100 克切薄片，1 个鸡蛋打散。", "烧开约 500 毫升水，放入牛肉片，保持微沸并煮熟。", "边搅汤边淋入蛋液，待蛋液完全凝固，加入生菜烫到软即可。"]),
        Recipe(name: "生菜牛肉汤", minutes: 14, ingredients: ["生菜", "牛肉"],
               steps: ["洗净一小碗生菜，撕成方便入口的大小；把约 100 克牛肉切薄。", "烧开约 500 毫升水，拨散牛肉片并煮熟。", "生菜入锅烫到变软，连汤盛出。"]),
        Recipe(name: "生菜蛋花汤", minutes: 10, ingredients: ["生菜", "鸡蛋"],
               steps: ["洗净一小把生菜，撕小片；打散 1 个鸡蛋。", "烧开约 450 毫升水，慢慢倒入蛋液，煮到蛋花完全凝固。", "加入生菜煮软，即可盛出。"]),
        Recipe(name: "牛肉蛋花汤", minutes: 14, ingredients: ["牛肉", "鸡蛋"],
               steps: ["牛肉约 100 克切成薄片，1 个鸡蛋打散。", "烧开约 450 毫升水，放入牛肉片煮熟。", "蛋液沿锅边缓缓倒入，待完全凝固后盛出。"]),
        Recipe(name: "牛肉生菜包", minutes: 15, ingredients: ["牛肉", "生菜"],
               steps: ["洗净几片完整生菜叶并沥水，留下当菜包。另用干净的刀板将牛肉切薄片。", "用清水把牛肉片煮熟并捞出沥水。", "取生菜叶包住牛肉，卷起来吃。"]),
        Recipe(name: "水煮生菜", minutes: 6, ingredients: ["生菜"],
               steps: ["把一把生菜逐叶洗净，撕成大片。", "烧开一锅水，把叶子压入水中，煮到刚变软后沥水装盘。"]),
        Recipe(name: "牛肉米饭汤", minutes: 17, ingredients: ["牛肉", "米饭"],
               steps: ["把半碗熟米饭和约 500 毫升水煮到米粒变软。", "把约 100 克牛肉切成薄片，加入汤饭中并拨散，煮到牛肉熟透、米饭整体冒热气。"]),
        Recipe(name: "番茄牛肉汤面", minutes: 20, ingredients: ["番茄", "牛肉", "面条"],
               steps: ["取 1 个番茄切块，约 100 克牛肉切薄片。", "番茄加约 500 毫升水煮软，下牛肉片并煮熟。", "另煮一人份面条，沥水盛碗，把番茄、牛肉和汤浇在面上。"]),
        Recipe(name: "牛肉豆腐汤", minutes: 16, ingredients: ["牛肉", "豆腐"],
               steps: ["豆腐约 120 克切块，牛肉约 100 克切薄片。", "水开后放豆腐小煮，加入牛肉片拨散并彻底煮熟。"]),
        Recipe(name: "番茄牛肉碎盖饭", minutes: 20, ingredients: ["番茄", "牛肉碎", "米饭", "油"],
               steps: ["番茄 1 个切小丁，把一碗熟米饭加热至整体冒热气。", "用少量油把牛肉碎炒散，加番茄小火煮出汁。牛肉碎的中心温度达到 71°C。", "把番茄牛肉碎铺在米饭上。"]),
        Recipe(name: "鸡胸肉生菜包", minutes: 20, ingredients: ["鸡胸肉", "生菜"],
               steps: ["洗净生菜叶并沥水备用。另用干净刀板把鸡胸肉切成均匀薄片。", "把鸡肉放进微沸的清水中煮，中心达到 74°C 后捞起。", "把鸡肉装进生菜叶里卷起来吃。"]),
        Recipe(name: "鸡肉蘑菇汤", minutes: 22, ingredients: ["鸡胸肉", "蘑菇"],
               steps: ["约 120 克蘑菇洗净切片，鸡胸肉切小块。", "清水烧开，先煮蘑菇，再加入鸡肉。用温度计检查鸡肉中心达到 74°C 后盛出。"]),
        Recipe(name: "蘑菇蛋花汤", minutes: 12, ingredients: ["蘑菇", "鸡蛋"],
               steps: ["蘑菇约 100 克洗净切片，用约 450 毫升水煮熟。", "打散一个鸡蛋，淋入锅中，煮到蛋花完全凝固。"]),
        Recipe(name: "蘑菇炒蛋", minutes: 13, ingredients: ["蘑菇", "鸡蛋", "油"],
               steps: ["蘑菇约 100 克切片，2 个鸡蛋打散。", "倒少量油，先把蘑菇炒熟，再淋入蛋液。翻炒到蛋液全部凝固。"]),
        Recipe(name: "土豆鸡蛋泥", minutes: 18, ingredients: ["土豆", "鸡蛋"],
               steps: ["1 个中等土豆去皮切小块，煮到用筷子能轻松戳透。", "把 1 个鸡蛋煮到蛋黄和蛋白完全凝固。", "趁热将土豆压成泥，加入切碎的鸡蛋拌匀。"]),
        Recipe(name: "土豆胡萝卜汤", minutes: 22, ingredients: ["土豆", "胡萝卜"],
               steps: ["1 个土豆和半根胡萝卜去皮切小块。", "加水盖过食材，煮开后转小火煮到全部能轻松戳透。可以压碎几块土豆，让汤更浓。"]),
        Recipe(name: "番茄土豆汤", minutes: 20, ingredients: ["番茄", "土豆"],
               steps: ["番茄 1 个切块，土豆 1 个去皮切小块。", "加约 500 毫升水，先把土豆煮到接近软透，再加番茄煮软。"]),
        Recipe(name: "包菜蛋花汤", minutes: 13, ingredients: ["包菜", "鸡蛋"],
               steps: ["洗净两片包菜切丝，1 个鸡蛋打散。", "用约 500 毫升水将包菜煮软，再淋入蛋液，煮到完全凝固。"]),
        Recipe(name: "包菜炒蛋", minutes: 14, ingredients: ["包菜", "鸡蛋", "油"],
               steps: ["洗净包菜切细丝，把 2 个鸡蛋打散。", "热锅倒少量油，把包菜丝炒软，再加入蛋液，炒到完全凝固。"]),
        Recipe(name: "黄瓜鸡蛋拌生菜", minutes: 15, ingredients: ["黄瓜", "鸡蛋", "生菜"],
               steps: ["黄瓜和生菜洗净。黄瓜切丁，生菜撕小。", "鸡蛋煮到蛋白蛋黄完全凝固，去壳切块。", "把鸡蛋、黄瓜和生菜拌在一起。"]),
        Recipe(name: "生菜豆腐汤", minutes: 12, ingredients: ["生菜", "豆腐"],
               steps: ["洗净一把生菜并撕小，豆腐约 120 克切块。", "水开后放豆腐煮约 5 分钟，加入生菜烫软即可。"]),
        Recipe(name: "生菜鸡蛋炒饭", minutes: 15, ingredients: ["生菜", "鸡蛋", "米饭", "油"],
               steps: ["生菜洗净擦干切碎，打散 1 个蛋，准备一碗熟米饭。", "用少量油把蛋炒到完全凝固，再加饭炒到整锅热透。", "加生菜略炒至变软，盛出。"])
    ]
}
