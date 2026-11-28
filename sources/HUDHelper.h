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
// 不出这个目录），并预建设置 App 要用的子目录。非 root 调用时只建目录。返回数据目录是否全部完成。
// root 调用时还会把继承来的 TMPDIR（必须是 /private/var/mobile/Containers/Data/Application/<UUID>/tmp
// 或 /var/mobile/... 的同样写法，且是真目录）这一个目录本身改回 501:501 并补上属主的 rwx，结果不计入返回值
OBJC_EXTERN BOOL IKRepairDataDirectory(void);
// 设置 App 调用（会等待子进程，请放在后台线程）：数据目录已经可写就直接返回 YES；
// 否则以 root 身份启动自身的 -ik-data 修好属主，再检查一次
OBJC_EXTERN BOOL IKEnsureDataDirectoryWritable(void);

// 设置 App 调用（可能等待子进程，请放在后台线程）：本 App 的临时目录（NSTemporaryDirectory）能写就返回 YES，
// 不存在时先自己建；仍不能写时以 root 身份启动自身的 -ik-data（见 IKRepairDataDirectory），再检查一次
OBJC_EXTERN BOOL IKEnsureTemporaryDirectoryWritable(void);
// 一行诊断：临时目录是否存在、属主、权限、当前进程能否写（真的建一个探测文件试），第一层里有几项不归当前用户，
// TMPDIR 环境变量是否和它一致，以及数据目录 /var/mobile/Library/IslandKit 能否写。路径里的容器 UUID 换成 <uuid>
OBJC_EXTERN NSString *IKAppStorageDiagnostic(void);

NS_ASSUME_NONNULL_END
