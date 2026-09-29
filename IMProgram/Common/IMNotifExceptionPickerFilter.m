//  IMNotifExceptionPickerFilter.m

#import "IMNotifExceptionPickerFilter.h"
#import "IMAccountIdentity.h" // IMIsSystemUserID

BOOL IMNotifExceptionPickerMatches(BOOL isGroup, BOOL muted, NSString *peer, BOOL wantGroup) {
    if (isGroup != wantGroup) { return NO; }
    if (muted) { return NO; }
    if (!isGroup && IMIsSystemUserID(peer)) { return NO; } // 系统通知单聊：服务端拒 send_msg to=system，列出来无意义
    return YES;
}
