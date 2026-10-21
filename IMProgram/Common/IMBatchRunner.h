//  IMBatchRunner.h
//  有界并发的批量执行器（纯逻辑、可单测）：逐项调用 work，同时在途最多 limit 个，全部结束后回调一次。
//  会话列表批量已读 / 批量删除用它把逐条接口的瞬时请求量压住（设计 CONV_LIST_EDIT_MODE_DESIGN §4）。
//  所有回调都在调用线程（主线程）上，不做线程切换：work 的 done 必须在主线程调用。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMBatchRunner : NSObject

/// work：处理一项，完成后**恰好调用一次** done(error)。
/// completion：全部结束后调用一次，参数依次为成功项、失败项（均保持 items 顺序）。
+ (void)forEach:(NSArray *)items
    concurrency:(NSUInteger)limit
           work:(void (^)(id item, void (^done)(NSError *_Nullable error)))work
     completion:(void (^)(NSArray *succeeded, NSArray *failed))completion;

@end

NS_ASSUME_NONNULL_END
