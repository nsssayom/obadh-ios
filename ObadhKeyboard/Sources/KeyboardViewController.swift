import UIKit
import os

final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {
    /// Lifecycle telemetry so the running extension can be observed on the
    /// Simulator via: `xcrun simctl spawn booted log stream --predicate
    /// 'subsystem == "com.nsssayom.obadh.keyboard"'`.
    private let lifecycleLog = Logger(subsystem: "com.nsssayom.obadh.keyboard", category: "lifecycle")
    private let engine = ObadhBridgeClient.shared
    private lazy var composer = KeyboardComposer(
        engine: ObadhBridgeClient.shared,
        emojiSuggester: BanglaEmojiSuggestionStore(bundle: Bundle(for: KeyboardViewController.self))
    )
    private let compositionController = TextCompositionController()
    private let personalAutosuggestStore = PersonalAutosuggestStore()
    /// Words the user has committed, protected from auto-insert corrections.
    private let learnedWordStore = LearnedWordStore()
    /// Serial queue for heavy engine work (snapshot export/write) so it stays
    /// off the main thread while remaining serialized against the Rust session.
    private let engineQueue = DispatchQueue(label: "com.nsssayom.obadh.engine", qos: .userInitiated)
    private let feedbackController = KeyboardFeedbackController()
    private let backspaceRepeater = BackspaceRepeatController()
    private let suggestionBar = SuggestionBarView()
    private let emojiPanelView = EmojiPanelView()
    private let emojiRecentStore = EmojiRecentStore()
    // Per-emoji skin-tone memory, shared with the emoji panel (same App Group
    // store), so a tone picked anywhere is remembered everywhere.
    private let emojiVariantPreferenceStore = EmojiVariantPreferenceStore()
    private lazy var emojiDataStore = EmojiDataStore(bundle: Bundle(for: KeyboardViewController.self))
    private let keyboardStack = UIStackView()
    // The system's own keyboard backdrop material (blur + tint). On iOS 26 this
    // adopts the Liquid Glass keyboard look automatically, and it is
    // non-transparent so touches over the inter-key gaps still reach the clear
    // KeyboardTouchSurfaceView. Preferred over a hand-rolled UIVisualEffect,
    // which reads as a distinct rectangle vs. the surrounding keyboard.
    private let keyboardBackgroundView = UIInputView(frame: .zero, inputViewStyle: .keyboard)
    private let keyboardTouchSurface = KeyboardTouchSurfaceView()
    private let keyPreviewCallout = KeyboardKeyPreviewCallout()
    /// iOS 26+ Liquid Glass group hosting `keyboardStack`, so all per-key glass
    /// views render in a single merged pass instead of ~33 separate ones. nil
    /// below iOS 26, where keys use the solid fill and the stack lives directly
    /// on `view`.
    private var keyboardGlassContainer: UIVisualEffectView?
    #if DEBUG
    // Agentic control channel — DEBUG builds only (see KeyboardDebugChannel).
    private lazy var debugChannel = KeyboardDebugChannel(handler: self)
    #endif
    private var keyButtons: [KeyboardKeyButton] = []
    private var highlightedKeyButton: KeyboardKeyButton?
    private var activeTouchKey: KeyboardKey?
    private var keyPreviewDismissal: DispatchWorkItem?
    private var shifted = false
    private var keyboardMode: KeyboardMode = .letters
    private var previousKeyWasSpace = false
    /// Native's double-space shortcut is a QUICK double-tap, not "any two spaces":
    /// only a second space inside this window converts to dari; a slower one types a
    /// plain space. Monotonic clock so host clock changes can't confuse it.
    private static let dariDoubleSpaceWindow: TimeInterval = 0.35
    private var lastSpaceKeyTime: CFTimeInterval = 0
    private var suggestionGeneration = 0
    private var isUpdatingTextProxy = false
    /// Set while the suggestion bar is showing corrections for an already-committed word
    /// the cursor sits in, so a tap replaces that word rather than inserting a next word.
    private var activeCursorWord: CursorWord?
    /// Whether the deterministic literal currently shown is NOT a dictionary word. When
    /// true the first suggestion slot is quoted ("keep my spelling"), native-style,
    /// independent of the auto-insert setting. Computed off-main each settle; reset
    /// before every composition refresh so a stale quote never shows.
    private var deterministicIsOOV = false
    private var showsSpaceLanguageIntro = false
    private var showsEmojiPanel = false
    private var isEmojiSearchActive = false
    private var emojiSearchQuery = ""
    private var emojiSearchLanguage: EmojiSearchLanguage = .english
    private let keyboardPreferences = KeyboardPreferences()
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
    // Legacy-presentation detection state (see recordPresentationTransient).
    private var presentationTransients: [CGFloat] = []
    private var presentationClassified = false

    #if DEBUG
    /// On-keyboard overlay dumping the presentation context iOS hands us in the current
    /// host app. Toggle from the app's debug panel; capture in Messenger vs Safari vs a
    /// legacy app to learn how the system frames the extension, then adapt to match.
    private let presentationProbeLabel = UILabel()
    /// Fiducial hairlines at the view's top edge and the strip's bottom, so any
    /// screenshot self-certifies our geometry (band = container edge → top hairline;
    /// strip = distance between the two lines) with no detector heuristics.
    private let probeTopHairline = UIView()
    private let probeStripHairline = UIView()
    private var lastProbeString = ""
    #endif

    var enableInputClicksWhenVisible: Bool {
        true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        lifecycleLog.notice("OBADH-LIFECYCLE viewDidLoad — extension loaded, backdrop=\(String(describing: type(of: self.keyboardBackgroundView)), privacy: .public)")
        recordFullAccessIfGranted()
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
        #if DEBUG
        startKeyTintObserver()
        configurePresentationProbe()
        #endif
    }

    deinit {
        #if DEBUG
        stopKeyTintObserver()
        #endif
    }

    #if DEBUG
    /// Live native-parity tuning: the containing app posts a Darwin notification when
    /// a key-tint slider changes; re-style the keys so the change shows without a
    /// rebuild. DEBUG only.
    private func startKeyTintObserver() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let controller = Unmanaged<KeyboardViewController>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    // A debug tunable changed. Drop the memoized metrics (its cache key
                    // ignores debug values) and force a relayout so shadow, key tint,
                    // and suggestion height all re-read at once.
                    controller.metricsCache = nil
                    controller.applyLayoutMetricsIfNeeded(force: true)
                    controller.refreshKeyboard()
                }
            },
            KeyboardPreferences.debugKeyTintDarwinName as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func stopKeyTintObserver() {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(KeyboardPreferences.debugKeyTintDarwinName as CFString),
            nil
        )
    }

    /// A yellow top-left overlay reporting the geometry iOS hands the extension: view
    /// bounds, safe-area insets, window vs screen width (side-inset tell), the height
    /// constraint, and the nearest rounded-corner ancestor (the system's container
    /// silhouette). Read it in different host apps to see legacy vs Liquid Glass framing.
    private func configurePresentationProbe() {
        presentationProbeLabel.numberOfLines = 0
        presentationProbeLabel.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        presentationProbeLabel.textColor = .systemYellow
        presentationProbeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        presentationProbeLabel.isUserInteractionEnabled = false
        presentationProbeLabel.isHidden = true
        presentationProbeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(presentationProbeLabel)
        NSLayoutConstraint.activate([
            presentationProbeLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            presentationProbeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4)
        ])
        for line in [probeTopHairline, probeStripHairline] {
            line.backgroundColor = .systemYellow
            line.isUserInteractionEnabled = false
            line.isHidden = true
            view.addSubview(line)
        }
    }

    private func updatePresentationProbe() {
        let enabled = keyboardPreferences.debugPresentationProbeEnabled
        presentationProbeLabel.isHidden = !enabled
        probeTopHairline.isHidden = !enabled
        probeStripHairline.isHidden = !enabled
        guard enabled else { return }
        let text = presentationProbeString()
        presentationProbeLabel.text = text
        let hairline = 1 / (view.window?.screen.scale ?? 3)
        probeTopHairline.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: hairline)
        probeStripHairline.frame = CGRect(
            x: 0,
            y: currentMetrics.suggestionHeight,
            width: view.bounds.width,
            height: hairline
        )
        view.bringSubviewToFront(probeTopHairline)
        view.bringSubviewToFront(probeStripHairline)
        view.bringSubviewToFront(presentationProbeLabel)
        if text != lastProbeString {
            lastProbeString = text
            lifecycleLog.notice("OBADH-PROBE \(text.replacingOccurrences(of: "\n", with: " · "), privacy: .public)")
        }
    }

    private func presentationProbeString() -> String {
        let b = view.bounds
        let sa = view.safeAreaInsets
        // frame-in-window is the smoking gun for height fights: origin.y > 0 means the
        // container is taller than our view and the system bottom-anchored us in it
        // (the "extra band above the suggestions" presentation); win is the container
        // the system actually granted, hCon what we asked for.
        let win = view.window
        let frame = win.map { view.convert(view.bounds, to: $0) } ?? .zero
        let winSize = win?.bounds.size ?? .zero
        let scrW = win?.screen.bounds.width ?? UIScreen.main.bounds.width
        let ivH = inputView?.bounds.height ?? 0
        let hActive = keyboardHeightConstraint?.isActive ?? false
        let selfSizing = inputView?.allowsSelfSizing ?? false
        // wf = the extension window's frame in SCREEN coordinates: with the screen
        // height it answers exactly where the system placed us — dock height below
        // (scrH - wfY - winH) and any system band above our view inside the container.
        let winFrame = win?.frame ?? .zero
        let scrH = win?.screen.bounds.height ?? UIScreen.main.bounds.height
        let designCompat = Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") as? Bool ?? false
        let m = currentMetrics
        return String(
            format: "b %.0f×%.0f  f(%.0f,%.0f)  win %.0f×%.0f  wf(%.0f,%.0f)  scr %.0f×%.0f\nsa L%.0f R%.0f T%.0f B%.0f  ivH %.0f  hCon %.0f/%@  ss %@  lg %@\nm s%.0f k%.0f r%.1f t%.0f b%.0f  rnd %@  glass %@  compat %@",
            b.width, b.height, frame.origin.x, frame.origin.y, winSize.width, winSize.height,
            winFrame.origin.x, winFrame.origin.y, scrW, scrH,
            sa.left, sa.right, sa.top, sa.bottom, ivH,
            keyboardHeightConstraint?.constant ?? 0, hActive ? "on" : "off", selfSizing ? "Y" : "N",
            KeyboardTheme.legacyPresentation ? "Y" : "N",
            m.suggestionHeight, m.minimumKeyHeight, m.rowSpacing,
            m.keyboardInsets.top, m.keyboardInsets.bottom,
            nearestRoundedAncestorDescription(), KeyboardGlassStyle.current.rawValue,
            designCompat ? "Y" : "N"
        )
    }

    /// Walks up from the extension's view to the window looking for the first ancestor
    /// whose layer is corner-rounded — the system's floating/curved keyboard container,
    /// if any. Reports its class, radius, and whether it clips.
    private func nearestRoundedAncestorDescription() -> String {
        var candidate: UIView? = view.superview
        var depth = 0
        while let current = candidate, depth < 10 {
            let radius = current.layer.cornerRadius
            if radius > 0.5 {
                return "\(type(of: current))·r\(Int(radius.rounded()))·clip\(current.clipsToBounds ? 1 : 0)"
            }
            candidate = current.superview
            depth += 1
        }
        return "none"
    }
    #endif

    /// Without Full Access this container is unreachable, so the write silently does
    /// nothing — which is precisely the signal. The containing app reads the stamp to
    /// learn that Full Access was granted; it has no API of its own to ask.
    private func recordFullAccessIfGranted() {
        guard hasFullAccess else { return }
        keyboardPreferences.fullAccessConfirmedAt = Date()
    }

    private func configureInputViewShell() {
        guard let inputView else { return }
        // Self-sizing + one height constraint is the deterministic mechanism: the
        // keyboard is exactly `preferredKeyboardHeight` in every host and on every
        // presentation path. Letting the system size us instead (allowsSelfSizing
        // false, no constraint) was measured to be untrustworthy: the granted height
        // ratchets across presentations (253→290→314 on the same sim) and renders a
        // container visibly taller than native. See the native-parity notes.
        inputView.allowsSelfSizing = true
        inputView.clipsToBounds = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewWillAppearWasCalled = true
        // Every presentation re-detects the host's container style (the host app
        // can differ each time we appear).
        presentationTransients.removeAll()
        presentationClassified = false
        if KeyboardTheme.legacyPresentation {
            KeyboardTheme.legacyPresentation = false
            metricsCache = nil
        }
        view.setNeedsUpdateConstraints()
        feedbackController.prepare()
        // Obadh may be returning to a field another keyboard has edited since we last
        // saw it. Any composition we remember is stale; start from whatever the
        // document is now.
        resetCompositionBookkeeping()
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()
        updateKeyboardHeightConstraintIfReady()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        lifecycleLog.notice("OBADH-LIFECYCLE viewDidAppear — keyboard visible, build=\(AppBuildInfo.summary, privacy: .public) style=\(self.traitCollection.userInterfaceStyle == .dark ? "dark" : "light", privacy: .public) size=\(NSCoder.string(for: self.view.bounds.size), privacy: .public)")
        showSpaceLanguageIntro()
        // Reflect the current cursor context (e.g. next-word suggestions) now that we
        // are back, rather than showing whatever was in the bar when we left.
        refreshSuggestions()
        #if DEBUG
        debugChannel.start()
        #endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Switching to another keyboard (or dismissing): the word in progress is already
        // ordinary text, so we only stop tracking it. Nothing is lost or stranded.
        resetCompositionBookkeeping()
        #if DEBUG
        debugChannel.stop()
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        recordPresentationTransient()
        applyLayoutMetricsIfNeeded()
        updateKeyboardTouchRegions()
        #if DEBUG
        updatePresentationProbe()
        #endif
    }

    // MARK: Legacy presentation detection

    /// iOS presents third-party keyboards in one of two containers — modern Liquid
    /// Glass or the legacy style for hosts that haven't adopted the current design —
    /// with no public API exposing which. The one observable difference is the
    /// presentation's transient sizing pass: before honoring our height, the system
    /// lays the view out at a presentation-specific intermediate. Those
    /// intermediates are class-quantized and disjoint (measured on every current
    /// width class, iOS 26.5): modern {294, 444, 452} vs legacy {260, 411, 419},
    /// separated by 33-34pt. Classification is nearest-anchor per screen height
    /// with a required margin; modern wins ties, unknown screens, and missing
    /// transients, so a wrong guess can only ever leave the shipped modern look.
    private static let presentationIntermediates: [CGFloat: (modern: CGFloat, legacy: CGFloat)] = [
        667: (294, 260),   // SE class (home button)
        852: (444, 411),   // iPhone 16 class
        874: (444, 411),   // iPhone 17 Pro class
        912: (452, 419),   // iPhone Air class
        932: (452, 419),   // Plus class
        956: (452, 419),   // Pro Max class
    ]

    private func recordPresentationTransient() {
        guard viewWillAppearWasCalled, !presentationClassified else { return }
        let height = view.bounds.height
        guard height > 0 else { return }
        let screenHeight = view.window?.screen.bounds.height ?? UIScreen.main.bounds.height
        if abs(height - preferredActiveKeyboardHeight) < 1 || presentationTransients.count > 8 {
            classifyPresentation(screenHeight: screenHeight)
            return
        }
        if height != screenHeight, presentationTransients.last != height {
            presentationTransients.append(height)
        }
    }

    private func classifyPresentation(screenHeight: CGFloat) {
        presentationClassified = true
        // iOS 27 removed the legacy keyboard fallback: native renders the modern
        // container even in pre-iOS-26-SDK hosts (measured in Messenger on an
        // iOS 27 device: native zone ~51pt = modern). The anchors below are
        // iOS 26 measurements and misfire against iOS 27 host layouts (Messenger
        // classified legacy -> 53pt strip + 17pt band = 70pt zone, 18pt taller
        // than native), so the detector is iOS 26 only.
        if #available(iOS 27.0, *) {
            return
        }
        guard let anchors = Self.presentationIntermediates[screenHeight],
              let intermediate = presentationTransients.last else {
            return
        }
        let legacyDistance = abs(intermediate - anchors.legacy)
        let modernDistance = abs(intermediate - anchors.modern)
        guard legacyDistance + 8 < modernDistance else { return }
        lifecycleLog.notice("OBADH-LIFECYCLE legacy presentation detected (intermediate \(intermediate, privacy: .public) on screen \(screenHeight, privacy: .public))")
        KeyboardTheme.legacyPresentation = true
        metricsCache = nil
        updateKeyboardHeightConstraintIfReady()
        applyLayoutMetricsIfNeeded(force: true)
        refreshKeyboard()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        guard !isUpdatingTextProxy else { return }
        // The host is about to change the text out from under us (a send button
        // clearing the field, a paste, another edit). Drop composition bookkeeping;
        // whatever was marked is the host's now.
        resetCompositionBookkeeping()
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

    // Moving the insertion point — a tap, an arrow key, a selection — is a *selection*
    // change, not a *text* change, so it never reaches textWillChange/textDidChange.
    // Observing it lets us stop tracking the word being composed the moment the cursor
    // leaves it. Because the word is ordinary text (not a marked IME region), stopping
    // tracking is all that's needed: the word stays, and the cursor moves freely — there
    // is nothing to confirm and nothing to strand.
    override func selectionWillChange(_ textInput: UITextInput?) {
        super.selectionWillChange(textInput)
        // Same guard the text callbacks use: our own proxy edits deliver their selection
        // callbacks synchronously inside performTextUpdate, where the flag is set, so
        // this fires only for genuine external moves.
        guard !isUpdatingTextProxy else { return }
        resetCompositionBookkeeping()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        guard !isUpdatingTextProxy else { return }
        // Backstop for hosts that deliver only one of the two callbacks; idempotent.
        resetCompositionBookkeeping()
        refreshSuggestions()
    }

    private func configureRootView() {
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = true

        // A native-material backdrop covering the whole keyboard: it gives the
        // system keyboard's glassy look uniformly (so there's no visible
        // rectangle around the key area) and, being non-transparent, it is what
        // lets touches over the gaps between keys reach the extension at all —
        // the clear touch surface on top then resolves them.
        keyboardBackgroundView.isUserInteractionEnabled = false
        keyboardBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardBackgroundView)
        NSLayoutConstraint.activate([
            keyboardBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

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

        // On iOS 26 the key rows live inside one Liquid Glass container so the
        // per-key glass effects merge in a single render pass (perf), and it sits
        // under the touch surface so hit-testing is unchanged. Below iOS 26 the
        // stack goes straight on `view` with the solid key fill. `keyLayoutAnchor`
        // is whichever view carries the key-area layout constraints.
        let keyLayoutAnchor: UIView
        if #available(iOS 26.0, *) {
            let containerEffect = UIGlassContainerEffect()
            containerEffect.spacing = 0
            let container = UIVisualEffectView(effect: containerEffect)
            container.isUserInteractionEnabled = false
            container.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(container)
            container.contentView.addSubview(keyboardStack)
            NSLayoutConstraint.activate([
                keyboardStack.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor),
                keyboardStack.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor),
                keyboardStack.topAnchor.constraint(equalTo: container.contentView.topAnchor),
                keyboardStack.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor)
            ])
            keyboardGlassContainer = container
            keyLayoutAnchor = container
        } else {
            view.addSubview(keyboardStack)
            keyLayoutAnchor = keyboardStack
        }

        keyboardTouchSurface.delegate = self
        view.addSubview(keyboardTouchSurface)
        keyPreviewCallout.alpha = 0
        keyPreviewCallout.isHidden = true
        view.addSubview(keyPreviewCallout)

        let insets = metrics.keyboardInsets
        let leadingConstraint = keyLayoutAnchor.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let trailingConstraint = keyLayoutAnchor.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        let topConstraint = keyLayoutAnchor.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor, constant: insets.top)
        let bottomConstraint = keyLayoutAnchor.bottomAnchor.constraint(
            lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -insets.bottom
        )
        let heightConstraint = keyLayoutAnchor.heightAnchor.constraint(equalToConstant: keyRowsHeight(for: metrics))
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
            // Full-bleed so its near-invisible touch-routing tint is uniform (no
            // rectangle). It ignores touches above `keyAreaTop` (the suggestion
            // bar) and, below the bottom command row down to the view edge, the
            // resolver clamps low thumb taps to the last row.
            keyboardTouchSurface.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardTouchSurface.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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
        // Buttons were rebuilt, so force the next appearance pass to restyle them.
        lastAppearanceState = nil
    }

    private func refreshKeyboard() {
        let metrics = currentMetrics
        updateKeyboardHeightConstraintIfReady()
        view.backgroundColor = .clear
        suggestionBar.isHidden = showsEmojiPanel
        keyboardStack.isHidden = showsEmojiPanel && !isEmojiSearchActive
        keyboardGlassContainer?.isHidden = keyboardStack.isHidden
        keyboardTouchSurface.isHidden = keyboardStack.isHidden
        emojiPanelView.isHidden = !showsEmojiPanel
        emojiPanelView.setSearchActive(isEmojiSearchActive)
        emojiPanelBottomToSafeAreaConstraint?.isActive = !isEmojiSearchActive
        emojiPanelBottomToKeyboardConstraint?.isActive = isEmojiSearchActive
        keyboardStackTopConstraint?.constant = keyboardTopConstant(for: metrics)
        updateKeyAppearanceIfNeeded(metrics: metrics)
        refreshSuggestions()
    }

    private struct KeyboardAppearanceState: Equatable {
        let shifted: Bool
        let mode: KeyboardMode
        let showsSpaceIntro: Bool
        let spaceCaption: String
        let style: UIUserInterfaceStyle
        let minimumKeyHeight: CGFloat
    }

    private var lastAppearanceState: KeyboardAppearanceState?

    /// Restyling all ~30 keys runs on every keypress via `refreshKeyboard`, yet a
    /// plain character press changes nothing visible. Skip the loop unless the
    /// state that actually drives key appearance changed.
    private func updateKeyAppearanceIfNeeded(metrics: KeyboardMetrics) {
        let state = KeyboardAppearanceState(
            shifted: shifted,
            mode: keyboardMode,
            showsSpaceIntro: showsSpaceLanguageIntro && !isEmojiSearchActive,
            spaceCaption: spaceCaption,
            style: traitCollection.userInterfaceStyle,
            minimumKeyHeight: metrics.minimumKeyHeight
        )
        guard state != lastAppearanceState else { return }
        lastAppearanceState = state

        for button in keyButtons {
            button.updateAppearance(
                shifted: state.shifted,
                traitCollection: traitCollection,
                metrics: metrics,
                showsSpaceIntro: state.showsSpaceIntro,
                spaceCaption: state.spaceCaption
            )
        }
    }

    private func refreshSuggestions() {
        suggestionGeneration &+= 1
        let generation = suggestionGeneration
        let engine = self.engine
        activeCursorWord = nil

        if composer.hasActiveInput {
            // The deterministic preview is already known synchronously; show it
            // immediately (not yet quoted — its dictionary status is unknown until the
            // async result below), then fill in autocorrect candidates off the main
            // thread so the FST traversal never blocks typing.
            deterministicIsOOV = false
            updateCompositionSuggestionBar()
            let buffer = composer.romanBuffer
            let composerGeneration = composer.generation
            let limit = composer.autocorrectFetchLimit
            let autoInsert = keyboardPreferences.autoInsertTopCorrection
            let shownWord = composer.preview
            engineQueue.async { [weak self] in
                let candidates = engine.compositionSuggestions(for: buffer, limit: limit)
                // The literal's dictionary status drives both the native-style "keep my
                // spelling" quote (always) and the auto-insert gate (when enabled).
                let shownIsLexiconWord = !shownWord.isEmpty && engine.isLexiconWord(shownWord)
                Task { @MainActor in
                    guard let self, self.suggestionGeneration == generation else { return }
                    self.deterministicIsOOV = !shownWord.isEmpty && !shownIsLexiconWord
                    self.composer.mergeAutocorrectCandidates(candidates, generation: composerGeneration)
                    self.composer.resolveAutocorrectTarget(
                        autoInsertEnabled: autoInsert,
                        deterministicIsLexiconWord: shownIsLexiconWord,
                        isProtectedWord: { self.learnedWordStore.isProtected($0) }
                    )
                    self.updateCompositionSuggestionBar()
                }
            }
            return
        }

        let contextBeforeInput = textDocumentProxy.documentContextBeforeInput ?? ""
        guard contextBeforeInput.contains(where: { !$0.isWhitespace }) else {
            suggestionBar.update(suggestions: [])
            return
        }

        // Cursor sitting inside an already-committed word (a word character immediately
        // precedes it): offer corrections for that word, not next-word suggestions.
        let contextAfterInput = textDocumentProxy.documentContextAfterInput ?? ""
        if let cursorWord = CursorWordDetector.wordAtCursor(before: contextBeforeInput, after: contextAfterInput) {
            activeCursorWord = cursorWord
            engineQueue.async { [weak self] in
                let alternatives = engine
                    .wordAlternatives(for: cursorWord.word, limit: 4)
                    .filter { !$0.isEmpty && $0 != cursorWord.word }
                    .prefix(3)
                    .map { KeyboardSuggestion(text: $0, source: .autocorrect) }
                Task { @MainActor in
                    guard let self, self.suggestionGeneration == generation else { return }
                    self.suggestionBar.update(suggestions: alternatives)
                }
            }
            return
        }

        // The autosuggest session accumulates as the user types left-to-right; it
        // reflects where typing stopped, not where the cursor is, and it never rewinds.
        // So it's only trustworthy at the end of the text. With the cursor moved into
        // earlier text, it buries the cursor-accurate context lookup — use that alone.
        let cursorAtEnd = (textDocumentProxy.documentContextAfterInput ?? "").isEmpty
        engineQueue.async { [weak self] in
            let contextSuggestions = engine
                .autosuggestSuggestions(for: contextBeforeInput, limit: 6)
                .filter { !$0.isEmpty }
                .map { KeyboardSuggestion(text: $0, source: .autosuggest) }
            let merged: [KeyboardSuggestion]
            if cursorAtEnd {
                let sessionSuggestions = engine
                    .autosuggestSessionSuggestions(limit: 6)
                    .map { KeyboardSuggestion(text: $0, source: .autosuggest) }
                merged = KeyboardComposer.mergeSuggestions(
                    primary: sessionSuggestions,
                    fallback: contextSuggestions,
                    limit: 3
                )
            } else {
                merged = Array(contextSuggestions.prefix(3))
            }
            Task { @MainActor in
                guard let self, self.suggestionGeneration == generation else { return }
                self.suggestionBar.update(suggestions: merged)
            }
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
            composer.append(shifted ? value.uppercased() : value)
            shifted = false
            refreshCompositionPreview()
        case let .symbol(symbol):
            switch symbol.role {
            case .sentenceTerminator:
                insertSentenceTerminator(symbol.output)
            case .literal:
                insertLiteralSymbol(symbol.output)
            }
        case .space:
            handleSpaceKey()
        case .returnKey:
            if !commitActiveInputIfNeeded(trailingText: "\n") {
                engine.clearAutosuggestSession()
                performTextUpdate {
                    textDocumentProxy.insertText("\n")
                }
            }
        case .backspace:
            backspaceRepeater.end()
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
        case .emoji:
            showEmojiPanel()
        }
        previousKeyWasSpace = key == .space
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
        emojiSearchLanguage = keyboardPreferences.defaultEmojiSearchLanguage
        shifted = false
        keyboardMode = .letters
        emojiPanelView.setSearchActive(true)
        syncEmojiSearchQuery()
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
        // In Bangla mode the typed roman is transliterated into the Bangla query
        // shown in the field and searched against the Bangla index.
        let query = emojiSearchLanguage == .bangla
            ? engine.transliterate(emojiSearchQuery)
            : emojiSearchQuery
        emojiPanelView.setSearchQuery(query, language: emojiSearchLanguage)
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
        backspaceRepeater.begin { [weak self] unit in
            guard let self else { return }
            // Honour the escalation the policy hands us: a sustained hold graduates
            // from characters to whole words, native-style. Previously this arm threw
            // the unit away and always deleted one character, so clearing several
            // words meant holding backspace forever.
            performBackspace(unit: unit, requiresTextEvidence: false)
            feedbackController.backspaceRepeated(unit: unit)
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
                    compositionController.clearComposition(in: documentEditor)
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
            compositionController.commit(finalText: committed, trailingText: trailingText, in: documentEditor)
        }
        observeCommittedToken(committed)
        observeAutosuggestBoundary(trailingText)
        return true
    }

    /// দাঁড়ি `।`, `?`, `!`: finalize any active composition, insert the glyph,
    /// and reset the autosuggest session for a new sentence. Handled purely on
    /// the iOS layer — the engine is not consulted.
    private func insertSentenceTerminator(_ output: String) {
        if !commitActiveInputIfNeeded(trailingText: output) {
            performTextUpdate {
                textDocumentProxy.insertText(output)
            }
        }
        engine.clearAutosuggestSession()
    }

    /// Any other symbol (digits, `,`, `.`, `৳`, brackets, quotes, dashes…):
    /// finalize active composition, otherwise insert with Apple-style smart
    /// punctuation (`--`→—, `...`→…, straight→curly quotes).
    private func insertLiteralSymbol(_ output: String) {
        if commitActiveInputIfNeeded(trailingText: output) {
            return
        }
        let contextBefore = textDocumentProxy.documentContextBeforeInput ?? ""
        let substitution = SmartPunctuation.literalSubstitution(for: output, contextBefore: contextBefore)
        performTextUpdate {
            applySmartPunctuation(substitution)
        }
    }

    private func handleSpaceKey() {
        let now = CACurrentMediaTime()
        let withinDoubleTapWindow = previousKeyWasSpace
            && now - lastSpaceKeyTime <= Self.dariDoubleSpaceWindow
        lastSpaceKeyTime = now
        if commitActiveInputIfNeeded(trailingText: " ") {
            return
        }
        let contextBefore = textDocumentProxy.documentContextBeforeInput ?? ""
        // Double-space → dari ends a sentence: only at the end of the text, and only
        // as a quick double-tap, matching the native shortcut. A slow second space,
        // or any space mid-text, types a plain space — always.
        let cursorAtEnd = (textDocumentProxy.documentContextAfterInput ?? "").isEmpty
        if cursorAtEnd, withinDoubleTapWindow,
           let substitution = SmartPunctuation.doubleSpaceSubstitution(contextBefore: contextBefore) {
            performTextUpdate {
                applySmartPunctuation(substitution)
            }
            return
        }
        performTextUpdate {
            insertSpace()
        }
    }

    private func applySmartPunctuation(_ substitution: SmartPunctuationResult) {
        for _ in 0..<substitution.deleteBefore {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(substitution.insertion)
    }

    private func refreshCompositionPreview() {
        performTextUpdate {
            compositionController.setComposition(composer.preview, in: documentEditor)
        }
    }

    /// Show the composition candidates, quoting the literal when it is not a dictionary
    /// word (native-style "keep my spelling"), so the first slot always reads as the
    /// user's own text and stays tappable. OOV-ness subsumes the auto-insert case —
    /// auto-insert only ever targets a non-lexicon literal.
    private func updateCompositionSuggestionBar() {
        suggestionBar.update(
            suggestions: composer.activeSuggestions,
            emojis: resolvedEmojiSuggestions(),
            quotedText: deterministicIsOOV ? composer.preview : nil
        )
    }

    /// Stop tracking the word in progress. The word is ordinary document text, so this
    /// touches nothing — it just means the next keystroke starts a fresh word. Call it
    /// whenever the composition is no longer ours to rewrite: the cursor moved, the
    /// keyboard is switching away, or the host changed the field. Because there is no
    /// marked region, there is nothing to strand and the cursor is never trapped.
    private func resetCompositionBookkeeping() {
        composer.clear()
        compositionController.resetHostState()
        previousKeyWasSpace = false
    }

    private func commitMarkedSuggestion(_ text: String) {
        performTextUpdate {
            compositionController.commitSuggestion(text, in: documentEditor)
        }
    }

    /// Marks proxy edits so our own text/selection callbacks are ignored. The edit and
    /// the callbacks it triggers are synchronous, so the flag need only span this call —
    /// the same contract the text-change delegates already rely on.
    private func performTextUpdate(_ update: () -> Void) {
        isUpdatingTextProxy = true
        defer { isUpdatingTextProxy = false }
        update()
    }

    private func insertSpace() {
        compositionController.insertSpace(in: documentEditor)
    }

    private func restorePersonalAutosuggest() {
        guard let snapshot = personalAutosuggestStore.loadSnapshot() else {
            return
        }
        if !engine.importPersonalAutosuggestSnapshot(snapshot) {
            personalAutosuggestStore.removeSnapshot()
        }
    }

    /// Learn from a committed word. `keep` marks the strong signal — the user tapped
    /// their quoted spelling to reject a correction — versus an ordinary commit.
    private func observeCommittedToken(_ token: String, keep: Bool = false) {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard engine.commitAutosuggestToken(token) else {
            return
        }
        // The bridge calls and disk write are the slow part; keep them off the space-key
        // critical path. Serialized on engineQueue against the Rust session.
        let engine = self.engine
        let store = self.personalAutosuggestStore
        let learnedWordStore = self.learnedWordStore
        let signal: LearnedWordStore.Signal = keep ? .explicitKeep : .commit
        engineQueue.async {
            // Only a word the built-in lexicon doesn't know can ever need protection, so
            // the personal store never fills with words it already covers.
            if !engine.isLexiconWord(token) {
                learnedWordStore.reinforce(token, signal: signal)
            }
            if let snapshot = engine.exportPersonalAutosuggestSnapshot() {
                store.saveSnapshot(snapshot)
            }
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

    private struct MetricsCacheKey: Equatable {
        let size: CGSize
        let verticalSizeClass: UIUserInterfaceSizeClass
    }

    private var metricsCache: (key: MetricsCacheKey, value: KeyboardMetrics)?

    private var currentMetrics: KeyboardMetrics {
        // Metrics MUST derive from the intended height, never from view.bounds.height:
        // the suggestion strip's required height feeds the view's fitting size, which
        // is what the system sizes the container by. Basing metrics on current bounds
        // creates a feedback loop (bounds→strip→fitting→bounds) that locks the
        // container at whatever it currently is and makes height changes impossible —
        // measured as the 290/314 "phantom grants" that were our own clamps echoed.
        let size: CGSize
        let bounds = view.bounds.size
        if bounds.width > 0 {
            size = CGSize(width: bounds.width, height: preferredKeyboardHeight)
        } else {
            let screenSize = view.window?.screen.bounds.size ?? UIScreen.main.bounds.size
            size = CGSize(width: min(screenSize.width, screenSize.height), height: preferredKeyboardHeight)
        }

        // KeyboardTheme.metrics depends only on the size and vertical size class,
        // yet it is read several times per keypress; memoize within a layout pass.
        let key = MetricsCacheKey(size: size, verticalSizeClass: traitCollection.verticalSizeClass)
        if let cached = metricsCache, cached.key == key {
            return cached.value
        }
        let value = KeyboardTheme.metrics(for: size, traitCollection: traitCollection)
        metricsCache = (key, value)
        return value
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
        // Flush above the pressed key, like native (its preview never overlaps the
        // key face; verified on iOS 27 device screenshots).
        let y = min(
            max(0, frameInView.minY - size.height),
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
        // The full-bleed surface must not eat suggestion-bar taps.
        keyboardTouchSurface.keyAreaTop = suggestionBar.frame.maxY
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
    func suggestionBar(_ suggestionBar: SuggestionBarView, didSelectEmoji emoji: String) {
        feedbackController.suggestionAccepted()
        acceptEmojiSuggestion(emoji)
    }

    /// Long-press variant options — the emoji panel index loads lazily HERE (only
    /// on a long-press), never during typing.
    func suggestionBar(_ suggestionBar: SuggestionBarView, variantOptionsFor base: String) -> [EmojiItem] {
        guard let item = emojiDataStore.item(for: base) else { return [] }
        return emojiDataStore.variantOptions(for: item)
    }

    func suggestionBar(_ suggestionBar: SuggestionBarView, didPickEmojiVariant emoji: String, base: String) {
        feedbackController.suggestionAccepted()
        emojiVariantPreferenceStore.record(baseEmoji: base, selectedEmoji: emoji)
        acceptEmojiSuggestion(emoji)
    }

    /// Resolve each base suggestion emoji to the user's remembered skin tone — a
    /// dict lookup in the shared App Group store, no `EmojiDataStore` load.
    private func resolvedEmojiSuggestions() -> [EmojiSuggestion] {
        let preferences = emojiVariantPreferenceStore.load()
        return composer.activeEmojis.map { base in
            EmojiSuggestion(base: base, display: preferences[base] ?? base)
        }
    }

    func suggestionBar(_ suggestionBar: SuggestionBarView, didSelect suggestion: KeyboardSuggestion) {
        feedbackController.suggestionAccepted()
        if composer.hasActiveInput {
            // Native-style: every shown slot is tappable. Tapping the deterministic
            // literal keeps the user's spelling (a strong "I mean this word" signal);
            // tapping a correction replaces it. Either commits the tapped text in place
            // and finalizes the word.
            let keepsLiteral = suggestion.source == .deterministic
            commitMarkedSuggestion(suggestion.text)
            composer.clear()
            observeCommittedToken(suggestion.text, keep: keepsLiteral)
        } else if let cursorWord = activeCursorWord {
            // A correction for the word the cursor sits in: replace that word in place.
            replaceCursorWord(cursorWord, with: suggestion.text)
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

    /// Replace the already-committed word the cursor is in with a chosen alternative.
    /// Move the cursor to the word's end so the whole word is behind it, then swap it.
    private func replaceCursorWord(_ cursorWord: CursorWord, with replacement: String) {
        activeCursorWord = nil
        performTextUpdate {
            if !cursorWord.after.isEmpty {
                textDocumentProxy.adjustTextPosition(byCharacterOffset: cursorWord.after.utf16.count)
            }
            compositionController.replaceWordBeforeCursor(cursorWord.word, with: replacement, in: documentEditor)
        }
    }

    /// Tapping the inline emoji finalizes the word being composed and appends the
    /// emoji (so "ভালোবাসা" + tap → "ভালোবাসা❤️"), keeping the word rather than
    /// replacing it. Also feeds the emoji panel's recents.
    private func acceptEmojiSuggestion(_ emoji: String) {
        if composer.hasActiveInput {
            let word = composer.preview
            commitMarkedSuggestion(word)
            composer.clear()
            observeCommittedToken(word)
        }
        performTextUpdate {
            textDocumentProxy.insertText(emoji)
        }
        emojiRecentStore.record(emoji)
        emojiPanelView.recordRecentEmoji(emoji)
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

    func emojiPanelViewDidToggleSearchLanguage(_ view: EmojiPanelView) {
        emojiSearchLanguage = emojiSearchLanguage.toggled
        feedbackController.suggestionAccepted()
        syncEmojiSearchQuery()
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

    func deleteBackward() {
        proxy.deleteBackward()
    }
}

#if DEBUG
extension KeyboardViewController: KeyboardDebugCommandHandler {
    /// DEBUG-only. Drives the keyboard from the agentic control channel so tooling
    /// can switch keyboards, pages, and key materials without simulating touches.
    /// Compile-excluded from Release (see KeyboardDebugChannel).
    func handleDebugCommand(_ command: String, argument: String?) {
        switch command {
        case "advance":
            // The public API the globe key calls — cycle to the next keyboard.
            advanceToNextInputMode()
        case "mode":
            switch argument {
            case "numbers": keyboardMode = .numbers
            case "symbols": keyboardMode = .symbols
            default: keyboardMode = .letters
            }
            shifted = false
            reloadKeyboardRows()
            refreshKeyboard()
        case "glass":
            guard let argument, let style = KeyboardGlassStyle(rawValue: argument) else {
                lifecycleLog.notice("OBADH-DEBUG glass: unknown style \(argument ?? "", privacy: .public)")
                return
            }
            KeyboardGlassStyle.current = style
            reloadKeyboardRows()
            refreshKeyboard()
        case "probe":
            // Mouse-free sim driving of the presentation probe overlay.
            keyboardPreferences.debugPresentationProbeEnabled = argument != "off"
            updatePresentationProbe()
        case "tap":
            // Inject keys through the exact production path so input behavior
            // (spaces, dari timing, composition) is scriptable on the simulator.
            // Comma-separated keys fire back-to-back within one poll — the quick
            // double-tap case: tap:space,space.
            guard let argument else { return }
            for name in argument.split(separator: ",") {
                if name == "space" {
                    handleKeyPress(.space)
                } else if name == "return" {
                    handleKeyPress(.returnKey)
                } else if name.count == 1 {
                    handleKeyPress(.character(String(name)))
                }
            }
        case "cursor":
            if let argument, let offset = Int(argument) {
                textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
            }
        case "context":
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            let after = textDocumentProxy.documentContextAfterInput ?? ""
            lifecycleLog.notice("OBADH-CONTEXT before=[\(before, privacy: .public)] after=[\(after, privacy: .public)]")
        case "preview":
            // Show the key preview + pressed state programmatically so the parity
            // suite can capture the popover (a real touch cannot be scripted).
            if let argument, argument != "off",
               let button = keyButtons.first(where: { $0.previewText?.lowercased() == argument.lowercased() }) {
                button.isHighlighted = true
                showKeyPreview(for: button)
            } else {
                for button in keyButtons { button.isHighlighted = false }
                hideKeyPreview(animated: false)
                refreshKeyboard()
            }
        case "emoji":
            switch argument {
            case "close": hideEmojiPanel()
            default: showEmojiPanel()
            }
            refreshKeyboard()
        case "dump":
            lifecycleLog.notice("OBADH-DEBUG state build=\(AppBuildInfo.summary, privacy: .public) mode=\(String(describing: self.keyboardMode), privacy: .public) shifted=\(self.shifted) glass=\(KeyboardGlassStyle.current.rawValue, privacy: .public) appearance=\(self.traitCollection.userInterfaceStyle == .dark ? "dark" : "light", privacy: .public) size=\(NSCoder.string(for: self.view.bounds.size), privacy: .public) emojiPanel=\(self.showsEmojiPanel ? "shown" : "hidden") \(self.emojiPanelView.debugStateSummary, privacy: .public)")
        default:
            lifecycleLog.notice("OBADH-DEBUG unknown command=\(command, privacy: .public)")
        }
    }
}
#endif
