import UIKit

final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {
    private let engine = ObadhBridgeClient.shared
    private let composer = KeyboardComposer(engine: ObadhBridgeClient.shared)
    private let compositionController = TextCompositionController()
    private let punctuationBuffer = KeyboardPunctuationBuffer()
    private let personalAutosuggestStore = PersonalAutosuggestStore()
    private let feedbackController = KeyboardFeedbackController()
    private let backspaceRepeater = BackspaceRepeatController()
    private let suggestionBar = SuggestionBarView()
    private let emojiPanelView = EmojiPanelView()
    private let emojiRecentStore = EmojiRecentStore()
    private lazy var emojiDataStore = EmojiDataStore(bundle: Bundle(for: KeyboardViewController.self))
    private let keyboardStack = UIStackView()
    private var keyButtons: [KeyboardKeyButton] = []
    private var shifted = false
    private var keyboardMode: KeyboardMode = .letters
    private var isUpdatingTextProxy = false
    private var showsSpaceLanguageIntro = false
    private var showsEmojiPanel = false
    private var isEmojiSearchActive = false
    private var emojiSearchQuery = ""
    private var spaceLanguageIntroDismissal: DispatchWorkItem?
    private var keyboardStackLeadingConstraint: NSLayoutConstraint?
    private var keyboardStackTrailingConstraint: NSLayoutConstraint?
    private var keyboardStackTopConstraint: NSLayoutConstraint?
    private var keyboardStackBottomConstraint: NSLayoutConstraint?
    private var keyboardStackHeightConstraint: NSLayoutConstraint?
    private var rowHeightConstraints: [NSLayoutConstraint] = []
    private var emojiPanelBottomToSafeAreaConstraint: NSLayoutConstraint?
    private var emojiPanelBottomToKeyboardConstraint: NSLayoutConstraint?
    private var lastAppliedMetricSize: CGSize = .zero

    var enableInputClicksWhenVisible: Bool {
        true
    }

    override func loadView() {
        let inputView = UIInputView(frame: .zero, inputViewStyle: .keyboard)
        inputView.allowsSelfSizing = true
        view = inputView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let configuration = engine.configureModels(in: Bundle(for: KeyboardViewController.self))
        if configuration.autosuggestAvailable {
            restorePersonalAutosuggest()
        }
        feedbackController.prepare()
        configureRootView()
        configureSuggestionBar()
        configureEmojiPanel()
        reloadKeyboardRows()
        refreshKeyboard()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        feedbackController.prepare()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showSpaceLanguageIntro()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyLayoutMetricsIfNeeded()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        guard !isUpdatingTextProxy else { return }
        composer.clear()
        compositionController.resetHostState()
        punctuationBuffer.reset()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        guard !isUpdatingTextProxy else { return }
        if !composer.hasActiveInput,
           (textDocumentProxy.documentContextBeforeInput ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty {
            engine.clearAutosuggestSession()
        }
        refreshSuggestions()
    }

    private func configureRootView() {
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = false

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: KeyboardViewController, _) in
            controller.view.backgroundColor = .clear
            controller.applyLayoutMetricsIfNeeded(force: true)
            controller.refreshKeyboard()
        }
    }

    private func configureSuggestionBar() {
        suggestionBar.delegate = self
        view.addSubview(suggestionBar)

        let metrics = currentMetrics
        keyboardStack.axis = .vertical
        keyboardStack.alignment = .fill
        keyboardStack.distribution = .fill
        keyboardStack.spacing = metrics.rowSpacing
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardStack)

        let insets = metrics.keyboardInsets
        let leadingConstraint = keyboardStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: insets.left)
        let trailingConstraint = keyboardStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -insets.right)
        let topConstraint = keyboardStack.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor, constant: insets.top)
        let bottomConstraint = keyboardStack.bottomAnchor.constraint(
            lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -insets.bottom
        )
        let heightConstraint = keyboardStack.heightAnchor.constraint(equalToConstant: keyRowsHeight(for: metrics))
        heightConstraint.priority = UILayoutPriority(999)
        keyboardStackLeadingConstraint = leadingConstraint
        keyboardStackTrailingConstraint = trailingConstraint
        keyboardStackTopConstraint = topConstraint
        keyboardStackBottomConstraint = bottomConstraint
        keyboardStackHeightConstraint = heightConstraint
        suggestionBar.applyMetrics(metrics)

        NSLayoutConstraint.activate([
            suggestionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            suggestionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            suggestionBar.topAnchor.constraint(equalTo: view.topAnchor),

            leadingConstraint,
            trailingConstraint,
            topConstraint,
            bottomConstraint,
            heightConstraint
        ])
    }

    private func configureEmojiPanel() {
        emojiPanelView.delegate = self
        emojiPanelView.configure(
            dataStore: emojiDataStore,
            recentEmojis: emojiRecentStore.load()
        )
        view.addSubview(emojiPanelView)

        let bottomToSafeArea = emojiPanelView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        let bottomToKeyboard = emojiPanelView.bottomAnchor.constraint(
            equalTo: keyboardStack.topAnchor,
            constant: -6
        )
        bottomToKeyboard.isActive = false
        emojiPanelBottomToSafeAreaConstraint = bottomToSafeArea
        emojiPanelBottomToKeyboardConstraint = bottomToKeyboard

        NSLayoutConstraint.activate([
            emojiPanelView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emojiPanelView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emojiPanelView.topAnchor.constraint(equalTo: view.topAnchor),
            bottomToSafeArea
        ])
    }

    private func reloadKeyboardRows() {
        let metrics = currentMetrics
        keyButtons.removeAll(keepingCapacity: true)
        NSLayoutConstraint.deactivate(rowHeightConstraints)
        rowHeightConstraints.removeAll(keepingCapacity: true)
        keyboardStack.arrangedSubviews.forEach { view in
            keyboardStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for row in KeyboardLayoutProvider.rows(for: keyboardMode) {
            let rowView = KeyboardRowView()
            rowView.translatesAutoresizingMaskIntoConstraints = false
            var rowButtons: [KeyboardKeyButton] = []
            rowButtons.reserveCapacity(row.keys.count)

            for key in row.keys {
                let button = KeyboardKeyButton(key: key)
                button.updateAppearance(
                    shifted: shifted,
                    traitCollection: traitCollection,
                    metrics: metrics,
                    showsSpaceIntro: showsSpaceLanguageIntro && !isEmojiSearchActive,
                    spaceCaption: spaceCaption
                )
                button.addTarget(self, action: #selector(handleKeyTouchDown(_:)), for: .touchDown)
                button.addTarget(self, action: #selector(handleKeyTouchDown(_:)), for: .touchDragEnter)
                button.addTarget(self, action: #selector(handleKeyPress(_:)), for: .touchUpInside)
                button.addTarget(
                    self,
                    action: #selector(handleKeyRelease(_:)),
                    for: [.touchDragExit, .touchUpOutside, .touchCancel]
                )
                rowButtons.append(button)
                keyButtons.append(button)
            }

            rowView.configure(row: row, buttons: rowButtons, metrics: metrics)
            keyboardStack.addArrangedSubview(rowView)
            let heightConstraint = rowView.heightAnchor.constraint(equalToConstant: metrics.minimumKeyHeight)
            heightConstraint.priority = UILayoutPriority(999)
            heightConstraint.isActive = true
            rowHeightConstraints.append(heightConstraint)
        }
    }

    private func refreshKeyboard() {
        let metrics = currentMetrics
        view.backgroundColor = .clear
        suggestionBar.isHidden = showsEmojiPanel
        keyboardStack.isHidden = showsEmojiPanel && !isEmojiSearchActive
        emojiPanelView.isHidden = !showsEmojiPanel
        emojiPanelView.setSearchActive(isEmojiSearchActive)
        emojiPanelBottomToSafeAreaConstraint?.isActive = !isEmojiSearchActive
        emojiPanelBottomToKeyboardConstraint?.isActive = isEmojiSearchActive
        keyboardStackTopConstraint?.constant = keyboardTopConstant(for: metrics)
        for button in keyButtons {
            button.updateAppearance(
                shifted: shifted,
                traitCollection: traitCollection,
                metrics: metrics,
                showsSpaceIntro: showsSpaceLanguageIntro && !isEmojiSearchActive,
                spaceCaption: spaceCaption
            )
        }
        refreshSuggestions()
    }

    private func refreshSuggestions() {
        if composer.hasActiveInput {
            suggestionBar.update(suggestions: composer.activeSuggestions)
        } else {
            let contextBeforeInput = textDocumentProxy.documentContextBeforeInput ?? ""
            guard contextBeforeInput.contains(where: { !$0.isWhitespace }) else {
                suggestionBar.update(suggestions: [])
                return
            }

            let sessionSuggestions = engine
                .autosuggestSessionSuggestions(limit: 6)
                .map { KeyboardSuggestion(text: $0, source: .autosuggest) }
            let contextSuggestions = composer.contextSuggestions(context: contextBeforeInput, limit: 6)
            let suggestions = KeyboardComposer.mergeSuggestions(
                primary: sessionSuggestions,
                fallback: contextSuggestions,
                limit: 3
            )
            suggestionBar.update(suggestions: suggestions)
        }
    }

    private func showSpaceLanguageIntro() {
        spaceLanguageIntroDismissal?.cancel()
        showsSpaceLanguageIntro = true
        refreshKeyboard()

        let dismissal = DispatchWorkItem { [weak self] in
            guard let self else { return }
            showsSpaceLanguageIntro = false
            for button in keyButtons where button.key == .space {
                UIView.transition(
                    with: button,
                    duration: 0.22,
                    options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState]
                ) {
                    button.updateAppearance(
                        shifted: self.shifted,
                        traitCollection: self.traitCollection,
                        metrics: self.currentMetrics,
                        showsSpaceIntro: false,
                        spaceCaption: self.spaceCaption
                    )
                }
            }
        }
        spaceLanguageIntroDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35, execute: dismissal)
    }

    @objc private func handleKeyTouchDown(_ sender: KeyboardKeyButton) {
        if sender.key == .backspace {
            beginBackspacePress()
        } else {
            feedbackController.keyTouched(sender.key)
        }
    }

    @objc private func handleKeyRelease(_ sender: KeyboardKeyButton) {
        if sender.key == .backspace {
            backspaceRepeater.end()
        }
    }

    @objc private func handleKeyPress(_ sender: KeyboardKeyButton) {
        if isEmojiSearchActive {
            handleEmojiSearchKeyPress(sender.key)
            refreshKeyboard()
            return
        }

        switch sender.key {
        case let .character(value):
            punctuationBuffer.reset()
            composer.append(shifted ? value.uppercased() : value)
            shifted = false
            refreshCompositionPreview()
        case let .symbol(symbol):
            if symbol.role == .sentenceTerminator {
                if !commitActiveInputWithSentenceTerminator(symbol.output) {
                    performTextUpdate {
                        let inserted = applyPunctuationRawInput(symbol.output)
                        observeAutosuggestBoundary(inserted)
                    }
                }
            } else if !commitActiveInputIfNeeded(trailingText: symbol.output) {
                punctuationBuffer.reset()
                performTextUpdate {
                    textDocumentProxy.insertText(symbol.output)
                }
            }
        case .space:
            punctuationBuffer.reset()
            if !commitActiveInputIfNeeded(trailingText: " ") {
                performTextUpdate {
                    insertSpaceIfNeeded()
                }
            }
        case .returnKey:
            punctuationBuffer.reset()
            if !commitActiveInputIfNeeded(trailingText: "\n") {
                engine.clearAutosuggestSession()
                performTextUpdate {
                    textDocumentProxy.insertText("\n")
                }
            }
        case .backspace:
            backspaceRepeater.end()
        case .shift:
            punctuationBuffer.reset()
            shifted.toggle()
        case let .modeSwitch(value):
            punctuationBuffer.reset()
            switch value {
            case "123":
                keyboardMode = .numbers
            case "#+=":
                keyboardMode = .symbols
            default:
                keyboardMode = .letters
            }
            shifted = false
            reloadKeyboardRows()
        case .emoji:
            punctuationBuffer.reset()
            showEmojiPanel()
        }
        refreshKeyboard()
    }

    private func showEmojiPanel() {
        if composer.hasActiveInput {
            _ = commitActiveInputIfNeeded()
        }
        showsEmojiPanel = true
        isEmojiSearchActive = false
        emojiSearchQuery = ""
        emojiPanelView.configure(
            dataStore: emojiDataStore,
            recentEmojis: emojiRecentStore.load()
        )
    }

    private func hideEmojiPanel() {
        showsEmojiPanel = false
        isEmojiSearchActive = false
        emojiSearchQuery = ""
        emojiPanelView.setSearchQuery("")
        emojiPanelView.setSearchActive(false)
        keyboardMode = .letters
        shifted = false
        reloadKeyboardRows()
    }

    private func enterEmojiSearch() {
        guard showsEmojiPanel else { return }
        isEmojiSearchActive = true
        emojiSearchQuery = ""
        shifted = false
        keyboardMode = .letters
        emojiPanelView.setSearchActive(true)
        emojiPanelView.setSearchQuery(emojiSearchQuery)
        reloadKeyboardRows()
    }

    private func exitEmojiSearch() {
        isEmojiSearchActive = false
        emojiSearchQuery = ""
        emojiPanelView.setSearchQuery("")
        emojiPanelView.setSearchActive(false)
        keyboardMode = .letters
        shifted = false
        reloadKeyboardRows()
    }

    private func handleEmojiSearchKeyPress(_ key: KeyboardKey) {
        punctuationBuffer.reset()

        switch key {
        case let .character(value):
            emojiSearchQuery.append(shifted ? value.uppercased() : value)
            shifted = false
            syncEmojiSearchQuery()
        case let .symbol(symbol):
            emojiSearchQuery.append(symbol.output)
            syncEmojiSearchQuery()
        case .space:
            if emojiSearchQuery.last?.isWhitespace != true {
                emojiSearchQuery.append(" ")
                syncEmojiSearchQuery()
            }
        case .returnKey, .emoji:
            exitEmojiSearch()
        case .backspace:
            if emojiSearchQuery.isEmpty {
                exitEmojiSearch()
            } else {
                emojiSearchQuery.removeLast()
                syncEmojiSearchQuery()
            }
        case .shift:
            shifted.toggle()
        case let .modeSwitch(value):
            switch value {
            case "123":
                keyboardMode = .numbers
            case "#+=":
                keyboardMode = .symbols
            default:
                keyboardMode = .letters
            }
            shifted = false
            reloadKeyboardRows()
        }
    }

    private func syncEmojiSearchQuery() {
        emojiPanelView.setSearchQuery(emojiSearchQuery)
    }

    private func beginBackspacePress() {
        guard !backspaceRepeater.isActive else { return }

        guard performBackspace(unit: .character) else { return }
        feedbackController.keyTouched(.backspace)
        backspaceRepeater.begin { [weak self] unit in
            guard let self else { return }
            guard performBackspace(unit: unit) else {
                backspaceRepeater.end()
                return
            }
            feedbackController.backspaceRepeated(unit: unit)
        }
    }

    @discardableResult
    private func performBackspace(unit: BackspaceDeletionUnit) -> Bool {
        punctuationBuffer.reset()

        if composer.hasActiveInput {
            switch unit {
            case .character:
                if composer.deleteBackward() {
                    refreshCompositionPreview()
                    return true
                }
            case .word, .sentence, .availableContext:
                composer.clear()
                performTextUpdate {
                    compositionController.clearMarkedText(in: documentEditor)
                }
                refreshSuggestions()
                return true
            }
        }

        let contextBeforeInput = textDocumentProxy.documentContextBeforeInput
        guard contextBeforeInput?.isEmpty != true else {
            refreshSuggestions()
            return false
        }
        guard textDocumentProxy.hasText || contextBeforeInput != nil else {
            refreshSuggestions()
            return false
        }

        let deleteCount = BackspaceDeletionPlanner.deleteCount(
            before: contextBeforeInput ?? "",
            unit: unit
        )
        guard deleteCount > 0 else {
            performTextUpdate {
                textDocumentProxy.deleteBackward()
            }
            refreshSuggestions()
            return true
        }

        performTextUpdate {
            for _ in 0..<deleteCount {
                textDocumentProxy.deleteBackward()
            }
        }
        engine.clearAutosuggestSession()
        refreshSuggestions()
        return true
    }

    @discardableResult
    private func commitActiveInputIfNeeded(trailingText: String = "") -> Bool {
        guard composer.hasActiveInput else { return false }
        guard let committed = composer.commitActiveInput() else { return false }
        performTextUpdate {
            compositionController.commitText(committed, trailingText: trailingText, in: documentEditor)
        }
        observeCommittedToken(committed)
        observeAutosuggestBoundary(trailingText)
        return true
    }

    @discardableResult
    private func commitActiveInputWithSentenceTerminator(_ rawInput: String) -> Bool {
        guard composer.hasActiveInput else { return false }
        guard let committed = composer.commitActiveInput() else { return false }
        let operation = punctuationBuffer.append(
            rawInput,
            contextBeforeInput: committed,
            engine: engine
        )
        performTextUpdate {
            compositionController.commitText(committed, trailingText: operation.insertion, in: documentEditor)
        }
        observeCommittedToken(committed)
        observeAutosuggestBoundary(operation.insertion)
        return true
    }

    private func refreshCompositionPreview() {
        performTextUpdate {
            compositionController.updateMarkedText(composer.preview, in: documentEditor)
        }
    }

    private func commitMarkedSuggestion(_ text: String) {
        performTextUpdate {
            compositionController.commitSuggestion(text, in: documentEditor)
        }
    }

    private func performTextUpdate(_ update: () -> Void) {
        isUpdatingTextProxy = true
        defer { isUpdatingTextProxy = false }
        update()
    }

    private func insertSpaceIfNeeded() {
        compositionController.insertSpaceIfNeeded(in: documentEditor)
    }

    private func applyPunctuationRawInput(_ rawInput: String) -> String {
        let operation = punctuationBuffer.append(
            rawInput,
            contextBeforeInput: textDocumentProxy.documentContextBeforeInput ?? "",
            engine: engine
        )
        for _ in 0..<operation.deletePreviousCharacterCount {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(operation.insertion)
        return operation.insertion
    }

    private func restorePersonalAutosuggest() {
        guard let snapshot = personalAutosuggestStore.loadSnapshot() else {
            return
        }
        if !engine.importPersonalAutosuggestSnapshot(snapshot) {
            personalAutosuggestStore.removeSnapshot()
        }
    }

    private func observeCommittedToken(_ token: String) {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        if engine.commitAutosuggestToken(token),
           let snapshot = engine.exportPersonalAutosuggestSnapshot() {
            personalAutosuggestStore.saveSnapshot(snapshot)
        }
    }

    private func observeAutosuggestBoundary(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        if text.contains(where: \.isNewline) {
            engine.clearAutosuggestSession()
        }
    }

    private var documentEditor: DocumentProxyEditor {
        DocumentProxyEditor(proxy: textDocumentProxy)
    }

    private var currentMetrics: KeyboardMetrics {
        let bounds = view.bounds.size
        if bounds.width > 0, bounds.height > 0 {
            return KeyboardTheme.metrics(for: bounds, traitCollection: traitCollection)
        }
        let screenSize = view.window?.screen.bounds.size ?? UIScreen.main.bounds.size
        return KeyboardTheme.metrics(
            for: CGSize(width: min(screenSize.width, screenSize.height), height: preferredKeyboardHeight),
            traitCollection: traitCollection
        )
    }

    private var preferredKeyboardHeight: CGFloat {
        KeyboardTheme.preferredKeyboardHeight(
            for: view.window?.screen.bounds.size ?? UIScreen.main.bounds.size,
            traitCollection: traitCollection
        )
    }

    private func applyLayoutMetricsIfNeeded(force: Bool = false) {
        let size = view.bounds.size
        let shouldReloadRows = force || size != lastAppliedMetricSize
        guard shouldReloadRows else {
            return
        }
        lastAppliedMetricSize = size

        let metrics = currentMetrics
        let insets = metrics.keyboardInsets
        keyboardStack.spacing = metrics.rowSpacing
        keyboardStackLeadingConstraint?.constant = insets.left
        keyboardStackTrailingConstraint?.constant = -insets.right
        keyboardStackTopConstraint?.constant = keyboardTopConstant(for: metrics)
        keyboardStackBottomConstraint?.constant = -insets.bottom
        keyboardStackHeightConstraint?.constant = keyRowsHeight(for: metrics)
        view.backgroundColor = .clear
        suggestionBar.applyMetrics(metrics)

        if shouldReloadRows {
            reloadKeyboardRows()
            refreshSuggestions()
            return
        }

        for case let rowView as KeyboardRowView in keyboardStack.arrangedSubviews {
            rowView.metrics = metrics
            rowView.setNeedsLayout()
        }
        for constraint in rowHeightConstraints {
            constraint.constant = metrics.minimumKeyHeight
        }
        for button in keyButtons {
            button.updateAppearance(
                shifted: shifted,
                traitCollection: traitCollection,
                metrics: metrics,
                showsSpaceIntro: showsSpaceLanguageIntro && !isEmojiSearchActive,
                spaceCaption: spaceCaption
            )
        }
    }

    private var spaceCaption: String {
        isEmojiSearchActive ? "En" : "বাংলা"
    }

    private func keyboardTopConstant(for metrics: KeyboardMetrics) -> CGFloat {
        guard isEmojiSearchActive else {
            return metrics.keyboardInsets.top
        }

        let keyRowsHeight = keyRowsHeight(for: metrics)
        let targetTop = max(
            metrics.suggestionHeight + metrics.keyboardInsets.top,
            view.bounds.height - keyRowsHeight - metrics.keyboardInsets.bottom
        )
        return targetTop - metrics.suggestionHeight
    }

    private func keyRowsHeight(for metrics: KeyboardMetrics) -> CGFloat {
        let rowCount = CGFloat(KeyboardLayoutProvider.rows(for: keyboardMode).count)
        guard rowCount > 0 else { return 0 }
        return rowCount * metrics.minimumKeyHeight + max(0, rowCount - 1) * metrics.rowSpacing
    }
}

extension KeyboardViewController: SuggestionBarViewDelegate {
    func suggestionBar(_ suggestionBar: SuggestionBarView, didSelect suggestion: KeyboardSuggestion) {
        feedbackController.suggestionAccepted()
        if composer.hasActiveInput {
            guard suggestion.source != .deterministic else { return }
            commitMarkedSuggestion(suggestion.text)
            composer.clear()
            observeCommittedToken(suggestion.text)
        } else {
            performTextUpdate {
                compositionController.commitNextWordSuggestion(suggestion.text, in: documentEditor)
            }
            observeCommittedToken(suggestion.text)
            observeAutosuggestBoundary(" ")
        }
        refreshKeyboard()
    }
}

extension KeyboardViewController: EmojiPanelViewDelegate {
    func emojiPanelView(_ view: EmojiPanelView, didSelect item: EmojiItem) {
        feedbackController.suggestionAccepted()
        performTextUpdate {
            textDocumentProxy.insertText(item.emoji)
        }
        emojiRecentStore.record(item.emoji)
        view.recordRecentEmoji(item.emoji)
    }

    func emojiPanelViewDidRequestSearch(_ view: EmojiPanelView) {
        feedbackController.suggestionAccepted()
        enterEmojiSearch()
        refreshKeyboard()
    }

    func emojiPanelViewDidRequestKeyboard(_ view: EmojiPanelView) {
        feedbackController.suggestionAccepted()
        hideEmojiPanel()
        refreshKeyboard()
    }

    func emojiPanelViewDidBeginBackspace(_ view: EmojiPanelView) {
        beginBackspacePress()
    }

    func emojiPanelViewDidEndBackspace(_ view: EmojiPanelView) {
        backspaceRepeater.end()
    }
}

private struct DocumentProxyEditor: TextDocumentEditing {
    let proxy: any UITextDocumentProxy

    var contextBeforeInput: String? {
        proxy.documentContextBeforeInput
    }

    func insertText(_ text: String) {
        proxy.insertText(text)
    }

    func setMarkedText(_ text: String, selectedRange: NSRange) {
        proxy.setMarkedText(text, selectedRange: selectedRange)
    }

    func unmarkText() {
        proxy.unmarkText()
    }
}
