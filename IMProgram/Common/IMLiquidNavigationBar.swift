import UIKit

@objc(IMLiquidNavigationBarDelegate)
public protocol IMLiquidNavigationBarDelegate: NSObjectProtocol {
    func liquidNavigationBarDidTapBack(_ bar: IMLiquidNavigationBar)
    func liquidNavigationBarDidTapAction(_ bar: IMLiquidNavigationBar)
    func liquidNavigationBarDidTapLeft(_ bar: IMLiquidNavigationBar)
    /// 中间标题被点击（仅在 showsTitleGlass=YES 的页面，即聊天页可点）。可选实现。
    @objc optional func liquidNavigationBarDidTapTitle(_ bar: IMLiquidNavigationBar)
}

@objcMembers
@objc(IMLiquidNavigationBar)
public final class IMLiquidNavigationBar: UIView {
    public weak var delegate: IMLiquidNavigationBarDelegate?

    // MARK: - 可调背景参数（独立出来便于调试：改默认值→重编译即可看效果，全局生效）
    /// 磨砂整体不透明度系数（乘在每个实例的 backgroundEffectProgress 上）。
    /// 调小 → 整条导航磨砂更透明（0.0 完全透明、1.0 当前默认）。想"再透明一点"就调这里。
    public static var backgroundBlurAlpha: CGFloat = 1.0
    /// 深色模式磨砂的压暗 tint alpha。调小 → 深色下更透明（0 = 纯磨砂不压暗）。浅色模式恒为透明不受影响。
    public static var darkTintAlpha: CGFloat = 0.55
    /// 底缘渐隐蒙版：顶部保持"最实"的高度比例，其下平滑渐隐到导航栏下缘透明。
    /// 调小 → 过渡更长更柔和（消除"被切割"生硬感）；调大 → 实心区更多、过渡更短更硬。
    public static var fadeSolidTopRatio: CGFloat = 0.2

    // 说明：以下属性的 didSet 一律先做等值判断再落地。导航容器每个布局周期都会把整套属性重写一遍
    // （标题、左右按钮、进度…），而这些 didSet 会连带触发 setNeedsLayout / 重建按钮配置等重排；
    // 不挡住等值写入的话，滚动或打字时每帧都在做无意义的重排。

    // ⚠️ 这两处必须 setNeedsLayout()：标题的竖向槽位是按「有无副标题」二选一算的（见 layoutSubviews），
    // 有副标题时主标题上移让位、无副标题时整体居中。曾漏掉重排 → 单聊的「在线」是 presence 单独晚到的，
    // 期间没有任何别的属性变化触发布局，主标题仍停在「居中」槽位，副标题正好压进它下半部（重叠 7pt）；
    // 群聊因副标题与群名/头像同批到达、被 actionImage 的 didSet 顺带重排，才看似正常。
    public var titleText: String = "" {
        didSet {
            guard oldValue != titleText else { return }
            titleLabel.text = titleText
            setNeedsLayout()
        }
    }

    public var subtitleText: String = "" {
        didSet {
            guard oldValue != subtitleText else { return }
            subtitleLabel.text = subtitleText
            setNeedsLayout()
        }
    }

    public var actionTitle: String? {
        didSet {
            guard oldValue != actionTitle else { return }
            applyActionConfig()
            updateCompactContentVisibility()
            setNeedsLayout()
        }
    }

    public var actionImage: UIImage? {
        didSet {
            guard oldValue !== actionImage else { return }
            applyActionConfig()
            updateCompactContentVisibility()
            setNeedsLayout()
        }
    }

    public var actionEnabled: Bool = true {
        didSet {
            guard oldValue != actionEnabled else { return }
            actionButton.isEnabled = actionEnabled
        }
    }

    /// 单个图标操作（加号、通讯录添加等）使用独立圆形按钮；带文字的操作保持胶囊形。
    public var actionCircular: Bool = false {
        didSet {
            guard oldValue != actionCircular else { return }
            setNeedsLayout()
        }
    }

