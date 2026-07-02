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
    private let keyboardTouchSurface = KeyboardTouchSurfaceView()
    private let keyPreviewCallout = KeyboardKeyPreviewCallout()
    private var keyButtons: [KeyboardKeyButton] = []
    private var highlightedKeyButton: KeyboardKeyButton?
    private var activeTouchKey: KeyboardKey?
    private var keyPreviewDismissal: DispatchWorkItem?
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
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private var viewWillAppearWasCalled = false
    private var lastAppliedMetricSize: CGSize = .zero

    var enableInputClicksWhenVisible: Bool {
        true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureInputViewShell()
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

    private func configureInputViewShell() {
        guard let inputView else { return }
        inputView.allowsSelfSizing = true
        inputView.clipsToBounds = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewWillAppearWasCalled = true
        view.setNeedsUpdateConstraints()
        feedbackController.prepare()
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()
        updateKeyboardHeightConstraintIfReady()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showSpaceLanguageIntro()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyLayoutMetricsIfNeeded()
        updateKeyboardTouchRegions()
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
        view.clipsToBounds = true
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: preferredActiveKeyboardHeight)
        heightConstraint.priority = UILayoutPriority.required - 1
        keyboardHeightConstraint = heightConstraint

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: KeyboardViewController, _) in
            controller.view.backgroundColor = .clear
            controller.view.clipsToBounds = true
            controller.view.setNeedsUpdateConstraints()
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
        keyboardStack.isUserInteractionEnabled = false
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardStack)
        keyboardTouchSurface.delegate = self
        view.addSubview(keyboardTouchSurface)
        keyPreviewCallout.alpha = 0
        keyPreviewCallout.isHidden = true
        view.addSubview(keyPreviewCallout)

        let insets = metrics.keyboardInsets
        let leadingConstraint = keyboardStack.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let trailingConstraint = keyboardStack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
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
            heightConstraint,

            keyboardTouchSurface.leadingAnchor.constraint(equalTo: keyboardStack.leadingAnchor),
            keyboardTouchSurface.trailingAnchor.constraint(equalTo: keyboardStack.trailingAnchor),
            keyboardTouchSurface.topAnchor.constraint(equalTo: keyboardStack.topAnchor),
            keyboardTouchSurface.bottomAnchor.constraint(equalTo: keyboardStack.bottomAnchor)
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
        hideKeyPreview(animated: false)
        clearHighlightedKey()
        activeTouchKey = nil
        keyButtons.removeAll(keepingCapacity: true)
        NSLayoutConstraint.deactivate(rowHeightConstraints)
        rowHeightConstraints.removeAll(keepingCapacity: true)
        keyboardStack.arrangedSubviews.forEach { view in
            keyboardStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let rows = KeyboardLayoutProvider.rows(for: keyboardMode)
        for row in rows {
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
        keyboardStack.setNeedsLayout()
        keyboardTouchSurface.keyRows = []
    }

    private func refreshKeyboard() {
        let metrics = currentMetrics
        updateKeyboardHeightConstraintIfReady()
        view.backgroundColor = .clear
        suggestionBar.isHidden = showsEmojiPanel
        keyboardStack.isHidden = showsEmojiPanel && !isEmojiSearchActive
        keyboardTouchSurface.isHidden = keyboardStack.isHidden
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

    private func handleKeyTouchDown(_ key: KeyboardKey) {
        if isEmojiSearchActive, key == .backspace {
            beginEmojiSearchBackspacePress()
            return
        }

        if key == .backspace {
            beginBackspacePress()
        } else {
            feedbackController.keyTouched(key)
        }
    }

    private func handleKeyRelease(_ key: KeyboardKey) {
        if key == .backspace {
            endBackspacePress()
        }
    }

    private func handleKeyPress(_ key: KeyboardKey) {
        if isEmojiSearchActive {
            if key == .backspace {
                endBackspacePress()
                return
            }
            handleEmojiSearchKeyPress(key)
            refreshKeyboard()
            return
        }

        switch key {
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

    private func beginEmojiSearchBackspacePress() {
        guard !backspaceRepeater.isActive else { return }

        guard performEmojiSearchBackspace() else { return }
        feedbackController.keyTouched(.backspace)
        backspaceRepeater.begin { [weak self] _ in
            guard let self else { return }
            guard performEmojiSearchBackspace() else {
                endBackspacePress()
                return
            }
            feedbackController.backspaceRepeated(unit: .character)
        }
    }

    @discardableResult
    private func performEmojiSearchBackspace() -> Bool {
        guard !emojiSearchQuery.isEmpty else {
            exitEmojiSearch()
            refreshKeyboard()
            return false
        }

        emojiSearchQuery.removeLast()
        syncEmojiSearchQuery()
        refreshKeyboard()
        return true
    }

    private func beginBackspacePress() {
        guard !backspaceRepeater.isActive else { return }

        guard performBackspace(unit: .character, requiresTextEvidence: true) else { return }
        feedbackController.keyTouched(.backspace)
        backspaceRepeater.begin { [weak self] _ in
            guard let self else { return }
            performBackspace(unit: .character, requiresTextEvidence: false)
            feedbackController.backspaceRepeated(unit: .character)
        }
    }

    private func endBackspacePress() {
        backspaceRepeater.end()
    }

    @discardableResult
    private func performBackspace(
        unit: BackspaceDeletionUnit,
        requiresTextEvidence: Bool = true
    ) -> Bool {
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
        guard !requiresTextEvidence || textDocumentProxy.hasText || contextBeforeInput?.isEmpty == false else {
            refreshSuggestions()
            return false
        }

        if unit == .character || contextBeforeInput?.isEmpty != false {
            performTextUpdate {
                textDocumentProxy.deleteBackward()
            }
            engine.clearAutosuggestSession()
            refreshSuggestions()
            return true
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
        if bounds.width > 0 {
            return KeyboardTheme.metrics(
                for: CGSize(width: bounds.width, height: preferredKeyboardHeight),
                traitCollection: traitCollection
            )
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

    private var preferredActiveKeyboardHeight: CGFloat {
        let screenSize = view.window?.screen.bounds.size ?? UIScreen.main.bounds.size
        if showsEmojiPanel {
            return KeyboardTheme.preferredEmojiKeyboardHeight(
                for: screenSize,
                traitCollection: traitCollection
            )
        }
        return KeyboardTheme.preferredKeyboardHeight(
            for: screenSize,
            traitCollection: traitCollection
        )
    }

    private func applyLayoutMetricsIfNeeded(force: Bool = false) {
        let size = view.bounds.size
        let preferredHeight = preferredActiveKeyboardHeight
        let metricSize = CGSize(width: size.width, height: preferredKeyboardHeight)
        let shouldReloadRows = force || metricSize != lastAppliedMetricSize
        guard shouldReloadRows || keyboardHeightConstraint?.constant != preferredHeight else {
            return
        }
        lastAppliedMetricSize = metricSize

        let metrics = currentMetrics
        let insets = metrics.keyboardInsets
        updateKeyboardHeightConstraintIfReady()
        keyboardStack.spacing = metrics.rowSpacing
        keyboardStackLeadingConstraint?.constant = 0
        keyboardStackTrailingConstraint?.constant = 0
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
        updateKeyboardTouchRegions()
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

    private func updateKeyboardHeightConstraintIfReady() {
        guard viewWillAppearWasCalled, let keyboardHeightConstraint else {
            return
        }

        keyboardHeightConstraint.constant = preferredActiveKeyboardHeight
        if !keyboardHeightConstraint.isActive {
            keyboardHeightConstraint.isActive = true
        }
    }

    private func beginTouch(on key: KeyboardKey) {
        activeTouchKey = key
        setHighlightedKey(key)
        handleKeyTouchDown(key)
    }

    private func moveTouch(to key: KeyboardKey) {
        guard key != activeTouchKey else { return }
        if let activeTouchKey {
            handleKeyRelease(activeTouchKey)
        }
        activeTouchKey = key
        setHighlightedKey(key)
        handleKeyTouchDown(key)
    }

    private func endTouch(on key: KeyboardKey?) {
        let finalKey = key ?? activeTouchKey
        if let finalKey, finalKey != activeTouchKey {
            moveTouch(to: finalKey)
        }
        if let activeTouchKey {
            handleKeyRelease(activeTouchKey)
        }
        clearHighlightedKey()
        activeTouchKey = nil
        if let finalKey {
            handleKeyPress(finalKey)
        }
    }

    private func cancelTouch() {
        if let activeTouchKey {
            handleKeyRelease(activeTouchKey)
        }
        clearHighlightedKey()
        activeTouchKey = nil
    }

    private func setHighlightedKey(_ key: KeyboardKey) {
        guard highlightedKeyButton?.key != key else { return }
        highlightedKeyButton?.isHighlighted = false
        let keyButton = keyButtons.first { $0.key == key }
        keyButton?.isHighlighted = true
        highlightedKeyButton = keyButton
        if let keyButton {
            showKeyPreview(for: keyButton)
        } else {
            hideKeyPreview(animated: false)
        }
    }

    private func clearHighlightedKey() {
        highlightedKeyButton?.isHighlighted = false
        highlightedKeyButton = nil
        scheduleKeyPreviewDismissal()
    }

    private func showKeyPreview(for button: KeyboardKeyButton) {
        keyPreviewDismissal?.cancel()
        keyPreviewDismissal = nil

        let metrics = currentMetrics
        guard
            metrics.keyPreviewHeight > 0,
            let previewText = button.previewText,
            !previewText.isEmpty
        else {
            hideKeyPreview(animated: false)
            return
        }

        keyPreviewCallout.update(
            text: previewText,
            metrics: metrics,
            traitCollection: traitCollection
        )

        let size = KeyboardKeyPreviewCallout.preferredSize(
            for: button.bounds,
            metrics: metrics
        )
        let frameInView = button.convert(button.bounds, to: view)
        let desiredX = frameInView.midX - size.width / 2
        let x = min(max(0, desiredX), max(0, view.bounds.width - size.width))
        let y = min(
            max(0, frameInView.minY - size.height + metrics.keyPreviewStemHeight + 2),
            max(0, view.bounds.height - size.height)
        )

        keyPreviewCallout.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        view.bringSubviewToFront(keyPreviewCallout)

        guard keyPreviewCallout.isHidden || keyPreviewCallout.alpha < 1 else {
            keyPreviewCallout.transform = .identity
            return
        }

        keyPreviewCallout.isHidden = false
        keyPreviewCallout.alpha = 0
        keyPreviewCallout.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        UIView.animate(
            withDuration: 0.055,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
        ) {
            self.keyPreviewCallout.alpha = 1
            self.keyPreviewCallout.transform = .identity
        }
    }

    private func scheduleKeyPreviewDismissal() {
        guard !keyPreviewCallout.isHidden else { return }
        keyPreviewDismissal?.cancel()
        let dismissal = DispatchWorkItem { [weak self] in
            self?.hideKeyPreview(animated: true)
        }
        keyPreviewDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.055, execute: dismissal)
    }

    private func hideKeyPreview(animated: Bool) {
        keyPreviewDismissal?.cancel()
        keyPreviewDismissal = nil
        guard !keyPreviewCallout.isHidden else { return }

        let finish = {
            self.keyPreviewCallout.alpha = 0
            self.keyPreviewCallout.transform = .identity
            self.keyPreviewCallout.isHidden = true
        }

        guard animated else {
            finish()
            return
        }

        UIView.animate(
            withDuration: 0.09,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseIn]
        ) {
            self.keyPreviewCallout.alpha = 0
            self.keyPreviewCallout.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        } completion: { _ in
            finish()
        }
    }

    private func updateKeyboardTouchRegions() {
        guard !keyboardStack.isHidden, keyboardTouchSurface.bounds.width > 0 else {
            keyboardTouchSurface.keyRows = []
            return
        }

        keyboardStack.layoutIfNeeded()
        let rows = keyboardStack.arrangedSubviews.compactMap { view -> [KeyboardTouchKeyRegion]? in
            guard let rowView = view as? KeyboardRowView else { return nil }
            let regions = rowView.keyRegions(in: keyboardTouchSurface)
            return regions.isEmpty ? nil : regions
        }
        keyboardTouchSurface.keyRows = rows
    }
}

extension KeyboardViewController: KeyboardTouchSurfaceViewDelegate {
    func keyboardTouchSurface(_ view: KeyboardTouchSurfaceView, didBegin key: KeyboardKey) {
        beginTouch(on: key)
    }

    func keyboardTouchSurface(_ view: KeyboardTouchSurfaceView, didMoveTo key: KeyboardKey) {
        moveTouch(to: key)
    }

    func keyboardTouchSurface(_ view: KeyboardTouchSurfaceView, didEnd key: KeyboardKey?) {
        endTouch(on: key)
    }

    func keyboardTouchSurfaceDidCancel(_ view: KeyboardTouchSurfaceView) {
        cancelTouch()
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

    func emojiPanelViewDidRequestClearSearch(_ view: EmojiPanelView) {
        feedbackController.suggestionAccepted()
        emojiSearchQuery = ""
        syncEmojiSearchQuery()
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
        endBackspacePress()
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
