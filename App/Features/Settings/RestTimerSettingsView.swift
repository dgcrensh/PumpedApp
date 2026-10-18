import PumpedCore
import SwiftData
import SwiftUI

/// Settings → Rest timers: how long to rest after a set of each exercise type (spec §6.2).
struct RestTimerSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settings: [RestTimerSettings]

    var body: some View {
        Form {
            if let settings = settings.first {
                Section {
                    ForEach(ExerciseType.allCases, id: \.self) { type in
                        Stepper(value: binding(for: type, in: settings), in: RestTimer.settingRange, step: RestTimer.settingStep) {
                            LabeledContent(type.displayName, value: CountdownText.format(settings.seconds(for: type)))
                        }
                    }
                } footer: {
                    Text("The timer starts each time you log a set. Each exercise's type comes from the library.")
                }
                Section {
                    Button("Reset to defaults") {
                        for type in ExerciseType.allCases {
                            settings.setSeconds(type.defaultRestSeconds, for: type)
                        }
                        try? context.save()
                    }
                }
            }
        }
        .navigationTitle("Rest timers")
        .onAppear {
            if settings.isEmpty {
                _ = WorkoutFlow.restTimerSettings(in: context)
                try? context.save()
            }
        }
    }

    private func binding(for type: ExerciseType, in settings: RestTimerSettings) -> Binding<Int> {
        Binding {
            settings.seconds(for: type)
        } set: { seconds in
            settings.setSeconds(seconds, for: type)
            try? context.save()
        }
    }
}

extension RestTimerSettings {
    func setSeconds(_ seconds: Int, for type: ExerciseType) {
        switch type {
        case .heavyCompound: heavyCompoundSec = seconds
        case .compound: compoundSec = seconds
        case .isolation: isolationSec = seconds
        }
    }
}

#Preview {
    NavigationStack {
        RestTimerSettingsView()
    }
    .modelContainer(PreviewData.container)
}
