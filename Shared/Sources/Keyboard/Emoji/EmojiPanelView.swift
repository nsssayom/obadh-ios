import UIKit

@MainActor
protocol EmojiPanelViewDelegate: AnyObject {
    func emojiPanelView(_ view: EmojiPanelView, didSelect item: EmojiItem)
    func emojiPanelViewDidRequestSearch(_ view: EmojiPanelView)
    func emojiPanelViewDidRequestKeyboard(_ view: EmojiPanelView)
    func emojiPanelViewDidBeginBackspace(_ view: EmojiPanelView)
    func emojiPanelViewDidEndBackspace(_ view: EmojiPanelView)
}

final class EmojiPanelView: UIView {
    weak var delegate: EmojiPanelViewDelegate?

    private enum Metrics {
        static let searchTop: CGFloat = 10
        static let searchHorizontalInset: CGFloat = 14
        static let searchHeight: CGFloat = 44
        static let searchHitHeight: CGFloat = 66
        static let searchCornerRadius: CGFloat = 22
        static let searchIconSize: CGFloat = 22
        static let searchIconLeading: CGFloat = 16
        static let searchTextSpacing: CGFloat = 10
        static let searchTextTrailing: CGFloat = 16
        static let collectionTopSpacing: CGFloat = 9
        static let collectionBottomSpacing: CGFloat = 4
        static let categoryHeight: CGFloat = 44
        static let minimumEmojiCellSize: CGFloat = 42
        static let maximumEmojiCellSize: CGFloat = 54
        static let emojiGlyphScale: CGFloat = 0.76
    }

    private let searchHitControl = UIControl()
    private let searchChrome = UIControl()
    private let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private let searchLabel = UILabel()
    private let collectionView: UICollectionView
    private let categoryStack = UIStackView()
    private var categoryButtons: [EmojiCategory: UIButton] = [:]
    private var keyboardButton = UIButton(type: .system)
    private var backspaceButton = UIButton(type: .system)
    private var searchChromeTopConstraint: NSLayoutConstraint?
    private var searchChromeHeightConstraint: NSLayoutConstraint?
    private var collectionTopConstraint: NSLayoutConstraint?
    private var collectionBottomConstraint: NSLayoutConstraint?
    private var categoryStackHeightConstraint: NSLayoutConstraint?
    private var dataStore = EmojiDataStore.empty
    private let emojiVariantPreferenceStore = EmojiVariantPreferenceStore()
    private var recentEmojis: [String] = []
    private var selectedCategory: EmojiCategory = .smileys
    private var isSearchActive = false
    private var searchQuery = ""
    private var visibleItems: [EmojiItem] = []
    private var variantPopover: EmojiVariantPopoverView?

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 7
        layout.sectionInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(dataStore: EmojiDataStore, recentEmojis: [String]) {
        self.dataStore = dataStore
        self.recentEmojis = recentEmojis
        if selectedCategory == .recents && recentEmojis.isEmpty {
            selectedCategory = .smileys
        }
        reloadItems()
    }

    func recordRecentEmoji(_ emoji: String) {
        recentEmojis.removeAll { $0 == emoji }
        recentEmojis.insert(emoji, at: 0)
        if recentEmojis.count > 64 {
            recentEmojis.removeLast(recentEmojis.count - 64)
        }
        if selectedCategory == .recents {
            reloadItems()
        }
    }

    func setSearchQuery(_ query: String) {
        searchQuery = query
        reloadItems()
    }

    func setSearchActive(_ active: Bool) {
        guard isSearchActive != active else { return }
        isSearchActive = active
        if !active {
            searchQuery = ""
        }
        reloadItems()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
            return
        }
        let width = bounds.width
        let targetCellSize: CGFloat = width >= 700 ? 48 : 45
        let columns = max(1, floor(
            (
                width
                    - layout.sectionInset.left
                    - layout.sectionInset.right
                    + layout.minimumInteritemSpacing
            ) / (targetCellSize + layout.minimumInteritemSpacing)
        ))
        let availableWidth = width - layout.sectionInset.left - layout.sectionInset.right
        let rawItemWidth = floor((availableWidth - (columns - 1) * layout.minimumInteritemSpacing) / columns)
        let itemWidth = min(Metrics.maximumEmojiCellSize, max(Metrics.minimumEmojiCellSize, rawItemWidth))
        layout.itemSize = CGSize(width: itemWidth, height: itemWidth)
        EmojiCell.glyphFontSize = floor(itemWidth * Metrics.emojiGlyphScale)
        reloadCategoryButtons()
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isHidden = true

