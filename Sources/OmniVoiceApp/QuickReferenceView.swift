import SwiftUI

struct QuickReferenceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            referenceRow("Dictate", "Hold the dictation hotkey, speak, then release to insert cleaned text.")
            referenceRow("Correct", "Say \"no wait\", \"scratch that\", or \"oops, correction\" before the replacement.")
            referenceRow("Quote", "Say \"open quote hello close quote\" to produce \"hello\".")
            referenceRow("Punctuate", "Say \"comma\", \"period\", \"question mark\", \"new line\", or \"new paragraph\".")
            referenceRow("Command", "Say \"Command, open Safari\" to launch supported apps instead of inserting text.")
            referenceRow("Literal", "Switch to Raw Dictation when you want the fewest cleanup edits.")
        }
        .font(.callout)
    }

    private func referenceRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(detail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
