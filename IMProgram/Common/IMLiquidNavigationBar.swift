import UIKit

@objc(IMLiquidNavigationBarDelegate)
public protocol IMLiquidNavigationBarDelegate: NSObjectProtocol {
    func liquidNavigationBarDidTapBack(_ bar: IMLiquidNavigationBar)
    func liquidNavigationBarDidTapAction(_ bar: IMLiquidNavigationBar)
    func liquidNavigationBarDidTapLeft(_ bar: IMLiquidNavigationBar)
}

private final class IMLiquidHighlightButton: UIButton {
    override var isHighlighted: Bool {
        didSet {
            let target = isHighlighted
                ? CGAffineTransform(scaleX: 0.94, y: 0.94)
                : .identity
            UIView.animate(
                withDuration: 0.16,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
            ) {
                self.transform = target
                self.alpha = self.isHighlighted ? 0.72 : 1.0
            }
        }
    }
}

@objcMembers
@objc(IMLiquidNavigationBar)
public final class IMLiquidNavigationBar: UIView {
    public weak var delegate: IMLiquidNavigationBarDelegate?

    public var titleText: String = "" {
        didSet { titleLabel.text = titleText }
    }

    public var subtitleText: String = "" {
        didSet { subtitleLabel.text = subtitleText }
    }

    public var actionTitle: String? {
        didSet {
            actionButton.setTitle(actionTitle, for: .normal)
            actionButton.accessibilityLabel = actionTitle
            actionButton.isHidden = (actionTitle?.isEmpty ?? true) && actionImage == nil
            updateCompactContentVisibility()
            setNeedsLayout()
        }
    }

    public var actionImage: UIImage? {
        didSet {
            actionButton.setImage(actionImage, for: .normal)
            actionButton.isHidden = (actionTitle?.isEmpty ?? true) && actionImage == nil
            updateCompactContentVisibility()
            setNeedsLayout()
        }
    }

    public var actionEnabled: Bool = true {
        didSet { actionButton.isEnabled = actionEnabled }
    }

    /// 单个图标操作（加号、通讯录添加等）使用独立圆形按钮；带文字的操作保持胶囊形。
    public var actionCircular: Bool = false {
        didSet { setNeedsLayout() }
    }

    /// 仅聊天页保留中间标题的 Liquid Glass 背景；其他页面只显示文字。
    public var showsTitleGlass: Bool = false {
        didSet { updateCompactContentVisibility() }
    }

    public var showsBackButton: Bool = true {
        didSet { updateLeftButton() }
    }

    public var leftTitle: String? {
        didSet { updateLeftButton() }
    }

    public var leftImage: UIImage? {
        didSet { updateLeftButton() }
    }

    /// 中间标题胶囊的显隐进度；返回按钮和右侧操作按钮始终保留。
    /// 详情页会把头像水滴吸附进度映射到此属性，避免初始状态出现第二套标题栏。
    public var compactContentProgress: CGFloat = 0 {
        didSet { updateCompactContentVisibility() }
    }

    /// 头像大图铺满头部时为 1，折叠到普通页面背景时为 0。
    /// 大图态强制使用白色前景和轻微暗色承托，避免浅色模式下按钮落在照片上失去对比度。
    public var immersiveAppearanceProgress: CGFloat = 0 {
        didSet { refreshColors() }
    }

    /// Telegram PeerInfo 的导航背景在资料头部展开时完全透明，随内容折叠才渐进显现。
    public var backgroundEffectProgress: CGFloat = 1 {
        didSet { updateBackgroundEffect() }
    }

