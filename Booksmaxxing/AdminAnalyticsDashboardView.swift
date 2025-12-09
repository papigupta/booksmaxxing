#if DEBUG
import SwiftUI
import SwiftData
import UIKit

struct AdminAnalyticsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var snapshots: [UserAnalyticsSnapshot] = []
    @State private var isLoading = false
    @State private var copyConfirmation = false

    private let columns: [AdminColumn] = [
        AdminColumn(title: "User", value: { $0.userIdentifier }),
        AdminColumn(title: "First Seen", value: { Self.dateText($0.firstSeenAt) }),
        AdminColumn(title: "Signed In", value: { Self.dateText($0.signedInAt) }),
        AdminColumn(title: "App Version", value: { $0.appVersionLastSeen ?? "—" }),
        AdminColumn(title: "Has Email", value: { Self.boolText($0.hasEmail) }),
        AdminColumn(title: "Email Status", value: { $0.emailStatus.rawValue }),
        AdminColumn(title: "Email Updated", value: { Self.dateText($0.emailUpdatedAt) }),
        AdminColumn(title: "Books", value: { $0.hasAddedBook ? "✅" : "—" }),
        AdminColumn(title: "Starter Books", value: { "\($0.starterLessonBookCount)" }),
        AdminColumn(title: "Starter Lesson Used", value: { Self.boolText($0.usedStarterLesson) }),
        AdminColumn(title: "Started Lesson", value: { Self.boolText($0.startedLesson) }),
        AdminColumn(title: "First Start", value: { Self.dateText($0.firstLessonStartedAt) }),
        AdminColumn(title: "Finished Lesson", value: { Self.boolText($0.finishedLesson) }),
        AdminColumn(title: "First Finish", value: { Self.dateText($0.firstLessonFinishedAt) }),
        AdminColumn(title: "Results Viewed", value: { Self.boolText($0.resultsViewed) }),
        AdminColumn(title: "Primer Opened", value: { Self.boolText($0.primerOpened) }),
        AdminColumn(title: "Streak Page", value: { Self.boolText($0.streakPageViewed) }),
        AdminColumn(title: "Rings Page", value: { Self.boolText($0.activityRingsViewed) }),
        AdminColumn(title: "Current Streak", value: { "\($0.currentStreak)" }),
        AdminColumn(title: "Best Streak", value: { "\($0.bestStreak)" }),
        AdminColumn(title: "Lit Today", value: { Self.boolText($0.streakLitToday) }),
        AdminColumn(title: "BCal Ring", value: { Self.boolText($0.brainCaloriesRingClosed) }),
        AdminColumn(title: "Clarity Ring", value: { Self.boolText($0.clarityRingClosed) }),
        AdminColumn(title: "Attention Ring", value: { Self.boolText($0.attentionRingClosed) }),
        AdminColumn(title: "Last Updated", value: { Self.dateText($0.lastUpdatedAt) })
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    ProgressView("Loading snapshots…")
                        .progressViewStyle(.circular)
                }
                if snapshots.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No analytics yet",
                        systemImage: "doc.text",
                        description: Text("As soon as people move through onboarding, rows will appear here.")
                    )
                } else {
                    ScrollView([.vertical, .horizontal]) {
                        VStack(alignment: .leading, spacing: 0) {
                            headerRow
                            Divider()
                            ForEach(snapshots, id: \.id) { snapshot in
                                row(for: snapshot)
                                Divider()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Spacer()
            }
            .padding()
            .navigationTitle("User Analytics")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: copyCSV) {
                        Label("Copy CSV", systemImage: "doc.on.doc")
                    }
                    .disabled(snapshots.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: fetchSnapshots) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .onAppear(perform: fetchSnapshots)
            .alert("CSV copied", isPresented: $copyConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Paste anywhere to share the current table.")
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(columns) { column in
                Text(column.title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 120, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func row(for snapshot: UserAnalyticsSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(columns) { column in
                Text(column.value(snapshot))
                    .font(.footnote)
                    .frame(minWidth: 120, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.clear)
    }

    private func fetchSnapshots() {
        isLoading = true
        Task { @MainActor in
            var descriptor = FetchDescriptor<UserAnalyticsSnapshot>(
                sortBy: [SortDescriptor(\.lastUpdatedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 500
            do {
                snapshots = try modelContext.fetch(descriptor)
            } catch {
                print("AdminAnalyticsDashboardView fetch error: \(error)")
                snapshots = []
            }
            isLoading = false
        }
    }

    private func copyCSV() {
        guard !snapshots.isEmpty else { return }
        let header = columns.map { Self.csvEscape($0.title) }.joined(separator: ",")
        let rows = snapshots.map { snapshot in
            columns.map { Self.csvEscape($0.value(snapshot)) }.joined(separator: ",")
        }
        let csv = ([header] + rows).joined(separator: "\n")
        UIPasteboard.general.string = csv
        copyConfirmation = true
    }

    private static func boolText(_ value: Bool) -> String { value ? "✅" : "—" }

    private static func dateText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func csvEscape(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") {
            escaped = "\"\(escaped)\""
        }
        return escaped
    }
}

private struct AdminColumn: Identifiable {
    let id = UUID()
    let title: String
    let value: (UserAnalyticsSnapshot) -> String
}
#endif
