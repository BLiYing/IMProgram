//  IMChatSendPlan.m
//  规则与坑写在头文件注释里，这里只留实现。

#import "IMChatSendPlan.h"

IMChatSendPlan IMChatPlanSend(NSInteger pasteCount, BOOL hasText, BOOL editing, BOOL replying) {
    IMChatSendPlan plan = { IMChatSendImagesNone, NO, IMChatSendTextNone };
    if (pasteCount > 0) {
        if (pasteCount == 1 && hasText && !editing && !replying) {
            plan.images = IMChatSendImagesSingleWithCaption; // 文字随图发出，文本段不再发
            return plan;
        }
        plan.images = IMChatSendImagesPlain;
        plan.imagesShareAlbumID = pasteCount > 1;
    }
    if (hasText) { plan.text = editing ? IMChatSendTextEdit : IMChatSendTextSend; }
    return plan;
}
