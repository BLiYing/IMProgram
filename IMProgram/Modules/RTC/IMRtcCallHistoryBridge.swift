import Foundation
import IMCallEngine

/// `IMCallEngine.fetchCallHistory`（`async throws`，SDK 里唯一没标 `@objc` 的公开方法，
/// 因为它的返回类型 `IMCallHistoryPage`/`IMCallHistoryRecord` 是纯 Swift struct，
/// Swift 结构体天生不能出现在 `@objc` 签名里）到 ObjC 宿主 `IMRtcCall.m` 的桥接层。
///
/// 本类只做「调用 SDK + 把 struct 拍平成字典」，不做任何业务判断（未接判定/身份解析/分组一律留给
/// `IMCallHistoryRecord`/`IMCallHistoryPaginator`）。字典键沿用 `IMRtcCallRecordSender.m` 已经在用的
/// snake_case 词汇（`call_id`/`media_type`/`duration_sec`…）——聊天气泡通话记录与本页读的是同一批
/// 通话事实，用词一致方便对照，也省得再造一套命名。
///
/// 设计：IMServer docs/design/CALL_HISTORY_DESIGN.md §1（记录字段）/ §5（本文件即"调 SDK"那一步）。
@objcMembers
@objc(IMRtcCallHistoryBridge)
public final class IMRtcCallHistoryBridge: NSObject {

    /// `cursor`/回调里的 `nextCursor` 用 `NSNumber` 装 SDK 的 `Int64`（nil = 首页 / 已到底）。
    /// `completion` 恒在主线程回调，与 `IMRtcCall.m` 其它异步回调（`signTokenWithCompletion:` 等）
    /// 同一约定，调用方不用自己再切线程。
    // 显式 selector，不依赖 Swift → ObjC 的自动改名规则（那套规则本身没问题，但一旦这里改了参数顺序/
    // 命名，自动生成的 selector 会悄悄变而 IMRtcCall.m 的调用点毫无警觉——编译器只会在 selector 真的
    // 对不上时报错，届时定位成本远高于现在直接钉死）。
    @objc(fetchCallHistoryWithEngine:limit:cursor:completion:)
    public static func fetchCallHistory(engine: IMCallEngine, limit: Int, cursor: NSNumber?,
                                         completion: @escaping ([[String: Any]], NSNumber?, NSError?) -> Void) {
        let cursorValue: Int64? = cursor?.int64Value
        Task {
            do {
                let page = try await engine.fetchCallHistory(limit: limit, cursor: cursorValue)
                let dicts = page.records.map(dictionary(from:))
                let nextCursor = page.nextCursor.map { NSNumber(value: $0) }
                DispatchQueue.main.async { completion(dicts, nextCursor, nil) }
            } catch {
                // `IMRTCError` 已声明 `CustomNSError`（见 im-rtc IMErrorCode.swift），
                // `error as NSError` 保留 domain=IMRTCErrorInfo.domain / code=协议错误码 / 本地化描述，
                // 不会退化成泛用的「操作无法完成」。
                DispatchQueue.main.async { completion([], nil, error as NSError) }
            }
        }
    }

    private static func dictionary(from record: IMCallHistoryRecord) -> [String: Any] {
        [
            "call_id": record.callID,
            "room_id": record.roomID,
            "caller": record.caller,
            "media_type": record.mediaType,
            "is_group": record.isGroup,
            "reason": record.reason,
            "ended_by": record.endedBy,
            "duration_sec": record.durationSec,
            "started_at_ms": record.startedAtMS,
            "connected_at_ms": record.connectedAtMS,
            "ended_at_ms": record.endedAtMS,
            "user_data": record.userData,
            "chat_group_id": record.chatGroupID,
            "members": record.members.map { ["uid": $0.uid, "state": $0.state] },
        ]
    }
}
