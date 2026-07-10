import UIKit

@MainActor
protocol EmojiPanelViewDelegate: AnyObject {
    func emojiPanelView(_ view: EmojiPanelView, didSelect item: EmojiItem)
    func emojiPanelViewDidRequestSearch(_ view: EmojiPanelView)
    func emojiPanelViewDidRequestClearSearch(_ view: EmojiPanelView)
    func emojiPanelViewDidRequestKeyboard(_ view: EmojiPanelView)
    func emojiPanelViewDidBeginBackspace(_ view: EmojiPanelView)
    func emojiPanelViewDidEndBackspace(_ view: EmojiPanelView)
    func emojiPanelViewDidToggleSearchLanguage(_ view: EmojiPanelView)
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
        static let searchClearSize: CGFloat = 22
        static let searchClearTrailing: CGFloat = 13
        static let collectionTopSpacing: CGFloat = 9
        static let collectionBottomSpacing: CGFloat = 4
        static let categoryHeight: CGFloat = 44
        static let categorySelectionDiameter: CGFloat = 36
        static let minimumEmojiCellSize: CGFloat = 36
        static let maximumEmojiCellSize: CGFloat = 46
        static let targetEmojiCellSize: CGFloat = 39
        static let emojiGlyphScale: CGFloat = 0.80
    }

    private let searchHitControl = UIControl()
    private let searchChrome = UIControl()
    private let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private let searchTextStack = UIStackView()
    private let searchLabel = UILabel()
    private let searchCaret = UIView()
    private let searchClearButton = UIButton(type: .system)
    // EN⇄BN search language toggle; the Bangla index loads lazily on first use.
    private let searchLanguageButton = UIButton(type: .system)
    private lazy var banglaSearchStore = BanglaEmojiSearchStore(bundle: Bundle(for: EmojiPanelView.self))
    private var searchLanguage: EmojiSearchLanguage = .english
    private let collectionView: UICollectionView
    private let categoryStack = UIStackView()
    private var categoryButtons: [EmojiCategory: EmojiCategoryButton] = [:]
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
    private var searchItems: [EmojiItem] = []
    private var sectionCategories: [EmojiCategory] = []
    private var sectionItems: [[EmojiItem]] = []
    private var variantPopover: EmojiVariantPopoverView?
    private var recentsSnapshotNeedsRefresh = false
    /// How many emoji fit on one screenful of the grid. Recents never render past
    /// it, so the section always ends where the first page does.
    private var recentsPageCapacity = EmojiRecentStore.defaultLimit

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
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
        recentsSnapshotNeedsRefresh = false
        // Each open lands on Recents, matching the system keyboard. reloadItems()
        // demotes to .smileys when the section does not materialize — either there
        // are no recents, or the stored entries are ones the data store no longer
        // knows about.
        selectedCategory = .recents
        reloadItems()
    }

    /// Mirrors the tap into the in-memory list so the section is right without a
    /// round trip to defaults. Trimming here is plain oldest-out; the store's
    /// score-based eviction is authoritative and re-syncs on the next open.
    func recordRecentEmoji(_ emoji: String) {
        recentEmojis.removeAll { $0 == emoji }
        recentEmojis.insert(emoji, at: 0)
        if recentEmojis.count > EmojiRecentStore.defaultLimit {
            recentEmojis.removeLast(recentEmojis.count - EmojiRecentStore.defaultLimit)
        }
        recentsSnapshotNeedsRefresh = true
    }

    #if DEBUG
    /// Panel state for the DEBUG-only control channel. Never compiled into Release.
    var debugStateSummary: String {
        "category=\(selectedCategory.rawValue) recents=\(recentEmojis.count) sections=\(sectionCategories.map(\.rawValue).joined(separator: ","))"
    }
    #endif

    func setSearchQuery(_ query: String, language: EmojiSearchLanguage? = nil) {
        searchQuery = query
        if let language, language != searchLanguage {
            searchLanguage = language
            searchLanguageButton.setTitle(language.shortLabel, for: .normal)
        }
        reloadItems()
    }

    private func searchResults() -> [EmojiItem] {
        if searchLanguage == .bangla {
            // Bangla index maps to emoji strings; look up the display items in the
            // (already-loaded) English store, which owns all EmojiItems.
            return dataStore.items(for: banglaSearchStore.search(searchQuery, limit: 240))
        }
        return dataStore.search(searchQuery, limit: 240)
    }

    @objc private func handleSearchLanguageToggle() {
        delegate?.emojiPanelViewDidToggleSearchLanguage(self)
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
        let availableHeight = max(
            1,
            collectionView.bounds.height - layout.sectionInset.top - layout.sectionInset.bottom
        )
        let verticalSpacing = layout.minimumInteritemSpacing
        let rowCount = max(
            1,
            floor((availableHeight + verticalSpacing) / (Metrics.targetEmojiCellSize + verticalSpacing))
        )
        let rawItemSide = floor((availableHeight - max(0, rowCount - 1) * verticalSpacing) / rowCount)
        let itemSide = min(Metrics.maximumEmojiCellSize, max(Metrics.minimumEmojiCellSize, rawItemSide))
        if layout.itemSize.width != itemSide || layout.itemSize.height != itemSide {
            layout.itemSize = CGSize(width: itemSide, height: itemSide)
            layout.invalidateLayout()
        }
        EmojiCell.glyphFontSize = floor(itemSide * Metrics.emojiGlyphScale)
        updateRecentsPageCapacity(layout: layout, rowCount: rowCount, itemSide: itemSide)
        reloadCategoryButtons()
    }

    /// Recomputed on rotation and on iPad's resizable heights.
    private func updateRecentsPageCapacity(
        layout: UICollectionViewFlowLayout,
        rowCount: CGFloat,
        itemSide: CGFloat
    ) {
        let capacity = EmojiGridMetrics.pageCapacity(
            collectionWidth: collectionView.bounds.width,
            leadingInset: layout.sectionInset.left,
            columnSpacing: layout.minimumLineSpacing,
            itemSide: itemSide,
            rowCount: Int(rowCount)
        )
        guard capacity > 0, capacity != recentsPageCapacity else { return }
        recentsPageCapacity = capacity
        guard sectionCategories.contains(.recents) else { return }
        rebuildBrowsingSections()
        collectionView.reloadData()
    }

    /// Recents, trimmed to one page. The store already bounds what it keeps; this
    /// bounds what a narrower or shorter grid shows.
    private func visibleRecentEmojis() -> [String] {
        Array(recentEmojis.prefix(recentsPageCapacity))
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

        searchTextStack.translatesAutoresizingMaskIntoConstraints = false
        searchTextStack.axis = .horizontal
        searchTextStack.alignment = .center
        searchTextStack.distribution = .fill
        searchTextStack.spacing = 2
        searchTextStack.isUserInteractionEnabled = false
        searchChrome.addSubview(searchTextStack)

        searchLabel.translatesAutoresizingMaskIntoConstraints = false
        searchLabel.text = "Search Emoji"
        searchLabel.font = .systemFont(ofSize: 22, weight: .regular)
        searchLabel.lineBreakMode = .byTruncatingTail
        searchLabel.setContentHuggingPriority(.required, for: .horizontal)
        searchLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        searchTextStack.addArrangedSubview(searchLabel)

        searchCaret.translatesAutoresizingMaskIntoConstraints = false
        searchCaret.layer.cornerRadius = 1
        searchTextStack.addArrangedSubview(searchCaret)

        searchClearButton.translatesAutoresizingMaskIntoConstraints = false
        searchClearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        searchClearButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .regular),
            forImageIn: .normal
        )
        searchClearButton.addTarget(self, action: #selector(handleClearSearchTap), for: .touchUpInside)
        searchChrome.addSubview(searchClearButton)

        searchLanguageButton.translatesAutoresizingMaskIntoConstraints = false
        searchLanguageButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        searchLanguageButton.setTitle(searchLanguage.shortLabel, for: .normal)
        searchLanguageButton.layer.cornerRadius = 11
        searchLanguageButton.layer.cornerCurve = .continuous
        searchLanguageButton.addTarget(self, action: #selector(handleSearchLanguageToggle), for: .touchUpInside)
        searchChrome.addSubview(searchLanguageButton)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceHorizontal = true
        collectionView.alwaysBounceVertical = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
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

            searchTextStack.leadingAnchor.constraint(
                equalTo: searchIcon.trailingAnchor,
                constant: Metrics.searchTextSpacing
            ),
            searchTextStack.trailingAnchor.constraint(
                lessThanOrEqualTo: searchLanguageButton.leadingAnchor,
                constant: -6
            ),
            searchTextStack.centerYAnchor.constraint(equalTo: searchChrome.centerYAnchor),

            searchCaret.widthAnchor.constraint(equalToConstant: 2),
            searchCaret.heightAnchor.constraint(equalToConstant: 24),

            searchLanguageButton.trailingAnchor.constraint(equalTo: searchClearButton.leadingAnchor, constant: -6),
            searchLanguageButton.centerYAnchor.constraint(equalTo: searchChrome.centerYAnchor),
            searchLanguageButton.heightAnchor.constraint(equalToConstant: 22),
            searchLanguageButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            searchClearButton.trailingAnchor.constraint(
                equalTo: searchChrome.trailingAnchor,
                constant: -Metrics.searchClearTrailing
            ),
            searchClearButton.centerYAnchor.constraint(equalTo: searchChrome.centerYAnchor),
            searchClearButton.widthAnchor.constraint(equalToConstant: Metrics.searchClearSize),
            searchClearButton.heightAnchor.constraint(equalToConstant: Metrics.searchClearSize),

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
            let button = EmojiCategoryButton(selectionDiameter: Metrics.categorySelectionDiameter)
            button.setImage(UIImage(systemName: category.symbolName), for: .normal)
            button.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(pointSize: 20, weight: .regular),
                forImageIn: .normal
            )
            button.accessibilityLabel = category.accessibilityLabel
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
        searchCaret.backgroundColor = KeyboardTheme.textColor(for: traitCollection)
        searchClearButton.tintColor = KeyboardTheme.emojiPlaceholderColor(for: traitCollection)
        searchLanguageButton.setTitleColor(KeyboardTheme.textColor(for: traitCollection), for: .normal)
        searchLanguageButton.backgroundColor = KeyboardTheme.emojiCategorySelectedBackgroundColor(for: traitCollection)
        let inactiveTint = KeyboardTheme.emojiCategoryTintColor(selected: false, traitCollection: traitCollection)
        keyboardButton.setTitleColor(inactiveTint, for: .normal)
        backspaceButton.tintColor = KeyboardTheme.emojiCategoryTintColor(selected: false, traitCollection: traitCollection)
        collectionView.indicatorStyle = traitCollection.userInterfaceStyle == .dark ? .white : .black
        reloadCategoryButtons()
        updateSearchLabelAppearance()
    }

    private func reloadCategoryButtons() {
        for (category, button) in categoryButtons {
            let selected = category == selectedCategory && !isSearchActive
            button.update(
                selected: selected,
                tintColor: KeyboardTheme.emojiCategoryTintColor(
                    selected: selected,
                    traitCollection: traitCollection
                ),
                selectedBackgroundColor: KeyboardTheme.emojiCategorySelectedBackgroundColor(for: traitCollection)
            )
        }
    }

    private func navigableCategories() -> [EmojiCategory] {
        EmojiCategory.visibleCases.filter { category in
            category != .recents || !recentEmojis.isEmpty
        }
    }

    private func selectCategory(_ category: EmojiCategory, animated: Bool = true) {
        if category == .recents, recentsSnapshotNeedsRefresh || !sectionCategories.contains(.recents) {
            rebuildBrowsingSections()
            recentsSnapshotNeedsRefresh = false
            collectionView.reloadData()
        } else if isSearchActive || sectionCategories.isEmpty {
            rebuildBrowsingSections()
        }
        guard sectionCategories.contains(category) else { return }

        guard category != selectedCategory || isSearchActive else {
            scrollToCategory(category, animated: animated)
            return
        }

        isSearchActive = false
        searchQuery = ""
        selectedCategory = category
        if sectionCategories.isEmpty {
            rebuildBrowsingSections()
        }
        reloadCategoryButtons()
        scrollToCategory(category, animated: animated)
    }
    private func reloadItems() {
        dismissVariantPopover(animated: false)
        if isSearchActive || selectedCategory == .recents {
            recentsSnapshotNeedsRefresh = false
        }
        switch selectedCategory {
        case _ where isSearchActive:
            searchItems = searchQuery.isEmpty
                ? searchIdleItems()
                : applyVariantPreferences(to: searchResults())
            searchLabel.text = searchQuery
        case .recents:
            rebuildBrowsingSections()
            searchLabel.text = "Search Emoji"
            if !sectionCategories.contains(.recents) {
                selectedCategory = .smileys
            }
        default:
            rebuildBrowsingSections()
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
        updateSearchControls()
        collectionView.reloadData()
        if isSearchActive {
            collectionView.setContentOffset(.zero, animated: false)
        } else {
            scrollToCategory(selectedCategory, animated: false)
        }
    }

    private func rebuildBrowsingSections() {
        let pairs: [(EmojiCategory, [EmojiItem])] = navigableCategories().compactMap { category in
            let items = category == .recents
                ? dataStore.items(for: visibleRecentEmojis())
                : applyVariantPreferences(to: dataStore.items(in: category))
            return items.isEmpty ? nil : (category, items)
        }
        sectionCategories = pairs.map(\.0)
        sectionItems = pairs.map(\.1)
        if !sectionCategories.contains(selectedCategory), let fallback = sectionCategories.first {
            selectedCategory = fallback
        }
    }

    private func scrollToCategory(_ category: EmojiCategory, animated: Bool) {
        guard
            !isSearchActive,
            let section = sectionCategories.firstIndex(of: category),
            sectionItems.indices.contains(section),
            !sectionItems[section].isEmpty
        else {
            return
        }

        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(
            at: IndexPath(item: 0, section: section),
            at: .left,
            animated: animated
        )
    }

    private func item(at indexPath: IndexPath) -> EmojiItem? {
        if isSearchActive {
            guard indexPath.section == 0, searchItems.indices.contains(indexPath.item) else {
                return nil
            }
            return searchItems[indexPath.item]
        }

        guard
            sectionItems.indices.contains(indexPath.section),
            sectionItems[indexPath.section].indices.contains(indexPath.item)
        else {
            return nil
        }
        return sectionItems[indexPath.section][indexPath.item]
    }

    private func updateSelectedCategoryForVisibleContent() {
        guard !isSearchActive, !sectionCategories.isEmpty else { return }

        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
        guard !visibleIndexPaths.isEmpty else { return }

        let referenceX = collectionView.contentOffset.x + collectionView.bounds.width / 2
        let closestSection = visibleIndexPaths.compactMap { indexPath -> (section: Int, distance: CGFloat)? in
            guard
                sectionCategories.indices.contains(indexPath.section),
                let attributes = collectionView.layoutAttributesForItem(at: indexPath)
            else {
                return nil
            }
            return (indexPath.section, abs(attributes.frame.midX - referenceX))
        }
        .min { lhs, rhs in
            lhs.distance < rhs.distance
        }?
        .section

        guard
            let closestSection,
            sectionCategories.indices.contains(closestSection)
        else {
            return
        }

        let category = sectionCategories[closestSection]
        guard category != selectedCategory else { return }
        selectedCategory = category
        reloadCategoryButtons()
    }

    private func updateSearchLabelAppearance() {
        searchLabel.textColor = isSearchActive && !searchQuery.isEmpty
            ? KeyboardTheme.textColor(for: traitCollection)
            : KeyboardTheme.emojiPlaceholderColor(for: traitCollection)
    }

    private func updateSearchControls() {
        let showsClearButton = isSearchActive && !searchQuery.isEmpty
        searchClearButton.isHidden = !showsClearButton
        searchClearButton.isEnabled = showsClearButton
        searchLanguageButton.isHidden = !isSearchActive
        searchCaret.isHidden = !isSearchActive

        guard isSearchActive else {
            searchCaret.layer.removeAllAnimations()
            searchCaret.alpha = 0
            return
        }

        guard searchCaret.layer.animation(forKey: "blink") == nil else { return }
        searchCaret.alpha = 1
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = 0.55
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        searchCaret.layer.add(animation, forKey: "blink")
    }

    private func searchIdleItems() -> [EmojiItem] {
        let recentItems = dataStore.items(for: visibleRecentEmojis())
        if !recentItems.isEmpty {
            return recentItems
        }
        return applyVariantPreferences(to: dataStore.items(in: .smileys))
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

    @objc private func handleClearSearchTap() {
        guard isSearchActive, !searchQuery.isEmpty else { return }
        delegate?.emojiPanelViewDidRequestClearSearch(self)
    }

    @objc private func handleCategoryTap(_ sender: EmojiCategoryButton) {
        guard let category = EmojiCategory.visibleCases.first(where: { categoryIndex($0) == sender.tag }) else {
            return
        }
        selectCategory(category)
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
                let item = item(at: indexPath),
                let cell = collectionView.cellForItem(at: indexPath)
            else {
                return
            }
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
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        isSearchActive ? 1 : sectionItems.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if isSearchActive {
            return section == 0 ? searchItems.count : 0
        }
        guard sectionItems.indices.contains(section) else { return 0 }
        return sectionItems[section].count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: EmojiCell.reuseIdentifier,
            for: indexPath
        ) as! EmojiCell
        if let item = item(at: indexPath) {
            cell.update(with: item)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = item(at: indexPath) else { return }
        dismissVariantPopover(animated: false)
        delegate?.emojiPanelView(self, didSelect: item)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateSelectedCategoryForVisibleContent()
    }
}

private final class EmojiCategoryButton: UIButton {
    private let selectedBackgroundView = UIView()
    private let selectionDiameter: CGFloat

    init(selectionDiameter: CGFloat) {
        self.selectionDiameter = selectionDiameter
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(selected: Bool, tintColor: UIColor, selectedBackgroundColor: UIColor) {
        self.tintColor = tintColor
        selectedBackgroundView.backgroundColor = selected ? selectedBackgroundColor : .clear
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let diameter = min(selectionDiameter, bounds.width - 4, bounds.height - 4)
        selectedBackgroundView.frame = CGRect(
            x: (bounds.width - diameter) / 2,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        selectedBackgroundView.layer.cornerRadius = diameter / 2
        selectedBackgroundView.layer.cornerCurve = .continuous
    }

    private func configure() {
        backgroundColor = .clear
        contentHorizontalAlignment = .center
        contentVerticalAlignment = .center

        selectedBackgroundView.isUserInteractionEnabled = false
        selectedBackgroundView.backgroundColor = .clear
        addSubview(selectedBackgroundView)
        sendSubviewToBack(selectedBackgroundView)
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
