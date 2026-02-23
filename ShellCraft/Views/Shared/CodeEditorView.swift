import SwiftUI

struct CodeEditorView: View {
    @Binding var text: String
    let language: String
    var lineNumbers: Bool = true
    var isEditable: Bool = true

    @State private var lineCount: Int = 1

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if lineNumbers {
                lineNumberGutter
            }

            TextEditor(text: isEditable ? $text : .constant(text))
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .onChange(of: text) {
                    updateLineCount()
                }
                .onAppear {
                    updateLineCount()
                }
                .disabled(!isEditable)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.tertiary, lineWidth: 0.5)
        )
    }

    private var lineNumberGutter: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(1...max(lineCount, 1), id: \.self) { number in
                Text("\(number)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 30, alignment: .trailing)
                    .padding(.trailing, 4)
                    .padding(.vertical, 1)
            }
            Spacer()
        }
        .padding(.top, 8)
        .background(.quaternary.opacity(0.3))
    }

    private func updateLineCount() {
        lineCount = max(text.components(separatedBy: "\n").count, 1)
    }
}