    private let backButton = IMLiquidHighlightButton(type: .system)
    private let actionButton = IMLiquidHighlightButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let backGlass = UIVisualEffectView()
    private let titleGlass = UIVisualEffectView()
    private let actionGlass = UIVisualEffectView()
    private let backgroundGlass = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))

    @objc(initWithTitle:subtitle:actionTitle:)
    public init(title: String, subtitle: String, actionTitle: String?) {
        self.titleText = title
        self.subtitleText = subtitle
        self.actionTitle = actionTitle
        super.init(frame: .zero)
        buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildView() {
        backgroundColor = .clear
        isOpaque = false

        backgroundGlass.isUserInteractionEnabled = false
        insertSubview(backgroundGlass, at: 0)
        updateBackgroundEffect()

        [backGlass, titleGlass, actionGlass].forEach { glass in
            glass.effect = Self.makeGlassEffect()
            glass.isUserInteractionEnabled = false
            glass.layer.masksToBounds = true
            glass.layer.cornerCurve = .continuous
            addSubview(glass)
        }

        backGlass.layer.cornerRadius = 22
        titleGlass.layer.cornerRadius = 24
        actionGlass.layer.cornerRadius = 22

        let chevron = UIImage(
            systemName: "chevron.backward",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        )
        backButton.setImage(chevron, for: .normal)
        backButton.accessibilityLabel = "返回"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        addSubview(backButton)

        actionButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        actionButton.accessibilityLabel = actionTitle
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        actionButton.isHidden = (actionTitle?.isEmpty ?? true) && actionImage == nil
        addSubview(actionButton)

        titleLabel.text = titleText
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        addSubview(titleLabel)

        subtitleLabel.text = subtitleText
        subtitleLabel.textAlignment = .center
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        addSubview(subtitleLabel)
        refreshColors()
        updateLeftButton()
        updateCompactContentVisibility()
    }

    private func refreshColors() {
        let progress = min(max(immersiveAppearanceProgress, 0), 1)
        // 显式按当前 trait 解析，并在照片态平滑过渡到白色，避免浅色模式按钮落在明暗复杂照片上看不见。
        let label = UIColor.label.resolvedColor(with: traitCollection)
        let primary = Self.mix(label, .white, progress: progress)
        let secondary = UIColor.secondaryLabel.resolvedColor(with: traitCollection)
        backButton.tintColor = primary
        actionButton.tintColor = primary
        actionButton.setTitleColor(primary, for: .normal)
        titleLabel.textColor = primary
        subtitleLabel.textColor = secondary
        let photoScrim = UIColor.black.withAlphaComponent(0.16 * progress)
        backGlass.backgroundColor = photoScrim
        actionGlass.backgroundColor = photoScrim
    }

    private static func mix(_ from: UIColor, _ to: UIColor, progress: CGFloat) -> UIColor {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        guard from.getRed(&fr, green: &fg, blue: &fb, alpha: &fa),
              to.getRed(&tr, green: &tg, blue: &tb, alpha: &ta) else {
            return progress >= 0.5 ? to : from
        }
        let p = min(max(progress, 0), 1)
        return UIColor(
            red: fr + (tr - fr) * p,
            green: fg + (tg - fg) * p,
            blue: fb + (tb - fb) * p,
            alpha: fa + (ta - fa) * p
        )
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection == nil ||
            traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            [backGlass, titleGlass, actionGlass].forEach { $0.effect = Self.makeGlassEffect() }
            backgroundGlass.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            refreshColors()
        }
    }

    private func updateCompactContentVisibility() {
        let progress = min(max(compactContentProgress, 0), 1)
        // 标题只保留文字，避免中间再出现一层玻璃胶囊；按钮玻璃仍由两侧独立承载。
        titleGlass.isHidden = !showsTitleGlass
        titleGlass.alpha = showsTitleGlass ? progress : 0
        titleLabel.alpha = progress
        subtitleLabel.alpha = progress
        actionGlass.isHidden = actionButton.isHidden
        actionGlass.alpha = actionButton.isHidden ? 0 : 1
        actionButton.alpha = 1
        actionButton.isUserInteractionEnabled = !actionButton.isHidden
    }

    private func updateBackgroundEffect() {
        backgroundGlass.alpha = min(max(backgroundEffectProgress, 0), 1)
    }

    private func updateLeftButton() {
        let custom = leftTitle?.isEmpty == false || leftImage != nil
        let chevron = UIImage(systemName: "chevron.backward",
                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))
        backButton.setTitle(custom ? leftTitle : nil, for: .normal)
        backButton.setImage(custom ? leftImage : chevron, for: .normal)
        backButton.accessibilityLabel = custom ? (leftTitle ?? "") : "返回"
        backButton.isHidden = !showsBackButton && !custom
        backGlass.isHidden = backButton.isHidden
        setNeedsLayout()
    }

    private static func makeGlassEffect() -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            return effect
        }
        return UIBlurEffect(style: .systemChromeMaterial)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // 从屏幕顶部覆盖到导航栏下缘，包含状态栏区域；页面内容可在其下方继续滚动。
        backgroundGlass.frame = bounds
        // 底缘柔和退场，避免磨砂导航与下方内容形成一条割裂的硬边。
        let fade = CAGradientLayer()
        fade.frame = backgroundGlass.bounds
        fade.colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor]
        fade.locations = [0, 0.72, 1]
        backgroundGlass.layer.mask = fade
        let top = safeAreaInsets.top
        let buttonY = top + 6
        let buttonSize: CGFloat = 44
        let side: CGFloat = 16
        let actionWidth = actionButton.isHidden ? 0 : (actionCircular ? buttonSize : max(68, actionButton.intrinsicContentSize.width + 28))
        let customLeft = leftTitle?.isEmpty == false || leftImage != nil
        let leftWidth = customLeft ? max(68, backButton.intrinsicContentSize.width + 24) : buttonSize
        let centerWidth = min(250, max(132, bounds.width - leftWidth - side - side - actionWidth - 24))
        let centerX = (bounds.width - centerWidth) / 2

        backGlass.frame = CGRect(x: side, y: buttonY, width: leftWidth, height: buttonSize)
        backButton.frame = backGlass.frame

        actionGlass.frame = CGRect(x: bounds.width - side - actionWidth, y: buttonY,
                                   width: actionWidth, height: buttonSize)
        actionGlass.layer.cornerRadius = actionCircular ? buttonSize / 2 : 22
        actionButton.frame = actionGlass.frame

        titleGlass.frame = CGRect(x: centerX, y: buttonY, width: centerWidth, height: buttonSize)
        let hasSubtitle = !(subtitleLabel.text?.isEmpty ?? true)
        let titleY = hasSubtitle ? buttonY + 2 : buttonY + 11
        titleLabel.frame = CGRect(x: centerX + 12, y: titleY, width: centerWidth - 24, height: 22)
        subtitleLabel.frame = CGRect(x: centerX + 12, y: buttonY + 23, width: centerWidth - 24, height: 17)
    }

    @objc private func backTapped() {
        if leftTitle?.isEmpty == false || leftImage != nil {
            delegate?.liquidNavigationBarDidTapLeft(self)
        } else {
            delegate?.liquidNavigationBarDidTapBack(self)
        }
    }

    @objc private func actionTapped() {
        delegate?.liquidNavigationBarDidTapAction(self)
    }
}
