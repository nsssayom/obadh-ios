import SwiftUI
import UIKit

// DEBUG-only. A text field to summon the keyboard, plus the on-device haptic tuning
// controls. Release ships no text input at all -- see ObadhApp.swift.
#if DEBUG
/// Hosts the UIKit test screen so it can sit behind a SwiftUI NavigationLink.
struct KeyboardTestScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> KeyboardTestViewController {
        KeyboardTestViewController()
    }

    func updateUIViewController(_ controller: KeyboardTestViewController, context: Context) {}
}

final class KeyboardTestViewController: UIViewController {
    private let textView = UITextView()
    private let helperLabel = UILabel()
    private let buildLabel = UILabel()
    // A vibrant gradient behind everything (incl. behind the keyboard) so the
    // key material's translucency is visible for native-vs-Obadh comparison.
    private let gradientLayer = CAGradientLayer()
    private var startsWithGradient: Bool {
        ProcessInfo.processInfo.arguments.contains("--gradient-bg")
    }
    /// Measurement backdrop: a flat mid-gray distinct from every keyboard material in
    /// BOTH appearances, so screenshot tooling can find the container edge without
    /// ambiguity (the normal solid background ≈ the panel color in dark mode).
    private var startsWithMeasureBackground: Bool {
        ProcessInfo.processInfo.arguments.contains("--measure-bg")
    }