    /// 仅聊天页保留中间标题的 Liquid Glass 背景；其他页面只显示文字。
    public var showsTitleGlass: Bool = false {
        didSet {
            guard oldValue != showsTitleGlass else { return }
            updateCompactContentVisibility()
        }
    }

    public var showsBackButton: Bool = true {
        didSet {
            guard oldValue != showsBackButton else { return }
            applyBackConfig()
        }
    }

    /// 宿主额外撑大的顶部安全区（宿主 `additionalSafeAreaInsets.top`）。默认 0＝宿主未撑大。
    ///
    /// 存在的理由：本栏按 `safeAreaInsets.top + 6` 摆放按钮，而 `safeAreaInsets` 继承自宿主视图。
    /// 自持栏页面（详情/「我」）的宿主安全区就是状态栏，直接用没问题；但导航容器注入到普通页面的栏，
    /// 其宿主安全区已被容器用 `additionalSafeAreaInsets.top = 56` 撑大（好让列表内容从栏下方开始），
    /// 栏继承到「状态栏 + 56」，按钮会整体下移 56pt 落到 bounds 之外——可见但 hitTest 点不到。
    ///
    /// 这里刻意存"宿主加了多少"而非"状态栏是多少"：前者是常量，后者随设备/旋转/是否已入窗而变。
    /// 用减法从同一个 `safeAreaInsets` 里还原真实状态栏高度，任何时刻自洽——旋转、首次入窗都无需重新同步。
    public var hostExtraTopInset: CGFloat = 0 {
        didSet {
            guard oldValue != hostExtraTopInset else { return }
            setNeedsLayout()
        }
    }

    public var leftTitle: String? {
        didSet {
            guard oldValue != leftTitle else { return }
            applyBackConfig()
        }
    }

    public var leftImage: UIImage? {
        didSet {
            guard oldValue !== leftImage else { return }
            applyBackConfig()
        }
    }

    /// 中间标题胶囊的显隐进度；返回按钮和右侧操作按钮始终保留。
    /// 详情页会把头像水滴吸附进度映射到此属性，避免初始状态出现第二套标题栏。
    public var compactContentProgress: CGFloat = 0 {
        didSet {
            guard oldValue != compactContentProgress else { return }
            updateCompactContentVisibility()
        }
    }

    /// 头像大图铺满头部时为 1，折叠到普通页面背景时为 0。
    /// 大图态强制使用白色前景，避免浅色模式下按钮落在明暗复杂照片上失去对比度。
    public var immersiveAppearanceProgress: CGFloat = 0 {
        didSet {
            guard oldValue != immersiveAppearanceProgress else { return }
            refreshColors()
        }
    }

    /// Telegram PeerInfo 的导航背景在资料头部展开时完全透明，随内容折叠才渐进显现。
    public var backgroundEffectProgress: CGFloat = 1 {
        didSet {
            guard oldValue != backgroundEffectProgress else { return }
            updateBackgroundEffect()
        }
    }

