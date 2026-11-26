import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    let providedFile: URL?
    let use: (Selection) -> Void

    @State private var code = ""
    @State private var preview: Selection?
    @State private var issue: String?
    @State private var choosingFile = false
    @State private var reading = false

    private let cardFile = UTType(exportedAs: "com.hgsldswk.couchstain.card", conformingTo: .plainText)

    private var manualCode: Binding<String> {
        Binding(get: { code }, set: {
            code = $0
            preview = nil
            issue = nil
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L.t("import.title")).font(.title.bold()).accessibilityAddTraits(.isHeader)
                        Text(L.t("import.hint")).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    quietButton("common.close", id: "import.close") { dismiss() }
                }

                VStack(alignment: .leading, spacing: 9) {
                    actionButton("import.paste", id: "import.paste", primary: preview == nil) {
                        code = UIPasteboard.general.string ?? ""
                        validate()
                    }
                    .disabled(reading)

                    Text(L.t("import.field")).font(.headline)
                    TextField(L.t("import.field"), text: manualCode, prompt: Text(L.t("import.example")))
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($fieldFocused)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("import.code")
                        .onSubmit(validate)
                    actionButton("import.preview", id: "import.preview", primary: false, action: validate)
                        .disabled(reading)
                }
                .rescuePanel()

                if let issue {
                    Label(L.t(issue), systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .accessibilityIdentifier("import.issue")
                        .rescuePanel(Palette.caution)
                }
                if let preview {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(preview.label()).font(.headline)
                            .accessibilityIdentifier("import.match")
                        Text(L.f("import.version", CareRules.version)).font(.footnote)
                            .foregroundStyle(Palette.muted)
                        Text(L.t("import.checkTag")).font(.footnote).foregroundStyle(Palette.muted)
                    }
                    .rescuePanel(Palette.tint)
                    actionButton("import.use", id: "import.use", primary: true) { use(preview) }
                }
                rowButton("import.file", icon: "folder", id: "import.file") {
                    fieldFocused = false
                    choosingFile = true
                }
                .disabled(reading)
                if reading { ProgressView(L.t("import.reading")) }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.paper.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [cardFile, .plainText]) { result in
            switch result {
            case .success(let url): Task { await read(url) }
            case .failure(let failure):
                if (failure as NSError).code != NSUserCancelledError { issue = "import.fileError" }
            }
        }
        .task {
            if let providedFile { await read(providedFile) }
        }
    }

    private func validate() {
        fieldFocused = false
        preview = ShareCode.parse(code)
        issue = preview == nil ? "import.invalid" : nil
    }

    @MainActor
    private func read(_ url: URL) async {
        reading = true
        preview = nil
        issue = nil
        defer { reading = false }
        do {
            let result = try await Task.detached(priority: .userInitiated) { try ShareCode.readFile(url) }.value
            guard !Task.isCancelled else { return }
            if let result {
                code = result.code
                preview = result
            } else {
                issue = "import.invalid"
            }
        } catch {
            issue = "import.fileError"
        }
    }
}
