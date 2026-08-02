import UIKit
import Lottie

/// 直接渲染 Telegram `UserAvatarMask.tgs` 的原始 Lottie 关键帧。
/// 页面只提供 0...1 滚动进度，不让动画自行播放，行为对应 Telegram `AnimationNode.setProgress`。
@objcMembers
@objc(IMTelegramAvatarMaskView)
public final class IMTelegramAvatarMaskView: UIView {
    private static let animation: LottieAnimation? = LottieAnimation.named("UserAvatarMask")

    private let animationView: LottieAnimationView

    public override init(frame: CGRect) {
        let configuration = LottieConfiguration(
            renderingEngine: .mainThread,
            decodingStrategy: .dictionaryBased,
            reducedMotionOption: .standardMotion
        )
        animationView = LottieAnimationView(
            animation: Self.animation,
            configuration: configuration
        )
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        animationView.backgroundColor = .clear
        animationView.contentMode = .scaleToFill
        animationView.isUserInteractionEnabled = false
        addSubview(animationView)
        setProgress(0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        animationView.frame = bounds
    }

    public func setProgress(_ progress: CGFloat) {
        let value = min(max(progress, 0), 1)
        setNeedsLayout()
        layoutIfNeeded()
        animationView.currentProgress = value
        animationView.forceDisplayUpdate()
    }

}

/// 对应 Telegram `DynamicIslandBlurNode`：滚动进度连续控制暗色模糊、径向渐变与黑色融合层。
@objcMembers
@objc(IMTelegramAvatarEffectsView)
public final class IMTelegramAvatarEffectsView: UIView {
    private let effectView = UIVisualEffectView(effect: nil)
    private let gradientView = UIImageView(image: IMTelegramAvatarEffectsView.makeGradientImage())
    private let fadeView = UIView()
    private var animator: UIViewPropertyAnimator?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        effectView.isUserInteractionEnabled = false
        gradientView.isUserInteractionEnabled = false
        fadeView.isUserInteractionEnabled = false
        fadeView.backgroundColor = .black
        addSubview(effectView)
        addSubview(gradientView)
        addSubview(fadeView)
        setProgress(0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        animator?.stopAnimation(true)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        effectView.frame = bounds
        fadeView.frame = bounds
        let gradientSize = CGSize(width: 100, height: 100)
        gradientView.frame = CGRect(
            x: (bounds.width - gradientSize.width) / 2,
            y: 0,
            width: gradientSize.width,
            height: gradientSize.height
        )
    }

    public func setProgress(_ progress: CGFloat) {
        let value = min(max(progress, 0), 1)
        isHidden = value <= 0.03
        fadeView.alpha = min(max(-0.25 + value * 1.55, 0), 1)

        guard value > 0 else {
            animator?.stopAnimation(true)
            animator = nil
            effectView.effect = nil
            return
        }

        var blurValue = value
        if animator == nil {
            let propertyAnimator = UIViewPropertyAnimator(duration: 1, curve: .linear)
            effectView.effect = nil
            propertyAnimator.addAnimations { [weak self] in
                self?.effectView.effect = UIBlurEffect(style: .dark)
            }
            animator = propertyAnimator
            if blurValue > 0.99 {
                blurValue = 0.99
            }
        }
        animator?.fractionComplete = min(max(-0.1 + blurValue * 1.1, 0), 1)
    }

    private static func makeGradientImage() -> UIImage? {
        let size = CGSize(width: 100, height: 100)
        return UIGraphicsImageRenderer(size: size).image { rendererContext in
            let colors = [
                UIColor.clear.cgColor,
                UIColor.clear.cgColor,
                UIColor.black.cgColor,
            ] as CFArray
            var locations: [CGFloat] = [0, 0.87, 1]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: &locations
            ) else {
                return
            }
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + 38)
            rendererContext.cgContext.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: 90,
                options: .drawsAfterEndLocation
            )
        }
    }
}
