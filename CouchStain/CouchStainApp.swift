import StoreKit
import SwiftUI
import UIKit

@main
struct CouchStainApp: App {
    init() {
        if Launch.isUITesting,
           let code = ProcessInfo.processInfo.environment["COUCHSTAIN_TEST_PASTEBOARD"] {
            UIPasteboard.general.setItems([["public.utf8-plain-text": code]], options: [.localOnly: true])
        }
    }

    var body: some Scene {
        WindowGroup {
            RescueView()
                .preferredColorScheme(.light)
        }
    }
}

private enum Panel: String, Identifiable {
    case share, milestone, importCode
    var id: String { rawValue }
}

struct RescueView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @AccessibilityFocusState private var titleFocused: Bool

    private let defaults: UserDefaults
    @State private var state: CardState
    @State private var current: Selection?
    @State private var care: Care?
    @State private var changing: Selection?
    @State private var panel: Panel?
    @State private var panelIsVisible = false
    @State private var directShare = ShareExport()
    @State private var sourcesOpen = false
    @State private var pendingRating: Selection?
    @State private var providedFile: URL?
    @State private var queuedFile: URL?

    init() {
        let defaults = Launch.defaults()
        let saved = CardState.load(from: defaults)
        self.defaults = defaults
        _state = State(initialValue: saved)
        _care = State(initialValue: saved.lastCare)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id("screen-top").accessibilityHidden(true)
                Group {
                    if let current {
                        result(CareRules.card(for: current))
                    } else {
                        home
                    }
                }
                .frame(maxWidth: 500)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: current) { _, newValue in
                directShare.clearFeedback()
                proxy.scrollTo("screen-top", anchor: .top)
                if newValue != nil { titleFocused = true }
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
        .tint(Palette.accentText)
        .sheet(item: $panel, onDismiss: panelDismissed) { presented in
            Group {
                switch presented {
                case .importCode:
                    ImportView(providedFile: providedFile) { selection in
                        open(selection)
                        panel = nil
                    }
                case .share, .milestone:
                    if let current {
                        SharePreview(card: CareRules.card(for: current), milestone: presented == .milestone) { completedShare in
                            if completedShare { pendingRating = current }
                            panel = nil
                        }
                    }
                }
            }
            .onAppear { panelIsVisible = true }
        }
        .modifier(SharePresentation(export: directShare, finish: { completed in
            if completed { pendingRating = current }
        }, didDismiss: presentQueuedFileOrReview))
        .onChange(of: directShare.busy) { _, busy in
            if !busy && !directShare.isPresenting && queuedFile != nil { presentQueuedFileOrReview() }
        }
        .reviewAfterCoreAction(when: idleRating && current != nil && changing == nil && !sourcesOpen) { requestReview() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reviewIfReady() }
        }
        .onOpenURL { file in
            guard file.isFileURL else { return }
            if directShare.busy || directShare.isPresenting {
                queuedFile = file
            } else if panel == nil && !panelIsVisible {
                providedFile = file
                panel = .importCode
            } else {
                queuedFile = file
                panel = nil
            }
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    homeTitle
                    Spacer(minLength: 0)
                    importButton.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 2) {
                    homeTitle
                    importButton
                }
            }
            .padding(.bottom, 5)

            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("home.care")).font(.headline).accessibilityAddTraits(.isHeader)
                Text(L.t("home.tagHint")).font(.footnote).foregroundStyle(Palette.muted)
                ChoiceGrid(count: 4, compactCount: 2) {
                    ForEach(Care.codes) { item in
                        selectionButton(id: "care." + item.rawValue, selected: care == item) {
                            select(item)
                        } label: {
                            VStack(spacing: 2) {
                                Text(L.t(item.matchKey)).font(.title2.bold())
                                Text(L.t(item.key)).font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                        }
                        .accessibilityLabel(Text(L.f("care.voiceover", L.t(item.matchKey), L.t(item.key))))
                    }
                }
                ChoiceGrid(count: 3, compactCount: 1) {
                    ForEach(Care.materials) { item in
                        selectionButton(id: "care." + item.rawValue, selected: care == item) {
                            select(item)
                        } label: {
                            Text(L.t(item.key)).font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
            .rescuePanel()

            VStack(alignment: .leading, spacing: 7) {
                Text(L.t("home.stain")).font(.headline).accessibilityAddTraits(.isHeader)
                Text(care == nil ? L.t("home.chooseCare") : L.t("home.chooseStain"))
                    .font(.footnote).foregroundStyle(Palette.muted)

                ChoiceGrid(count: 2, compactCount: 1) {
                    ForEach(Stain.allCases.filter { $0 != .problem }) { item in stainButton(item) }
                }
                stainButton(.problem)
            }
            .rescuePanel()

            if state.recent != nil && changing == nil {
                rowButton("home.resume", icon: "chevron.right", id: "home.resume") {
                    if let recent = state.recent { open(recent) }
                }
            }
            if changing != nil {
                rowButton("home.returnCard", icon: "chevron.right", id: "home.returnCard") {
                    if let changing { open(changing) }
                }
            }
            Text(L.t("home.offline")).font(.footnote).foregroundStyle(Palette.muted)
                .padding(.top, 5)
        }
    }

    private var homeTitle: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L.t("home.title"))
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home.title")
            Text(L.t("home.subtitle")).font(.footnote).foregroundStyle(Palette.muted)
        }
    }

    private var importButton: some View {
        quietButton("import.title", id: "home.import") {
            providedFile = nil
            panel = .importCode
        }
    }

    private func stainButton(_ stain: Stain) -> some View {
        selectionButton(id: "stain." + stain.rawValue, selected: changing?.stain == stain, enabled: care != nil) {
            if let care {
                open(Selection(care: care, stain: stain))
                CoreReview.shared.record()
            }
        } label: {
            Text(L.t(stain.key)).font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(care == nil)
    }

    private func result(_ card: Card) -> some View {
        let checked = state.recent == card.selection && state.recentChecked
        let milestone = checked && state.firstChecked == card.selection
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        homeButton.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        changeButton(card).fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        homeButton
                        changeButton(card)
                    }
                }
                Text(card.selection.label())
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.accentText)
                Text(L.t(card.title)).font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("card.title")
                    .accessibilityFocused($titleFocused)
            }

            guidance("card.first", keys: card.firstSteps, sources: card.sourceRefs, fill: Palette.tint, prominent: true)
            guidance(card.allowsDryCheck ? "card.recheckDry" : "card.recheck",
                     keys: card.rechecks, sources: card.sourceRefs, fill: Palette.surface)
            guidance("card.stop", keys: card.stops, sources: card.sourceRefs, fill: Palette.caution)

            VStack(spacing: 7) {
                actionButton("share.image", id: "card.shareImage", primary: true) {
                    directShare.image(card: card, milestone: false)
                }
                if directShare.busy {
                    ProgressView(L.t("share.preparing"))
                }
                directShare.feedback()

                if checked {
                    Label(L.t("card.checked"), systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .foregroundStyle(Palette.accentText)
                        .background(Palette.tint, in: RoundedRectangle(cornerRadius: 11))
                        .accessibilityIdentifier("card.checked")
                } else if card.allowsDryCheck {
                    actionButton("card.markChecked", id: "card.markChecked", primary: true) {
                        if state.recordDryCheck(card) { state.save(to: defaults); pendingRating = current; reviewIfReady() }
                    }
                }
                if milestone {
                    actionButton("card.keep", id: "card.keep", primary: true) { panel = .milestone }
                }
                actionButton("share.titleButton", id: "card.share", primary: false) {
                    panel = .share
                }
            }

            rowButton("sources.title", icon: sourcesOpen ? "chevron.up" : "chevron.down", id: "card.sources") {
                sourcesOpen.toggle()
            }
            .accessibilityValue(Text(L.t(sourcesOpen ? "sources.expanded" : "sources.collapsed")))
            if sourcesOpen { sourceList(card) }
        }
        .disabled(directShare.busy)
    }

    private var homeButton: some View {
        Button {
            current = nil
            changing = nil
            care = state.lastCare
        } label: {
            Label(L.t("card.home"), systemImage: "chevron.left")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.accentText)
        .accessibilityIdentifier("card.home")
    }

    private func changeButton(_ card: Card) -> some View {
        quietButton("card.change", id: "card.change") {
            changing = card.selection
            care = card.selection.care
            current = nil
        }
    }

    private func guidance(_ heading: String, keys: [String], sources: [SourceID],
                          fill: Color, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t(heading)).font(prominent ? .footnote.weight(.bold) : .headline)
                .foregroundStyle(prominent ? Palette.accentText : Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(heading)
            ForEach(Array(keys.enumerated()), id: \.offset) { item in
                Text(L.t(item.element))
                    .font(prominent && item.offset == 0 ? .title3.weight(.semibold) : .subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(sources.map { L.t($0.name) }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(Palette.muted)
        }
        .rescuePanel(fill)
    }

    private func sourceList(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L.t("sources.priority")).font(.subheadline)
            Text(L.t("sources.checked")).font(.footnote).foregroundStyle(Palette.muted)
            ForEach(card.rules) { rule in
                Text(L.f("sources.rule", rule.id, L.t(rule.citation)))
                    .font(.footnote).foregroundStyle(Palette.muted)
            }
            ForEach(card.sourceRefs) { source in
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text(source.rawValue + " · " + L.t(source.name)).font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(L.t(source.scope)).font(.subheadline)
                    ForEach(source.urls, id: \.self) { url in
                        Link(destination: url) {
                            Text(url.absoluteString)
                                .font(.footnote)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                    }
                }
            }
        }
        .rescuePanel()
    }

    private func select(_ item: Care) {
        if let changing {
            open(Selection(care: item, stain: changing.stain))
            CoreReview.shared.record()
        } else {
            care = item
            state.lastCare = item
            state.save(to: defaults)
        }
    }

    private func open(_ selection: Selection) {
        state.open(selection)
        state.save(to: defaults)
        care = selection.care
        current = selection
        changing = nil
        sourcesOpen = false
    }

    private func panelDismissed() {
        panelIsVisible = false
        providedFile = nil
        presentQueuedFileOrReview()
    }

    private func presentQueuedFileOrReview() {
        if let queuedFile {
            providedFile = queuedFile
            self.queuedFile = nil
            panel = .importCode
        } else {
            reviewIfReady()
        }
    }

    private var idleRating: Bool {
        panel == nil && !panelIsVisible && !directShare.isPresenting && !directShare.busy
            && queuedFile == nil && providedFile == nil && !directShare.hasFailure && scenePhase == .active
    }

    private func reviewIfReady() {
        guard !Launch.isUITesting, idleRating, let pendingRating else { return }
        self.pendingRating = nil
        guard current == pendingRating else { return }
        let card = CareRules.card(for: pendingRating)
        var candidate = state
        guard CoreReview.shared.attempt(ifEligible: { candidate.consumeRatingAttempt(card: card, completedShare: true, idle: true) }, { requestReview() }) else { return }
        state = candidate
        state.save(to: defaults)
    }
}
