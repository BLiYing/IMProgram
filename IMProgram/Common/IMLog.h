//  IMLog.h
//  统一日志宏：封装 NSLog，Release 下关闭。禁止裸 NSLog 散落（见 CODING_STYLE.md）。

#ifndef IMLog_h
#define IMLog_h

#ifdef DEBUG
    #define IMLog(fmt, ...) NSLog((@"[IM] " fmt), ##__VA_ARGS__)
#else
    #define IMLog(fmt, ...) do {} while (0)
#endif

#endif /* IMLog_h */
