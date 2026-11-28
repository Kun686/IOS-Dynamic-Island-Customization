//
//  HUDHelper.h
//  TrollSpeed
//
//  Created by Lessica on 2024/1/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

OBJC_EXTERN BOOL IsHUDEnabled(void);
OBJC_EXTERN void SetHUDEnabled(BOOL isEnabled);

#if DEBUG
OBJC_EXTERN void SimulateMemoryPressure(void);
#endif

OBJC_EXTERN NSUserDefaults *GetStandardUserDefaults(void);

// IslandKit 的数据目录 /var/mobile/Library/IslandKit。悬浮进程以 root 身份运行，它先建出来的目录归 root，
// 设置 App（mobile 用户）往里写备用头像、歌词时间轴、诊断报告都会被拒绝。
// 以 root 身份调用：把这个目录和其中的子目录改回 mobile:mobile（只改目录不改文件，不跟随符号链接，
// 不出这个目录），并预建设置 App 要用的子目录。非 root 调用时只建目录。返回是否全部完成
OBJC_EXTERN BOOL IKRepairDataDirectory(void);
// 设置 App 调用（会等待子进程，请放在后台线程）：数据目录已经可写就直接返回 YES；
// 否则以 root 身份启动自身的 -ik-data 修好属主，再检查一次
OBJC_EXTERN BOOL IKEnsureDataDirectoryWritable(void);

NS_ASSUME_NONNULL_END