    #if DEBUG
    // DEBUG-only on-device tuning: dial haptic feel + flip the test background,
    // written to the shared App Group so the live keyboard picks it up. Excluded
    // from Release.
    private let prefs = KeyboardPreferences()
    private let hapticSwitch = UISwitch()
    private let intensitySlider = UISlider()
    private let sharpnessSlider = UISlider()
    private let intensityValueLabel = UILabel()
    private let sharpnessValueLabel = UILabel()
    private let backgroundControl = UISegmentedControl(items: ["Gradient", "Solid"])
    // The tint/shadow slider system was removed: its App Group prefs outlived the
    // tuning sessions and silently re-themed the keyboard. Tuned values are baked
    // into KeyboardTheme; the panel keeps only haptics, background, and diagnostics.
    // Shows the geometry iOS hands the extension (bounds, safe area, container corners)
    // as a yellow overlay on the keyboard, to diagnose legacy vs Liquid Glass framing.
    private let presentationProbeSwitch = UISwitch()
    private lazy var debugControlsView = makeDebugControlsView()
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Keyboard Test"
        view.backgroundColor = startsWithMeasureBackground
            ? UIColor(white: 0.5, alpha: 1)   // appearance-independent mid-gray
            : .systemGroupedBackground
        configureGradient()
        configureTextView()
        configureHelperLabel()
        configureBuildLabel()
        #if DEBUG
        configureDebugControls()
        #endif
        layoutContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }

    private func configureGradient() {
        gradientLayer.colors = [
            UIColor.systemPurple.cgColor,
            UIColor.systemPink.cgColor,
            UIColor.systemOrange.cgColor,
            UIColor.systemTeal.cgColor,
            UIColor.systemBlue.cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.isHidden = !startsWithGradient
        view.layer.insertSublayer(gradientLayer, at: 0)
    }

    private func configureBuildLabel() {
        buildLabel.translatesAutoresizingMaskIntoConstraints = false
        buildLabel.text = "Obadh \(AppBuildInfo.summary)"
        buildLabel.textColor = .tertiaryLabel
        buildLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        buildLabel.numberOfLines = 0
        buildLabel.textAlignment = .center
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    private func configureTextView() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .secondarySystemGroupedBackground
        textView.textColor = .label
        textView.tintColor = .systemBlue
        textView.font = .systemFont(ofSize: 24)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.layer.cornerCurve = .continuous
        textView.layer.cornerRadius = 16
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .yes
        textView.spellCheckingType = .yes
        textView.keyboardType = .alphabet
        textView.text = ""
        textView.accessibilityLabel = "Obadh keyboard test field"
    }

    private func configureHelperLabel() {
        helperLabel.translatesAutoresizingMaskIntoConstraints = false
        helperLabel.text = "Tap the globe key if Obadh is not selected. The setup app keeps hardware key presses disabled to avoid an iOS 26 Simulator input-mode crash; use the on-screen keyboard here."
        helperLabel.textColor = .secondaryLabel
        helperLabel.font = .preferredFont(forTextStyle: .footnote)
        helperLabel.numberOfLines = 0
    }

    #if DEBUG
    private func configureDebugControls() {
        hapticSwitch.isOn = prefs.debugHapticOverrideEnabled
        hapticSwitch.addTarget(self, action: #selector(hapticOverrideChanged), for: .valueChanged)

        for slider in [intensitySlider, sharpnessSlider] {
            slider.minimumValue = 0
            slider.maximumValue = 1
        }
        intensitySlider.value = Float(prefs.debugHapticIntensity)
        intensitySlider.addTarget(self, action: #selector(intensityChanged), for: .valueChanged)
        sharpnessSlider.value = Float(prefs.debugHapticSharpness)
        sharpnessSlider.addTarget(self, action: #selector(sharpnessChanged), for: .valueChanged)

        for label in [intensityValueLabel, sharpnessValueLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            label.textColor = .secondaryLabel
        }

        backgroundControl.selectedSegmentIndex = startsWithGradient ? 0 : 1
        backgroundControl.addTarget(self, action: #selector(backgroundChanged), for: .valueChanged)

        presentationProbeSwitch.isOn = prefs.debugPresentationProbeEnabled
        presentationProbeSwitch.addTarget(self, action: #selector(presentationProbeChanged), for: .valueChanged)

        updateHapticValueLabels()
    }

    /// A scrollable, card-sectioned control panel so nothing clips above the keyboard.
    private func makeDebugControlsView() -> UIView {
        let haptics = debugSection("Haptics", views: [
            debugSwitchRow("Custom haptics", hapticSwitch),
            intensityValueLabel, intensitySlider,
            sharpnessValueLabel, sharpnessSlider
        ])
        let appearance = debugSection("Test background", views: [backgroundControl])
        let diagnostics = debugSection("Presentation diagnostics", views: [
            debugSwitchRow("Probe overlay on keyboard", presentationProbeSwitch)
        ])

        let content = UIStackView(arrangedSubviews: [haptics, appearance, diagnostics])
        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = true
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        return scroll
    }

    private func debugSwitchRow(_ title: String, _ control: UISwitch) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)
        let row = UIStackView(arrangedSubviews: [label, UIView(), control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        return row
    }

    private func debugSection(_ title: String, views: [UIView]) -> UIView {
        let header = UILabel()
        header.text = title.uppercased()
        header.font = .preferredFont(forTextStyle: .caption1)
        header.textColor = .secondaryLabel

        let inner = UIStackView(arrangedSubviews: views)
        inner.axis = .vertical
        inner.spacing = 6
        inner.translatesAutoresizingMaskIntoConstraints = false

        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12
        card.layer.cornerCurve = .continuous
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14)
        ])

        let wrap = UIStackView(arrangedSubviews: [header, card])
        wrap.axis = .vertical
        wrap.spacing = 6
        return wrap
    }

    private func updateHapticValueLabels() {
        intensityValueLabel.text = String(format: "Intensity   %.2f", intensitySlider.value)
        sharpnessValueLabel.text = String(format: "Sharpness   %.2f", sharpnessSlider.value)
    }

    @objc private func hapticOverrideChanged() {
        prefs.debugHapticOverrideEnabled = hapticSwitch.isOn
    }

    @objc private func intensityChanged() {
        prefs.debugHapticIntensity = Double(intensitySlider.value)
        updateHapticValueLabels()
    }

    @objc private func sharpnessChanged() {
        prefs.debugHapticSharpness = Double(sharpnessSlider.value)
        updateHapticValueLabels()
    }

    @objc private func backgroundChanged() {
        gradientLayer.isHidden = backgroundControl.selectedSegmentIndex != 0
    }

    @objc private func presentationProbeChanged() {
        prefs.debugPresentationProbeEnabled = presentationProbeSwitch.isOn
        KeyboardPreferences.postKeyTintChanged()
    }
    #endif

    private func layoutContent() {
        view.addSubview(helperLabel)
        view.addSubview(buildLabel)
        view.addSubview(textView)

        let margins = view.layoutMarginsGuide
        var constraints = [
            helperLabel.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            helperLabel.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            helperLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),

            buildLabel.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            buildLabel.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            buildLabel.topAnchor.constraint(equalTo: helperLabel.bottomAnchor, constant: 8),

            textView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
            // Fixed (not >=) so the scrollable control panel above gets a determined
            // height instead of being collapsed to zero by a growing text field.
            textView.heightAnchor.constraint(equalToConstant: 92)
        ]

        var textTop = buildLabel.bottomAnchor
        #if DEBUG
        view.addSubview(debugControlsView)
        constraints += [
            debugControlsView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            debugControlsView.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            debugControlsView.topAnchor.constraint(equalTo: buildLabel.bottomAnchor, constant: 10)
        ]
        textTop = debugControlsView.bottomAnchor
        #endif
        constraints.append(textView.topAnchor.constraint(equalTo: textTop, constant: 12))

        NSLayoutConstraint.activate(constraints)
    }
}
#endif
