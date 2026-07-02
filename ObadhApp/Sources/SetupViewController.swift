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
        case .keyboardFeel: 1
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
            return hapticCell()
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

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Keyboard Test"
        view.backgroundColor = .systemGroupedBackground
        configureTextView()
        configureHelperLabel()
        layoutContent()
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

    private func layoutContent() {
        view.addSubview(textView)
        view.addSubview(helperLabel)

        NSLayoutConstraint.activate([
            helperLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            helperLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            helperLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),

            textView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            textView.topAnchor.constraint(equalTo: helperLabel.bottomAnchor, constant: 12),
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
    }
}
