import SwiftUI

struct NoteSheetView: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(size: 18))
                .padding()
                .focused($isFocused)
                .navigationTitle("Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.fraction(0.4), .large])
        .presentationDragIndicator(.visible)
        .onAppear { isFocused = true }
    }
}
