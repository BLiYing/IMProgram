//  IMProtocol.m

#import "IMProtocol.h"

NSString * const kIMTypePing     = @"ping";
NSString * const kIMTypePong     = @"pong";
NSString * const kIMTypeAuth     = @"auth";
NSString * const kIMTypeSendMsg  = @"send_msg";
NSString * const kIMTypeAck      = @"ack";
NSString * const kIMTypeNewMsg   = @"new_msg";
NSString * const kIMTypeReceipt  = @"receipt";
NSString * const kIMTypeTyping   = @"typing";
NSString * const kIMTypePresence = @"presence";
NSString * const kIMTypeSyncReq  = @"sync_req";
NSString * const kIMTypeSyncResp = @"sync_resp";
NSString * const kIMTypeFriend   = @"friend";
NSString * const kIMTypeGroup    = @"group";
NSString * const kIMTypeMsgOp    = @"msg_op";
NSString * const kIMTypeError    = @"error";

NSString * const kIMMsgOpRecall  = @"recall";
NSString * const kIMMsgOpEdit    = @"edit";
NSString * const kIMMsgOpPin      = @"pin";

const int64_t kIMRecallWindowMs = 2 * 60 * 1000;

NSString * const kIMKeyType = @"type";
NSString * const kIMKeySeq  = @"seq";
NSString * const kIMKeyData = @"data";

NSString *IMConversationID(NSString *uidA, NSString *uidB) {
    NSString *a = uidA ?: @"";
    NSString *b = uidB ?: @"";
    if ([a compare:b] == NSOrderedDescending) {
        NSString *tmp = a; a = b; b = tmp;
    }
    return [NSString stringWithFormat:@"u_%@_u_%@", a, b];
}
