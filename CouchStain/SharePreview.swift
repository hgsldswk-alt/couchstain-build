import Observation
import SwiftUI
import UIKit

struct SharePreview: View {
    @Environment(\.dismiss) private var dismiss

    let card: Card
    let milestone: Bool
    let finish: (Bool) -> Void

    @State private var artwork: UIImage?
    @State private var renderFailed = false
    @State private var export = ShareExport()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L.t("share.title")).font(.title.bold())
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("share.title")
                        Text(L.t("share.hint")).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    quietButton("common.close", id: "share.close") { dismiss() }
                        .disabled(export.busy)
                }

                if let artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 312)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line) }
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Text(L.f("share.previewLabel", card.selection.label(),
                                                      L.t(milestone ? "card.checked" : card.title))))
                        .accessibilityIdentifier("share.preview")
                } else if !renderFailed {
                    ProgressView(L.t("share.preparing")).frame(maxWidth: .infinity, minHeight: 180)
                }

                Text(card.selection.code).font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("share.code")

                export.feedback(renderFailed: renderFailed)

                actionButton("share.image", id: "share.image", primary: true) {
                    export.image(card: card, milestone: milestone, prepared: artwork)
                }
                .disabled(artwork == nil || export.busy)
                actionButton("share.copy", id: "share.copy", primary: false) {
                    if !Launch.isUITesting {
                        UIPasteboard.general.setItems([["public.utf8-plain-text": card.selection.code]],
                                                      options: [.localOnly: true])
                    }
                    export.status = "share.copied"
                }
                rowButton("share.file", icon: "square.and.arrow.up", id: "share.file") {
                    export.codeFile(card.selection.code)
                }
                .disabled(export.busy)
            }
            .padding(20)
        }
        .background(Palette.paper.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
        .interactiveDismissDisabled(export.busy)
        .task { await prepare() }
        .modifier(SharePresentation(export: export, finish: finish))
    }

    @MainActor
    private func prepare() async {
        let card = self.card
        let milestone = self.milestone
        let result = await Task.detached(priority: .userInitiated) {
            ShareExport.render(card: card, milestone: milestone)
        }.value
        guard !Task.isCancelled else { return }
        artwork = result
        renderFailed = result == nil
    }
}

@MainActor
@Observable
final class ShareExport {
    private(set) var busy = false
    private var failed = false
    var status: String?
    fileprivate var activity: ActivityRequest?
    private var activeRequest: ActivityRequest?
    private var completedShare = false

    var isPresenting: Bool { activeRequest != nil }
    var hasFailure: Bool { failed }

    nonisolated static func render(card: Card, milestone: Bool) -> UIImage? {
        let id = L.bundle.object(forInfoDictionaryKey: "APP_STORE_ID") as? String ?? ""
        let store = StoreLink.appURL(id: id)
        return ShareArtwork.render(card: card, milestone: milestone, destination: store ?? StoreLink.supportURL,
                                   isStore: store != nil)
    }

    @ViewBuilder
    func feedback(renderFailed: Bool = false) -> some View {
        if failed || renderFailed {
            Text(L.t("share.failed")).font(.subheadline)
                .accessibilityIdentifier("share.error")
                .rescuePanel(Palette.caution)
        }
        if let status {
            Text(L.t(status)).font(.footnote.weight(.medium))
                .foregroundStyle(Palette.accentText)
                .accessibilityIdentifier(status)
        }
    }

    func clearFeedback() {
        failed = false
        status = nil
    }

    func image(card: Card, milestone: Bool, prepared: UIImage? = nil) {
        start(caption: L.t("share.caption")) {
            let image = prepared ?? Self.render(card: card, milestone: milestone)
            guard let png = image?.pngData() else { throw CocoaError(.fileWriteUnknown) }
            return try ShareFile.write(png, name: "couch-care.png")
        }
    }

    func codeFile(_ code: String) {
        start {
            try ShareFile.write(Data(code.utf8), name: "couch-care.couchstain")
        }
    }

    private func start(caption: String? = nil, write: @escaping @Sendable () throws -> URL) {
        guard !busy, !isPresenting else { return }
        busy = true
        clearFeedback()
        Task {
            defer { busy = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) { try write() }.value
                if Launch.isUITesting {
                    removeExport(url)
                    status = "share.requested"
                    return
                }
                let request = ActivityRequest(url: url, caption: caption)
                completedShare = false
                activeRequest = request
                activity = request
            } catch {
                failed = true
            }
        }
    }

    fileprivate func activityCompleted(_ request: ActivityRequest, completed: Bool, failed: Bool) {
        guard activeRequest?.id == request.id else { return }
        self.failed = failed
        completedShare = completed && !failed
        activity = nil
    }

    fileprivate func activityDismissed() -> Bool? {
        guard let request = activeRequest else { return nil }
        activeRequest = nil
        removeExport(request.url)
        return failed ? nil : completedShare
    }

    private func removeExport(_ url: URL) {
        Task.detached(priority: .utility) { ShareFile.remove(url) }
    }
}

@MainActor
struct SharePresentation: ViewModifier {
    @Bindable var export: ShareExport
    let finish: (Bool) -> Void
    var didDismiss: () -> Void = {}

    func body(content: Content) -> some View {
        content.sheet(item: $export.activity, onDismiss: {
            if let completed = export.activityDismissed() { finish(completed) }
            didDismiss()
        }) { request in
            ActivityView(items: request.items) { completed, failed in
                export.activityCompleted(request, completed: completed, failed: failed)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

fileprivate struct ActivityRequest: Identifiable {
    let id = UUID()
    let url: URL
    let caption: String?
    var items: [Any] {
        if let caption { return [url, caption] }
        return [url]
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: (Bool, Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            DispatchQueue.main.async { onComplete(completed, error != nil) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
