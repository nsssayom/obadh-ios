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
    private lazy var debugControlsView = makeDebugControlsView()
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Keyboard Test"
        view.backgroundColor = .systemGroupedBackground
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

        updateHapticValueLabels()
    }

    private func makeDebugControlsView() -> UIView {
        let title = UILabel()
        title.text = "Custom haptics"
        title.font = .preferredFont(forTextStyle: .subheadline)
        let switchRow = UIStackView(arrangedSubviews: [title, UIView(), hapticSwitch])
        switchRow.axis = .horizontal
        switchRow.alignment = .center
        switchRow.spacing = 8

        let stack = UIStackView(arrangedSubviews: [
            switchRow,
            intensityValueLabel, intensitySlider,
            sharpnessValueLabel, sharpnessSlider,
            backgroundControl
        ])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(2, after: intensityValueLabel)
        stack.setCustomSpacing(2, after: sharpnessValueLabel)
        return stack
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
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
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
