//  IMChatSendPlan.h
//  点「发送」时，输入栏里攒着的东西（粘贴图 + 文字）该怎么发——从 IMChatViewController+Compose 的
//  sendTapped 抽出的纯决策。
//
//  这条判断错得**很安静**：图文合并只在一个很窄的条件下成立，判错 = 文字丢了 / 重复发了 /
//  引用丢了；编辑态判错 = 编辑被当成发新消息（对端多一条，原消息还是旧的）。
//
//  **三端口径 2026-10-04 对读过**（im-web `App.tsx` 的发送、im-android `ChatSendInput.kt` 的 `mergesIntoCaption`）：
//  「恰好 1 张 + 有字 + 非引用 → 合并成一条 caption 消息」三端一致；iOS 与 Web 另加「非编辑」，且两端
//  媒体发送都不带 replyTo，所以引用态保持文本单发以免丢引用。
//  **已知分歧（没对齐）**：「编辑态 + 输入栏里还攒着粘贴图」——iOS/Web 先发图、再发编辑；Android 编辑态
//  直接提交文字并 return，粘贴图原地留着。这个组合很冷，哪边对没有产品口径，先不动。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 粘贴图那一段怎么发。
typedef NS_ENUM(NSInteger, IMChatSendImagesMode) {
    /// 没有粘贴图。
    IMChatSendImagesNone = 0,
    /// 恰好 1 张且有文字、非编辑、非引用：文字作为 caption 与图**同发一条**，不再补发独立文本（Telegram 模型）。
    IMChatSendImagesSingleWithCaption,
    /// 图片各自发出（≥2 张共享一个相册 group_id 成宫格，宫格不带 caption）；文字另走文本那一段。
    IMChatSendImagesPlain,
};

/// 文字那一段怎么发。
typedef NS_ENUM(NSInteger, IMChatSendTextMode) {
    /// 不发（文字为空，或已作为 caption 随图发出）。
    IMChatSendTextNone = 0,
    /// 编辑态：发 msg_op edit，**不是**新消息。
    IMChatSendTextEdit,
    /// 普通文本发送（带引用与否由调用方另判）。
    IMChatSendTextSend,
};

typedef struct {
    IMChatSendImagesMode images;
    /// images == Plain 且 ≥2 张时为 YES：这批图共享同一个新相册 ID。单张不要 ID。
    BOOL imagesShareAlbumID;
    IMChatSendTextMode text;
} IMChatSendPlan;

/**
 @param pasteCount 预览条里攒的粘贴图张数。
 @param hasText    **去掉首尾空白后**文字非空。
 @param editing    正在编辑一条已上号的消息（editingMessage.convSeq > 0）。
 @param replying   正在引用一条已上号的消息（replyingTo.convSeq > 0）。
 */
extern IMChatSendPlan IMChatPlanSend(NSInteger pasteCount, BOOL hasText, BOOL editing, BOOL replying);

NS_ASSUME_NONNULL_END