        searchHitControl.translatesAutoresizingMaskIntoConstraints = false
        searchHitControl.backgroundColor = .clear
        searchHitControl.addTarget(self, action: #selector(handleSearchTap), for: .touchUpInside)
        addSubview(searchHitControl)

        searchChrome.translatesAutoresizingMaskIntoConstraints = false
        searchChrome.layer.cornerCurve = .continuous
        searchChrome.layer.cornerRadius = Metrics.searchCornerRadius
        searchChrome.addTarget(self, action: #selector(handleSearchTap), for: .touchUpInside)
        addSubview(searchChrome)

        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: Metrics.searchIconSize,
            weight: .regular
        )
        searchChrome.addSubview(searchIcon)

        searchLabel.translatesAutoresizingMaskIntoConstraints = false
        searchLabel.text = "Search Emoji"
        searchLabel.font = .systemFont(ofSize: 22, weight: .regular)
        searchChrome.addSubview(searchLabel)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .none
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseIdentifier)
        let variantGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleEmojiVariantGesture(_:)))
        variantGesture.minimumPressDuration = 0.35
        variantGesture.cancelsTouchesInView = true
        collectionView.addGestureRecognizer(variantGesture)
        addSubview(collectionView)

        categoryStack.translatesAutoresizingMaskIntoConstraints = false
        categoryStack.axis = .horizontal
        categoryStack.alignment = .fill
        categoryStack.distribution = .fillEqually
        categoryStack.spacing = 0
        addSubview(categoryStack)

        configureCategoryButtons()

        let searchChromeTopConstraint = searchChrome.topAnchor.constraint(
            equalTo: topAnchor,
            constant: Metrics.searchTop
        )
        let searchChromeHeightConstraint = searchChrome.heightAnchor.constraint(
            equalToConstant: Metrics.searchHeight
        )
        let collectionTopConstraint = collectionView.topAnchor.constraint(
            equalTo: searchChrome.bottomAnchor,
            constant: Metrics.collectionTopSpacing
        )
        let collectionBottomConstraint = collectionView.bottomAnchor.constraint(
            equalTo: categoryStack.topAnchor,
            constant: -Metrics.collectionBottomSpacing
        )
        let categoryStackHeightConstraint = categoryStack.heightAnchor.constraint(equalToConstant: Metrics.categoryHeight)
        self.searchChromeTopConstraint = searchChromeTopConstraint
        self.searchChromeHeightConstraint = searchChromeHeightConstraint
        self.collectionTopConstraint = collectionTopConstraint
        self.collectionBottomConstraint = collectionBottomConstraint
        self.categoryStackHeightConstraint = categoryStackHeightConstraint

        NSLayoutConstraint.activate([
            searchHitControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchHitControl.trailingAnchor.constraint(equalTo: trailingAnchor),
            searchHitControl.topAnchor.constraint(equalTo: topAnchor),
            searchHitControl.heightAnchor.constraint(equalToConstant: Metrics.searchHitHeight),

            searchChrome.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.searchHorizontalInset),
            searchChrome.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.searchHorizontalInset),
            searchChromeTopConstraint,
            searchChromeHeightConstraint,

            searchIcon.leadingAnchor.constraint(equalTo: searchChrome.leadingAnchor, constant: Metrics.searchIconLeading),
            searchIcon.centerYAnchor.constraint(equalTo: searchChrome.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: Metrics.searchIconSize),
            searchIcon.heightAnchor.constraint(equalToConstant: Metrics.searchIconSize),

            searchLabel.leadingAnchor.constraint(
                equalTo: searchIcon.trailingAnchor,
                constant: Metrics.searchTextSpacing
            ),
            searchLabel.trailingAnchor.constraint(
                equalTo: searchChrome.trailingAnchor,
                constant: -Metrics.searchTextTrailing
            ),
            searchLabel.centerYAnchor.constraint(equalTo: searchChrome.centerYAnchor),

            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionTopConstraint,
            collectionBottomConstraint,

            categoryStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            categoryStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            categoryStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            categoryStackHeightConstraint
        ])

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: EmojiPanelView, _) in
            view.applyTheme()
        }

        applyTheme()
        reloadItems()
    }

    private func configureCategoryButtons() {
        keyboardButton = UIButton(type: .system)
        keyboardButton.setTitle("ABC", for: .normal)
        keyboardButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        keyboardButton.layer.cornerCurve = .continuous
        keyboardButton.addTarget(self, action: #selector(handleKeyboardTap), for: .touchUpInside)
        categoryStack.addArrangedSubview(keyboardButton)

        for category in EmojiCategory.visibleCases {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: category.symbolName), for: .normal)
            button.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(pointSize: 20, weight: .regular),
                forImageIn: .normal
            )
            button.layer.cornerCurve = .continuous
            button.tag = categoryIndex(category)
            button.addTarget(self, action: #selector(handleCategoryTap(_:)), for: .touchUpInside)
            categoryButtons[category] = button
            categoryStack.addArrangedSubview(button)
        }

        backspaceButton = UIButton(type: .system)
        backspaceButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        backspaceButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .regular),
            forImageIn: .normal
        )
        backspaceButton.layer.cornerCurve = .continuous
        backspaceButton.accessibilityLabel = "Delete"
        backspaceButton.addTarget(
            self,
            action: #selector(handleBackspaceTouchDown),
            for: [.touchDown, .touchDragEnter]
        )
        backspaceButton.addTarget(
            self,
            action: #selector(handleBackspaceRelease),
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )
        categoryStack.addArrangedSubview(backspaceButton)
    }

    private func applyTheme() {
        searchChrome.backgroundColor = KeyboardTheme.emojiSearchBackgroundColor(for: traitCollection)
        searchIcon.tintColor = KeyboardTheme.emojiPlaceholderColor(for: traitCollection)
        keyboardButton.setTitleColor(
            KeyboardTheme.emojiCategoryTintColor(selected: false, traitCollection: traitCollection),
            for: .normal
        )
        backspaceButton.tintColor = KeyboardTheme.emojiCategoryTintColor(selected: false, traitCollection: traitCollection)
        collectionView.indicatorStyle = traitCollection.userInterfaceStyle == .dark ? .white : .black
        reloadCategoryButtons()
        updateSearchLabelAppearance()
    }

    private func reloadCategoryButtons() {
        for (category, button) in categoryButtons {
            let selected = category == selectedCategory && !isSearchActive
            button.tintColor = KeyboardTheme.emojiCategoryTintColor(
                selected: selected,
                traitCollection: traitCollection
            )
            button.backgroundColor = selected
                ? KeyboardTheme.emojiCategorySelectedBackgroundColor(for: traitCollection)
                : .clear
            if button.bounds.width > 0 && button.bounds.height > 0 {
                button.layer.cornerRadius = min(button.bounds.width, button.bounds.height) / 2
            }
        }
    }

    private func reloadItems() {
        dismissVariantPopover(animated: false)
        switch selectedCategory {
        case _ where isSearchActive:
            visibleItems = dataStore.search(searchQuery, limit: 240)
            searchLabel.text = searchQuery.isEmpty ? "Search Emoji" : searchQuery
        case .recents:
            visibleItems = dataStore.items(for: recentEmojis)
            searchLabel.text = "Search Emoji"
            if visibleItems.isEmpty {
                selectedCategory = .smileys
                visibleItems = applyVariantPreferences(to: dataStore.items(in: .smileys))
            }
        default:
            visibleItems = applyVariantPreferences(to: dataStore.items(in: selectedCategory))
            searchLabel.text = "Search Emoji"
        }
        searchChromeTopConstraint?.constant = Metrics.searchTop
        searchChromeHeightConstraint?.constant = Metrics.searchHeight
        searchHitControl.isEnabled = !isSearchActive
        collectionTopConstraint?.isActive = true
        collectionBottomConstraint?.isActive = true
        collectionView.isHidden = false
        categoryStack.isHidden = isSearchActive
        categoryStackHeightConstraint?.constant = isSearchActive ? 0 : Metrics.categoryHeight
        reloadCategoryButtons()
        updateSearchLabelAppearance()
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
    }

    private func updateSearchLabelAppearance() {
        searchLabel.textColor = isSearchActive && !searchQuery.isEmpty
            ? KeyboardTheme.textColor(for: traitCollection)
            : KeyboardTheme.emojiPlaceholderColor(for: traitCollection)
    }

    private func applyVariantPreferences(to items: [EmojiItem]) -> [EmojiItem] {
        items.map { item in
            let options = dataStore.variantOptions(for: item)
            guard
                let baseEmoji = options.first?.emoji,
                let preferredEmoji = emojiVariantPreferenceStore.preferredEmoji(forBaseEmoji: baseEmoji),
                options.contains(where: { $0.emoji == preferredEmoji }),
                let preferredItem = dataStore.item(for: preferredEmoji)
            else {
                return item
            }
            return preferredItem
        }
    }

    @objc private func handleKeyboardTap() {
        delegate?.emojiPanelViewDidRequestKeyboard(self)
    }

    @objc private func handleBackspaceTouchDown() {
        delegate?.emojiPanelViewDidBeginBackspace(self)
    }

    @objc private func handleBackspaceRelease() {
        delegate?.emojiPanelViewDidEndBackspace(self)
    }

    @objc private func handleSearchTap() {
        guard !isSearchActive else { return }
        delegate?.emojiPanelViewDidRequestSearch(self)
    }

    @objc private func handleCategoryTap(_ sender: UIButton) {
        guard let category = EmojiCategory.visibleCases.first(where: { categoryIndex($0) == sender.tag }) else {
            return
        }
        isSearchActive = false
        selectedCategory = category
        searchQuery = ""
        reloadItems()
    }

    private func categoryIndex(_ category: EmojiCategory) -> Int {
        EmojiCategory.visibleCases.firstIndex(of: category) ?? 0
    }

    @objc private func handleEmojiVariantGesture(_ gesture: UILongPressGestureRecognizer) {
        let pointInCollection = gesture.location(in: collectionView)

        switch gesture.state {
        case .began:
            guard
                let indexPath = collectionView.indexPathForItem(at: pointInCollection),
                visibleItems.indices.contains(indexPath.item),
                let cell = collectionView.cellForItem(at: indexPath)
            else {
                return
            }
            let item = visibleItems[indexPath.item]
            let options = dataStore.variantOptions(for: item)
            guard options.count > 1 else { return }
            showVariantPopover(options: options, sourceCell: cell)
        case .changed:
            variantPopover?.updateSelection(at: gesture.location(in: self))
        case .ended:
            if let item = variantPopover?.selectedItem {
                let shouldRefreshItems = recordVariantPreference(for: item)
                delegate?.emojiPanelView(self, didSelect: item)
                dismissVariantPopover(animated: true)
                if shouldRefreshItems {
                    reloadItems()
                }
            } else {
                dismissVariantPopover(animated: true)
            }
        case .cancelled, .failed:
            dismissVariantPopover(animated: true)
        default:
            break
        }
    }

    @discardableResult
    private func recordVariantPreference(for item: EmojiItem) -> Bool {
        let options = dataStore.variantOptions(for: item)
        guard let baseEmoji = options.first?.emoji, options.count > 1 else { return false }
        emojiVariantPreferenceStore.record(baseEmoji: baseEmoji, selectedEmoji: item.emoji)
        return selectedCategory != .recents
    }

    private func showVariantPopover(options: [EmojiItem], sourceCell: UICollectionViewCell) {
        dismissVariantPopover(animated: false)

        let popover = EmojiVariantPopoverView(options: options)
        popover.updateTheme(traitCollection: traitCollection)
        addSubview(popover)

        let sourceFrame = collectionView.convert(sourceCell.frame, to: self)
        let popoverSize = popover.preferredSize
        let x = min(
            max(8, sourceFrame.midX - popoverSize.width / 2),
            max(8, bounds.width - popoverSize.width - 8)
        )
        let y = max(6, sourceFrame.minY - popoverSize.height - 6)
        popover.frame = CGRect(origin: CGPoint(x: x, y: y), size: popoverSize)
        popover.updateSelection(at: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY))

        popover.alpha = 0
        popover.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
        ) {
            popover.alpha = 1
            popover.transform = .identity
        }
        variantPopover = popover
    }

    private func dismissVariantPopover(animated: Bool) {
        guard let popover = variantPopover else { return }
        variantPopover = nil
        let removal = {
            popover.alpha = 0
            popover.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }
        let completion: (Bool) -> Void = { _ in
            popover.removeFromSuperview()
        }

        guard animated else {
            popover.removeFromSuperview()
            return
        }

        UIView.animate(
            withDuration: 0.08,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseIn],
            animations: removal,
            completion: completion
        )
    }
}

