import UIKit

final class SetupViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case status
        case settings
        case keyboardFeel
        case test

        var title: String {
            switch self {
            case .status: "Status"
            case .settings: "Settings"
            case .keyboardFeel: "Keyboard Feel"
            case .test: "Test"
            }
        }
    }

    private struct StatusItem {
        let title: String
        let detail: String
        let systemImage: String
        let tintColor: UIColor
    }

    private let preferences = KeyboardPreferences()
    private let hapticPreview = UISelectionFeedbackGenerator()
    private lazy var hapticSwitch: UISwitch = {
        let control = UISwitch()
        control.addTarget(self, action: #selector(hapticSwitchChanged(_:)), for: .valueChanged)
        return control
    }()
    private lazy var emojiLanguageControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["English", "বাংলা"])
        control.addTarget(self, action: #selector(emojiLanguageChanged(_:)), for: .valueChanged)
        return control
    }()

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Obadh"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .refresh,
            primaryAction: UIAction { [weak self] _ in
                self?.refresh()
            }
        )
        tableView.cellLayoutMarginsFollowReadableWidth = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .status: statusItems.count
        case .settings: 3
        case .keyboardFeel: 2
        case .test: 1
        case nil: 0
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .status:
            return statusCell(for: statusItems[indexPath.row])
        case .settings:
            return settingsCell(row: indexPath.row)
        case .keyboardFeel:
            return indexPath.row == 0 ? hapticCell() : emojiLanguageCell()
        case .test:
            return testCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else {
            return
        }

        switch (section, indexPath.row) {
        case (.settings, 0):
            openAppSettings()
        case (.test, 0):
            navigationController?.pushViewController(KeyboardTestViewController(), animated: true)
        default:
            break
        }
    }

    private var statusItems: [StatusItem] {
        [
            StatusItem(
                title: "Keyboard",
                detail: "Open iOS Keyboard settings to confirm Obadh is enabled.",
                systemImage: "exclamationmark.circle.fill",
                tintColor: .systemOrange
            ),
            StatusItem(
                title: "Full Access",
                detail: "Required by iOS for extension haptics. Enable it in Obadh keyboard settings.",
                systemImage: "hand.tap.fill",
                tintColor: .systemOrange
            ),
            StatusItem(
                title: "Keyboard Haptics",
                detail: "Enable Haptic feedback and global Vibration in iOS Settings.",
                systemImage: "waveform",
                tintColor: .systemOrange
            ),
            StatusItem(
                title: "Privacy",
                detail: "Typing, correction, suggestions, and learning stay on device.",
                systemImage: "lock.fill",
                tintColor: .systemGreen
            )
        ]
    }

    private func statusCell(for item: StatusItem) -> UITableViewCell {
        let cell = reusableCell()
        var content = UIListContentConfiguration.subtitleCell()
        content.text = item.title
        content.secondaryText = item.detail
        content.image = UIImage(systemName: item.systemImage)
        content.imageProperties.tintColor = item.tintColor
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        cell.accessoryView = nil
        return cell
    }

    private func settingsCell(row: Int) -> UITableViewCell {
        let cell = reusableCell()
        var content = UIListContentConfiguration.subtitleCell()
        cell.accessoryView = nil

        switch row {
        case 0:
            content.text = "Open Obadh Settings"
            content.image = UIImage(systemName: "gear")
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        case 1:
            content.text = "Add Keyboard"
            content.secondaryText = "Settings > General > Keyboard > Keyboards > Add New Keyboard > Obadh"
            cell.accessoryType = .none
            cell.selectionStyle = .none
        default:
            content.text = "Allow Full Access"
            content.secondaryText = "Settings > General > Keyboard > Keyboards > Obadh > Allow Full Access"
            cell.accessoryType = .none
            cell.selectionStyle = .none
        }

        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        return cell
    }

    private func hapticCell() -> UITableViewCell {
        let cell = reusableCell()
        var content = UIListContentConfiguration.cell()
        content.text = "Haptic Feedback"
        content.image = UIImage(systemName: "waveform")
        cell.contentConfiguration = content
        cell.accessoryType = .none
        cell.accessoryView = hapticSwitch
        cell.selectionStyle = .none
        return cell
    }

    private func emojiLanguageCell() -> UITableViewCell {
        let cell = reusableCell()
        var content = UIListContentConfiguration.cell()
        content.text = "Emoji Search Language"
        content.image = UIImage(systemName: "magnifyingglass")
        cell.contentConfiguration = content
        emojiLanguageControl.selectedSegmentIndex = preferences.defaultEmojiSearchLanguage == .bangla ? 1 : 0
        cell.accessoryView = emojiLanguageControl
        cell.accessoryType = .none
        cell.selectionStyle = .none
        return cell
    }

    @objc private func emojiLanguageChanged(_ sender: UISegmentedControl) {
        preferences.defaultEmojiSearchLanguage = sender.selectedSegmentIndex == 1 ? .bangla : .english
    }

    private func testCell() -> UITableViewCell {
        let cell = reusableCell()
        var content = UIListContentConfiguration.subtitleCell()
        content.text = "Open Test Field"
        content.secondaryText = "Use this UIKit text field to summon the installed Obadh keyboard in Simulator."
        content.image = UIImage(systemName: "keyboard")
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.accessoryView = nil
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        return cell
    }

    private func reusableCell() -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .none
        return cell
    }

    private func refresh() {
        hapticSwitch.isOn = preferences.hapticFeedbackEnabled
        tableView.reloadData()
    }

    @objc private func hapticSwitchChanged(_ sender: UISwitch) {
        preferences.hapticFeedbackEnabled = sender.isOn
        guard sender.isOn else { return }
        hapticPreview.prepare()
        hapticPreview.selectionChanged()
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
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
