//  IMMediaPickerEntry.m

#import "IMMediaPickerEntry.h"
#import "IMMediaPicker.h"
#import "IMMediaPickerViewController.h"
#import "IMLog.h"

@implementation IMMediaPickerEntry

+ (void)presentFromViewController:(UIViewController *)host
                handlesCompletion:(void (^)(NSArray<IMPickedMediaHandle *> *))completion {
    IMMediaPickerViewController *picker = [IMMediaPickerViewController new];
    __weak IMMediaPickerViewController *weakPicker = picker;
    picker.onFinish = ^(NSArray<PHAsset *> *assets, BOOL sendOriginal) {
        // 句柄只包一层 PHAsset，不做任何解码/压缩/转码（那些在句柄 loadData 时逐项进行）——选完秒回调。
        NSMutableArray<IMPickedMediaHandle *> *handles = [NSMutableArray arrayWithCapacity:assets.count];
        for (PHAsset *asset in assets) {
            [handles addObject:[IMMediaPicker handleForPhotoAsset:asset original:sendOriginal]];
        }
        IMLogDebugWithTag(IMLogTagMedia, @"picker_finish count=%lu original=%d", (unsigned long)handles.count, sendOriginal);
        [weakPicker dismissViewControllerAnimated:YES completion:nil];
        if (completion) { completion(handles); }
    };
    [host presentViewController:picker animated:YES completion:nil];
}

@end