    // 按钮本体即原生玻璃（iOS 26 用 UIButton.Configuration.glass()，旧系统降级 .gray() + 描边）：
    // 这样点击时能拿到系统 Liquid Glass 的按压放大/聚合动画，而不是手写缩放。此前用「普通按钮 +
    // 独立玻璃视图」分离结构，玻璃不参与交互、只能做 scale 0.94 的缩小，缺原生放大观感。
    private let backButton = UIButton(type: .system)
    private let actionButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let titleGlass = UIVisualEffectView()
    private let titleButton = UIButton(type: .custom) // 中间标题的点击区（仅聊天页启用），带按压缩放反馈
    private let backgroundGlass = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    // 底缘柔和退场蒙版：一次性创建，layoutSubviews 只更新 frame（避免每帧新建 CAGradientLayer）。
    private let backgroundFade = CAGradientLayer()

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
        // systemUltraThinMaterial 在深色模式下偏亮，磨砂会显成一块比背景亮的色块。
        // 叠一层随明暗自适应的背景色 tint：深色模式压向背景黑、浅色模式保持透明（不动浅色观感），
        // 与页面背景保持一致；tint 随磨砂一起被底部渐变蒙版渐隐，故渐变仍生效。
        backgroundGlass.contentView.backgroundColor = Self.backgroundTint()
        insertSubview(backgroundGlass, at: 0)
        // 颜色一次性设定；locations 交给 layoutSubviews 按 fadeSolidTopRatio 计算（便于调参即时生效）。
        backgroundFade.colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor]
        backgroundGlass.layer.mask = backgroundFade
        updateBackgroundEffect()

        titleGlass.effect = Self.makeGlassEffect()
        titleGlass.isUserInteractionEnabled = false
        titleGlass.layer.masksToBounds = true
        titleGlass.layer.cornerCurve = .continuous
        titleGlass.layer.cornerRadius = 24
        addSubview(titleGlass)

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        addSubview(backButton)

        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        addSubview(actionButton)

        titleLabel.text = titleText
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        addSubview(titleLabel)

        subtitleLabel.text = subtitleText
        subtitleLabel.textAlignment = .center
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        addSubview(subtitleLabel)

        // 中间标题点击区（覆盖在标题/副标题之上）：点击回调 delegate；按下缩放做 Liquid Glass 风格按压反馈。
        titleButton.addTarget(self, action: #selector(titleTapped), for: .touchUpInside)
        titleButton.addTarget(self, action: #selector(titlePressDown), for: [.touchDown, .touchDragEnter])
        titleButton.addTarget(self, action: #selector(titlePressUp),
                              for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        addSubview(titleButton)

        refreshColors()          // 内部会 applyBackConfig / applyActionConfig
        updateCompactContentVisibility()
    }

    /// 原生玻璃按钮配置：iOS 26 用 `.glass()`（自带按压放大）；旧系统 `.gray()` 填充 + 0.5pt 描边，
    /// 让胶囊在浅色纯白背景（会话/群列表/通讯录）上也能「浮起来」，修复 iOS 18 浅色下与背景难分辨。
    private func styledButtonConfig(image: UIImage?, title: String?, foreground: UIColor) -> UIButton.Configuration {
        var cfg: UIButton.Configuration
        if #available(iOS 26.0, *) {
            cfg = .glass()
        } else {
            cfg = .gray()
        }
        cfg.cornerStyle = .capsule
        cfg.contentInsets = .zero            // 尺寸由 layoutSubviews 的 frame 决定（圆钮 44×44）
        cfg.image = image
        if let title, !title.isEmpty {
            var container = AttributeContainer()
            container.font = .systemFont(ofSize: 17, weight: .medium)
            cfg.attributedTitle = AttributedString(title, attributes: container)
        }
        cfg.baseForegroundColor = foreground
        if #unavailable(iOS 26.0) {
            cfg.background.strokeColor = UIColor.separator
            cfg.background.strokeWidth = 0.5
            // 沉浸大图态用深色承托白图标（等价旧 photoScrim）；无沉浸时≈系统灰填充，浅色页也能辨。
            cfg.background.backgroundColor = currentButtonBackground()
        }
        return cfg
    }

    /// iOS<26 按钮承托底：无沉浸(progress0)≈系统灰填充（浅色页可辨）；沉浸大图(progress→1)渐入深色
    /// （白图标在浅色照片上可辨，等价旧 photoScrim）。iOS26 用原生玻璃，不需要它。
    private func currentButtonBackground() -> UIColor {
        let progress = min(max(immersiveAppearanceProgress, 0), 1)
        let base = UIColor.tertiarySystemFill.resolvedColor(with: traitCollection)
        return Self.mix(base, UIColor.black.withAlphaComponent(0.5), progress: progress)
    }

    private func chevronImage() -> UIImage? {
        UIImage(systemName: "chevron.backward",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))
    }

    private func applyBackConfig() {
        let custom = leftTitle?.isEmpty == false || leftImage != nil
        let leftIsText = leftTitle?.isEmpty == false
        // 图标型左按钮（默认返回箭头 / 自定义纯图标如叉叉）用圆形；文字型（如「取消」）才用胶囊。
        let image = leftIsText ? nil : (custom ? leftImage : chevronImage())
        let title = leftIsText ? leftTitle : nil
        backButton.configuration = styledButtonConfig(image: image, title: title, foreground: currentPrimary())
        backButton.accessibilityLabel = custom ? (leftTitle ?? "返回") : "返回"
        backButton.isHidden = !showsBackButton && !custom
        setNeedsLayout()
    }

    private func applyActionConfig() {
        let title = (actionTitle?.isEmpty ?? true) ? nil : actionTitle
        actionButton.configuration = styledButtonConfig(image: actionImage, title: title, foreground: currentPrimary())
        actionButton.isEnabled = actionEnabled
        actionButton.accessibilityLabel = actionTitle
        actionButton.isHidden = (actionTitle?.isEmpty ?? true) && actionImage == nil
        setNeedsLayout()
    }

    private func currentPrimary() -> UIColor {
        let progress = min(max(immersiveAppearanceProgress, 0), 1)
        let label = UIColor.label.resolvedColor(with: traitCollection)
        return Self.mix(label, .white, progress: progress)
    }

    private func refreshColors() {
        let primary = currentPrimary()
        titleLabel.textColor = primary
        subtitleLabel.textColor = UIColor.secondaryLabel.resolvedColor(with: traitCollection)
        // 只改前景色（沉浸态白色过渡）与 <26 承托底，不整体重建 Configuration——
        // 详情页头像滚动会逐帧改 immersiveAppearanceProgress，整体重建（含图片解码 / AttributedString）
        // 是滚动热路径上的无谓开销。首次（config 尚未建）才回退到完整构建。
        applyDynamicColors(to: backButton, primary: primary, rebuild: applyBackConfig)
        applyDynamicColors(to: actionButton, primary: primary, rebuild: applyActionConfig)
    }

    private func applyDynamicColors(to button: UIButton, primary: UIColor, rebuild: () -> Void) {
        guard button.configuration != nil else { rebuild(); return }
        button.configuration?.baseForegroundColor = primary
        if #unavailable(iOS 26.0) {
            button.configuration?.background.backgroundColor = currentButtonBackground()
        }
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
            titleGlass.effect = Self.makeGlassEffect()
            backgroundGlass.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            refreshColors()      // 重建按钮配置（前景色随 trait 重新解析）
        }
    }

    private func updateCompactContentVisibility() {
        let progress = min(max(compactContentProgress, 0), 1)
        // 标题只保留文字，避免中间再出现一层玻璃胶囊；按钮玻璃由按钮本体承载。
        titleGlass.isHidden = !showsTitleGlass
        titleGlass.alpha = showsTitleGlass ? progress : 0
        titleLabel.alpha = progress
        subtitleLabel.alpha = progress
        // 标题可点仅限展示玻璃且已显现（聊天页）；其他页面点击穿透、不拦截。
        titleButton.isUserInteractionEnabled = showsTitleGlass && progress > 0.5
        actionButton.alpha = 1
        actionButton.isUserInteractionEnabled = !actionButton.isHidden
    }

    private func updateBackgroundEffect() {
        backgroundGlass.alpha = min(max(backgroundEffectProgress, 0), 1) * Self.backgroundBlurAlpha
    }

    /// 磨砂背景 tint：深色模式压向背景黑，浅色模式透明。动态色随 trait 自动解析，无需手动刷新。
    private static func backgroundTint() -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.black.withAlphaComponent(IMLiquidNavigationBar.darkTintAlpha)
                : .clear
        }
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
        // 仅更新既有蒙版的 frame/locations（不再每帧重建 CAGradientLayer）；关隐式动画避免每次布局闪动。
        // 顶部 fadeSolidTopRatio 比例保持最实，其下平滑渐隐到导航栏下缘透明（从底部往状态栏逐渐加深）。
        let solid = min(max(Self.fadeSolidTopRatio, 0), 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundFade.frame = backgroundGlass.bounds
        backgroundFade.locations = [0, NSNumber(value: Double(solid)), 1]
        CATransaction.commit()
        let top = max(0, safeAreaInsets.top - hostExtraTopInset)
        let buttonY = top + 6
        let buttonSize: CGFloat = 44
        let side: CGFloat = 16
        let actionWidth = actionButton.isHidden ? 0 : (actionCircular ? buttonSize : max(68, actionButton.intrinsicContentSize.width + 28))
        // 左按钮：文字型（「取消」等）用胶囊宽；图标型（返回箭头 / 叉叉等）用圆形 44（修复叉叉椭圆）。
        let leftIsText = leftTitle?.isEmpty == false
        let leftWidth = leftIsText ? max(68, backButton.intrinsicContentSize.width + 24) : buttonSize
        // 标题盒宽度**按「文字按钮场景」一次算死**（预算 88pt/侧）：普通页（44 圆钮）与多选页
        //（「取消」文字钮）同宽，进出多选、右上角换文字钮都零跳变——此前按实际按钮宽动态收缩，
        // 状态切换时标题盒 220↔169 来回弹。兜底：某侧按钮实测超 88 预算时仍按实际值收缩
        //（防重叠优先于防跳变）；两侧各留 8pt 呼吸，宁可标题尾部截断也不压按钮。
        let sideBudget: CGFloat = 88
        let sideOccupied = max(side + sideBudget, max(side + leftWidth, side + actionWidth)) + 8
        let centerWidth = min(220, max(96, bounds.width - 2 * sideOccupied))
        let centerX = (bounds.width - centerWidth) / 2

        backButton.frame = CGRect(x: side, y: buttonY, width: leftWidth, height: buttonSize)

        actionButton.frame = CGRect(x: bounds.width - side - actionWidth, y: buttonY,
                                    width: actionWidth, height: buttonSize)

        titleGlass.frame = CGRect(x: centerX, y: buttonY, width: centerWidth, height: buttonSize)
        titleButton.frame = titleGlass.frame
        let hasSubtitle = !(subtitleLabel.text?.isEmpty ?? true)
        // 两行场景：主标题框高收到 20（原 22 几乎占满行盒，中文字形填满 em 盒会与副标题贴死），
        // 副标题下移到 buttonY+24 起 —— 主标题底(=buttonY+22) 与副标题顶(=buttonY+24) 留 2pt 间隙，消除重叠。
        let titleY = hasSubtitle ? buttonY + 2 : buttonY + 11
        titleLabel.frame = CGRect(x: centerX + 12, y: titleY, width: centerWidth - 24, height: 20)
        subtitleLabel.frame = CGRect(x: centerX + 12, y: buttonY + 24, width: centerWidth - 24, height: 16)
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

    @objc private func titleTapped() {
        delegate?.liquidNavigationBarDidTapTitle?(self)
    }

    @objc private func titlePressDown() { setTitlePressed(true) }
    @objc private func titlePressUp() { setTitlePressed(false) }

    /// 标题按压反馈：缩放标题玻璃与文字（Liquid Glass 风格轻按压）。只动 transform，
    /// 不碰 alpha（透明度由 compactContentProgress 控制，避免相互覆盖）。
    private func setTitlePressed(_ pressed: Bool) {
        let t = pressed ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
        UIView.animate(withDuration: 0.16, delay: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
            self.titleGlass.transform = t
            self.titleLabel.transform = t
            self.subtitleLabel.transform = t
        }
    }
}