extension EmojiPanelView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        visibleItems.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: EmojiCell.reuseIdentifier,
            for: indexPath
        ) as! EmojiCell
        cell.update(with: visibleItems[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard visibleItems.indices.contains(indexPath.item) else { return }
        dismissVariantPopover(animated: false)
        delegate?.emojiPanelView(self, didSelect: visibleItems[indexPath.item])
    }
}

private final class EmojiVariantPopoverView: UIView {
    private let options: [EmojiItem]
    private let stackView = UIStackView()
    private var optionLabels: [UILabel] = []
    private(set) var selectedIndex = 0

    var selectedItem: EmojiItem {
        options[selectedIndex]
    }

    var preferredSize: CGSize {
        CGSize(width: CGFloat(options.count) * 44 + 14, height: 54)
    }

    init(options: [EmojiItem]) {
        self.options = options
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTheme(traitCollection: UITraitCollection) {
        backgroundColor = KeyboardTheme.keyboardBackgroundColor(for: traitCollection).withAlphaComponent(0.96)
        layer.borderColor = KeyboardTheme.separatorColor(for: traitCollection).cgColor
        for label in optionLabels {
            label.textColor = KeyboardTheme.textColor(for: traitCollection)
        }
        updateSelectionHighlight(traitCollection: traitCollection)
    }

    func updateSelection(at pointInSuperview: CGPoint) {
        guard let superview else { return }
        let localPoint = convert(pointInSuperview, from: superview)
        for (index, label) in optionLabels.enumerated() {
            if label.frame.insetBy(dx: -5, dy: -8).contains(localPoint) {
                selectedIndex = index
                updateSelectionHighlight(traitCollection: traitCollection)
                return
            }
        }
    }

    private func configure() {
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1 / UIScreen.main.scale
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)
        clipsToBounds = false

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        addSubview(stackView)

        for item in options {
            let label = UILabel()
            label.text = item.emoji
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 31)
            label.layer.cornerRadius = 16
            label.layer.cornerCurve = .continuous
            label.clipsToBounds = true
            label.accessibilityLabel = item.name
            optionLabels.append(label)
            stackView.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        ])
    }

    private func updateSelectionHighlight(traitCollection: UITraitCollection) {
        for (index, label) in optionLabels.enumerated() {
            label.backgroundColor = index == selectedIndex
                ? KeyboardTheme.emojiCellHighlightColor(for: traitCollection)
                : .clear
        }
    }
}

private final class EmojiCell: UICollectionViewCell {
    static let reuseIdentifier = "EmojiCell"
    static var glyphFontSize: CGFloat = 34
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with item: EmojiItem) {
        label.text = item.emoji
        label.font = .systemFont(ofSize: Self.glyphFontSize)
        accessibilityLabel = item.name
        applyHighlightedState()
    }

    private func configure() {
        contentView.backgroundColor = .clear
        contentView.layer.cornerCurve = .continuous
        contentView.layer.cornerRadius = 8

        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.82
        label.font = .systemFont(ofSize: Self.glyphFontSize)
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    override var isHighlighted: Bool {
        didSet {
            applyHighlightedState()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.font = .systemFont(ofSize: Self.glyphFontSize)
        contentView.layer.cornerRadius = min(12, bounds.width * 0.22)
    }

    private func applyHighlightedState() {
        contentView.backgroundColor = isHighlighted
            ? KeyboardTheme.emojiCellHighlightColor(for: traitCollection)
            : .clear
    }
}
