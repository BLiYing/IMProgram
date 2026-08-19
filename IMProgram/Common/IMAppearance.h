//  IMAppearance.h
//  全局外观偏好：本地持久化、跨页面通知、浅色/深色模式与聊天个性化设置。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const IMAppearanceDidChangeNotification;

typedef NS_ENUM(NSInteger, IMAppearanceMode) {
    IMAppearanceModeSystem = 0,
    IMAppearanceModeLight,
    IMAppearanceModeDark,
};

@interface IMAppearance : NSObject

@property (class, nonatomic, readonly) IMAppearance *shared;
@property (nonatomic, assign) IMAppearanceMode mode;
@property (nonatomic, copy) NSString *themeID;       // classic/ocean/violet/midnight 及 lime…prussian-blue 等色系主题
@property (nonatomic, copy) NSString *wallpaperID;   // doodle / gradient / plain
@property (nonatomic, assign) CGFloat chatFontSize;  // 14...22
@property (nonatomic, assign) CGFloat bubbleRadius;  // 6...24
@property (nonatomic, assign) BOOL animationsEnabled;

@property (nonatomic, readonly) UIColor *accentColor;
@property (nonatomic, readonly) UIColor *bubbleMeColor;
@property (nonatomic, readonly) UIColor *wallpaperTopColor;
@property (nonatomic, readonly) UIColor *wallpaperBottomColor;
@property (nonatomic, readonly) UIColor *wallpaperDoodleColor;

- (UIColor *)accentColorForThemeID:(NSString *)themeID;
- (UIColor *)bubbleMeColorForThemeID:(NSString *)themeID;
- (NSArray<UIColor *> *)wallpaperColorsForThemeID:(NSString *)themeID;
- (void)applyInterfaceStyle;
- (void)resetToDefaults;

@end

NS_ASSUME_NONNULL_END
