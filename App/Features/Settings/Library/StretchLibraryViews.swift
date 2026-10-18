import SwiftData
import SwiftUI

/// Read-only list of stretches with their default hold.
struct StretchListView: View {
    @Query(sort: \Stretch.name) private var stretches: [Stretch]

    var body: some View {
        List(stretches) { stretch in
            LabeledContent(stretch.name, value: formatDuration(stretch.defaultDurationSec))
        }
        .navigationTitle("Stretches")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Read-only list of warmup cardio options.
struct CardioListView: View {
    @Query(sort: \CardioOption.name) private var options: [CardioOption]

    var body: some View {
        List(options) { Text($0.name) }
            .navigationTitle("Cardio")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// "0:30", "5:15".
func formatDuration(_ seconds: Int) -> String {
    Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
}

#Preview {
    NavigationStack {
        StretchListView()
    }
    .modelContainer(PreviewData.container)
}
