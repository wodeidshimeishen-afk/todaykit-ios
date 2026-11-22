import SwiftUI
import PhotosUI
import UIKit

enum AppTheme: String, CaseIterable, Identifiable {
    case blue, peach, mint, lavender

    var id: String { rawValue }

    var name: String {
        switch self {
        case .blue: "雾蓝"
        case .peach: "蜜桃粉"
        case .mint: "薄荷绿"
        case .lavender: "薰衣草紫"
        }
    }

    var base: Color {
        switch self {
        case .blue: Color(red: 0.95, green: 0.95, blue: 0.97)
        case .peach: Color(red: 0.99, green: 0.95, blue: 0.94)
        case .mint: Color(red: 0.93, green: 0.97, blue: 0.95)
        case .lavender: Color(red: 0.96, green: 0.94, blue: 0.99)
        }
    }

    var accent: Color {
        switch self {
        case .blue: Color(uiColor: .systemBlue)
        case .peach: Color(red: 0.60, green: 0.24, blue: 0.30)
        case .mint: Color(red: 0.12, green: 0.40, blue: 0.30)
        case .lavender: Color(red: 0.39, green: 0.24, blue: 0.59)
        }
    }
}

struct AppearanceView: View {
    @EnvironmentObject private var store: TodayStore

    var body: some View {
        List(AppTheme.allCases) { theme in
            Button {
                store.data.theme = theme.rawValue
            } label: {
                HStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.base)
                        .overlay { Circle().fill(theme.accent).frame(width: 14) }
                        .frame(width: 42, height: 34)
                    Text(theme.name).foregroundStyle(ink)
                    Spacer()
                    if store.theme == theme {
                        Image(systemName: "checkmark").foregroundStyle(theme.accent)
                            .accessibilityLabel("已选")
                    }
                }
            }
        }.navigationTitle("外观")
    }
}

extension TodayStore {
    var theme: AppTheme { AppTheme(rawValue: data.theme ?? "") ?? .blue }
}

struct DailyWeather: Equatable, Decodable {
    struct Forecast: Decodable {
        let weather_code: [Int?]
        let temperature_2m_max: [Double?]
        let temperature_2m_min: [Double?]
    }

    let daily: Forecast
    var code: Int? { daily.weather_code.first ?? nil }

    var symbol: String {
        guard let code else { return "sparkle" }
        return switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "sparkle"
        }
    }

    var label: String {
        switch symbol {
        case "sun.max.fill": "晴"
        case "cloud.sun.fill": "晴间多云"
        case "cloud.fill": "阴"
        case "cloud.fog.fill": "有雾"
        case "cloud.rain.fill": "有雨"
        case "cloud.snow.fill": "有雪"
        case "cloud.bolt.rain.fill": "雷雨"
        default: "暂无天气"
        }
    }

    var range: String? {
        guard let low = daily.temperature_2m_min.first ?? nil, let high = daily.temperature_2m_max.first ?? nil else { return nil }
        return "\(low.formatted(.number.precision(.fractionLength(0))))°–\(high.formatted(.number.precision(.fractionLength(0))))°"
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.code == rhs.code && lhs.range == rhs.range
    }
}

enum OpenMeteo {
    private struct CityResults: Decodable { let results: [WeatherCity]? }

    static func cities(matching name: String) async throws -> [WeatherCity] {
        let response: CityResults = try await request("https://geocoding-api.open-meteo.com/v1/search",
            query: ["name": name, "language": "zh", "count": "8"])
        return response.results ?? []
    }

    static func weather(for city: WeatherCity) async throws -> DailyWeather {
        try await request("https://api.open-meteo.com/v1/forecast",
                          query: ["latitude": String(city.latitude), "longitude": String(city.longitude),
                                  "daily": "weather_code,temperature_2m_max,temperature_2m_min",
                                  "timezone": "auto", "forecast_days": "1"])
    }

    private static func request<T: Decodable>(_ endpoint: String, query: [String: String]) async throws -> T {
        var parts = URLComponents(string: endpoint)
        parts?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = parts?.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 12))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct WeatherCityView: View {
    @EnvironmentObject private var store: TodayStore
    @State private var search = ""
    @State private var matches: [WeatherCity] = []
    @State private var status = ""
    @State private var searching = false

    var body: some View {
        List {
            Section {
                if let city = store.data.weatherCity {
                    LabeledContent("当前城市", value: city.name)
                    Button("关闭天气", role: .destructive) { store.data.weatherCity = nil }
                }
                TextField("输入城市，例如 Sydney 或上海", text: $search)
                    .submitLabel(.search)
                    .onSubmit { runSearch() }
                Button("搜索城市") { runSearch() }
                    .disabled(searching || search.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                if searching { ProgressView() }
                if !status.isEmpty { Text(status).foregroundStyle(muted) }
                ForEach(matches) { city in
                    Button {
                        store.data.weatherCity = city
                        status = "已选：\(city.name)"
                        matches = []
                    } label: {
                        VStack(alignment: .leading) {
                            Text(city.name)
                            if !city.region.isEmpty { Text(city.region).font(.caption).foregroundStyle(muted) }
                        }
                    }
                }
            } footer: {
                Text("按所选城市查询当天预报。只把城市搜索词和城市坐标提供给天气服务，无需定位权限。")
            }
            Link("天气数据由 Open-Meteo 提供", destination: URL(string: "https://open-meteo.com/")!)
        }.navigationTitle("今日天气")
    }

    private func runSearch() {
        let name = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searching, name.count >= 2 else { return }
        searching = true
        status = ""
        matches = []
        Task {
            defer { searching = false }
            do {
                matches = try await OpenMeteo.cities(matching: name)
                if matches.isEmpty { status = "未找到城市，可以试试英文名。" }
            } catch {
                status = "暂时无法搜索，请检查网络后再试。"
            }
        }
    }
}

struct MealPhoto: View {
    var data: Data?
    var height: CGFloat = 150

    var body: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("菜品照片")
        }
    }
}

struct MealPhotoEditor: View {
    @Binding var photo: Data?
    @State private var selection: PhotosPickerItem?
    @State private var camera = false
    @State private var problem = ""

    var body: some View {
        Section("菜品照片（选填）") {
            MealPhoto(data: photo)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { camera = true } label: { Label("拍照", systemImage: "camera") }
            }
            PhotosPicker(selection: $selection, matching: .images) {
                Label(photo == nil ? "从相册选" : "换张照片", systemImage: "photo")
            }
            if photo != nil {
                Button("移除照片", role: .destructive) { selection = nil; photo = nil; problem = "" }
            }
            if !problem.isEmpty { Text(problem).font(.footnote).foregroundStyle(muted) }
        }
        .task(id: selection) {
            guard let selection else { return }
            do {
                let data = try await selection.loadTransferable(type: Data.self)
                guard !Task.isCancelled else { return }
                guard let data, let image = UIImage(data: data) else {
                    problem = "无法读取这张照片。"
                    return
                }
                accept(image)
            } catch {
                if !Task.isCancelled { problem = "无法载入照片，请再试一次。" }
            }
        }
        .sheet(isPresented: $camera) {
            MealCamera { image in
                camera = false
                if let image { accept(image) }
            }.ignoresSafeArea()
        }
    }

    private func accept(_ image: UIImage) {
        let longSide = max(image.size.width, image.size.height)
        guard longSide > 0 else { return }
        let scale = min(1, 900 / longSide)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = rendered.jpegData(compressionQuality: 0.66) else {
            problem = "无法保存这张照片。"
            return
        }
        photo = data
        problem = ""
    }
}

struct MealCamera: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }
    }
}
