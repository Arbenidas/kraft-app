import SwiftUI
import WidgetKit

// Mismo contrato de App Group que iOS; se añade a un target Widget Extension de macOS.
struct KraftPending: Identifiable, Decodable { let id: String; let title: String; let kind: String }
struct KraftWidgetEntry: TimelineEntry { let date: Date; let items: [KraftPending] }
struct KraftWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> KraftWidgetEntry { KraftWidgetEntry(date: .now, items: []) }
  func getSnapshot(in context: Context, completion: @escaping (KraftWidgetEntry) -> Void) { completion(entry()) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<KraftWidgetEntry>) -> Void) { completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(900)))) }
  private func entry() -> KraftWidgetEntry {
    let values = UserDefaults(suiteName: "group.com.kraft.app")?.array(forKey: "pendingItems") as? [[String: String]] ?? []
    let items = values.compactMap { try? JSONDecoder().decode(KraftPending.self, from: JSONSerialization.data(withJSONObject: $0)) }
    return KraftWidgetEntry(date: .now, items: items)
  }
}
struct KraftWidgetView: View { let entry: KraftWidgetEntry; var body: some View { VStack(alignment: .leading) { Text("KRAFT · Pendientes").font(.headline); ForEach(entry.items.prefix(3)) { Text($0.title).lineLimit(1) }; Spacer(); Link("Capturar idea o tarea", destination: URL(string: "kraft://capture")!) }.padding() } }
@main struct KraftWidget: Widget { let kind = "KraftWidget"; var body: some WidgetConfiguration { StaticConfiguration(kind: kind, provider: KraftWidgetProvider()) { KraftWidgetView(entry: $0) }.configurationDisplayName("Pendientes KRAFT") } }
