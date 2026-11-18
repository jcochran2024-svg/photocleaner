import SwiftUI

struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SwipeFilter
    let onApply: (SwipeFilter) -> Void

    init(filter: SwipeFilter, onApply: @escaping (SwipeFilter) -> Void) {
        _draft = State(initialValue: filter)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    Picker("Range", selection: $draft.range) {
                        ForEach(DateRangeOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    if draft.range == .custom {
                        DatePicker("From", selection: $draft.customFrom, displayedComponents: .date)
                        DatePicker("To", selection: $draft.customTo, displayedComponents: .date)
                    }
                }
                Section("Type") {
                    Picker("Show", selection: $draft.media) {
                        ForEach(MediaFilter.allCases) { media in
                            Text(media.title).tag(media)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Oldest first", isOn: $draft.oldestFirst)
                    Toggle("Hide already reviewed", isOn: $draft.hideReviewed)
                } footer: {
                    Text("Reviewed = photos you already swiped Keep or Delete on. Skipped photos always come back.")
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(draft)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}
