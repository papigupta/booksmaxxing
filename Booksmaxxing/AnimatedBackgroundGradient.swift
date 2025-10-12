import SwiftUI

/// Crossfades between gradient color pairs when `key` changes, creating a soft, natural transition.
struct AnimatedBackgroundGradient: View {
    let start: Color
    let end: Color
    let key: String
    let duration: Double

    @State private var lastKey: String = ""
    @State private var lastStart: Color? = nil
    @State private var lastEnd: Color? = nil
    @State private var progress: Double = 1.0

    init(start: Color, end: Color, key: String, duration: Double = 0.3) {
        self.start = start
        self.end = end
        self.key = key
        self.duration = duration
    }

    var body: some View {
        ZStack {
            if let ls = lastStart, let le = lastEnd, progress < 1.0 {
                LinearGradient(colors: [ls, le], startPoint: .top, endPoint: .bottom)
                    .opacity(1.0 - progress)
            }
            LinearGradient(colors: [start, end], startPoint: .top, endPoint: .bottom)
                .opacity(progress)
        }
        .onAppear {
            // Initialize last colors to the current to avoid initial flash
            lastKey = key
            lastStart = start
            lastEnd = end
            progress = 1.0
        }
        .onChange(of: key) { _, newKey in
            // Capture previous colors before animating to new ones
            if lastKey != newKey {
                lastKey = newKey
                lastStart = lastStart ?? start
                lastEnd = lastEnd ?? end
                progress = 0.0
                withAnimation(.easeInOut(duration: duration)) {
                    progress = 1.0
                }
                // After animation completes, set last colors to the new ones
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    lastStart = start
                    lastEnd = end
                }
            }
        }
        // Also react if colors change without key change (defensive)
        .onChange(of: start) { _, _ in triggerIfNeeded() }
        .onChange(of: end) { _, _ in triggerIfNeeded() }
    }

    private func triggerIfNeeded() {
        // If colors changed but key didn't, still crossfade
        progress = 0.0
        withAnimation(.easeInOut(duration: duration)) {
            progress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            lastStart = start
            lastEnd = end
        }
    }
}

