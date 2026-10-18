import Charts
import PumpedCore
import SwiftData
import SwiftUI

/// An exercise's progress (spec §9): top-set weight and estimated 1RM over time, its PRs and every
/// workout it was in. A toggle widens the chart and workouts to the whole movement type.
struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var context
    let exercise: Exercise

    @State private var showsMovementType = false

    var body: some View {
        let scope = self.scope
        let workouts = HistoryData.workouts(scope, in: context)
        let points = ExerciseProgress.points(workouts.map(\.dated))
        List {
            if let movementType = exercise.movementType {
                Picker("Show", selection: $showsMovementType) {
                    Text(exercise.name).tag(false)
                    Text("All \(movementType.name)").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                if points.isEmpty {
                    Text("No sets logged yet")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressChart(points: points)
                        .frame(height: 220)
                        .padding(.vertical, 8)
                }
            } header: {
                Text("Progress")
            } footer: {
                Text("Top set is the heaviest set of each workout. Est. 1RM uses Epley: weight × (1 + reps/30).")
            }
            if !showsMovementType {
                records
            }
            Section("Workouts") {
                ForEach(workouts) { workout in
                    NavigationLink(value: workout.session) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.session.startedAt.formatted(date: .abbreviated, time: .omitted))
                            if showsMovementType {
                                Text(workout.exerciseNames.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(SetPrefill.summary(workout.sets))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scope: ProgressScope {
        if showsMovementType, let id = exercise.movementType?.id { return .movementType(id) }
        return .exercise(exercise.id)
    }

    @ViewBuilder
    private var records: some View {
        let book = HistoryData.records(of: exercise.id, in: context)
        if !book.isEmpty {
            Section("Records") {
                if let heaviest = book.heaviest {
                    LabeledContent("Heaviest weight", value: "\(SetValues.format(heaviest.weightLb)) lb × \(heaviest.reps)")
                }
                if let best = book.bestEstimatedOneRepMax {
                    LabeledContent(
                        "Best est. 1RM",
                        value: "\(SetValues.format(PersonalRecords.estimatedOneRepMax(best).rounded())) lb (\(best.summary))"
                    )
                }
                ForEach(book.mostReps, id: \.weightLb) { set in
                    LabeledContent(
                        "Most reps at \(set.weightLb == 0 ? "bodyweight" : "\(SetValues.format(set.weightLb)) lb")",
                        value: "\(set.reps)"
                    )
                }
            }
            .accessibilityIdentifier("records")
            let timeline = HistoryData.prTimeline(of: exercise.id, in: context)
            if !timeline.isEmpty {
                Section("PR history") {
                    ForEach(Array(timeline.enumerated()), id: \.offset) { _, event in
                        PRLabel(title: event.date.formatted(date: .abbreviated, time: .omitted), record: event.record)
                    }
                }
            }
        }
    }
}

/// Top-set weight and estimated 1RM per workout.
struct ProgressChart: View {
    let points: [ProgressPoint]

    private static let topSet = "Top set"
    private static let e1RM = "Est. 1RM"

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Pounds", point.topSetWeightLb),
                    series: .value("Series", Self.topSet)
                )
                .foregroundStyle(by: .value("Series", Self.topSet))
                .symbol(by: .value("Series", Self.topSet))

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Pounds", point.estimatedOneRepMax),
                    series: .value("Series", Self.e1RM)
                )
                .foregroundStyle(by: .value("Series", Self.e1RM))
                .symbol(by: .value("Series", Self.e1RM))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel("lb")
        .chartLegend(position: .top, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress-chart")
    }
}
