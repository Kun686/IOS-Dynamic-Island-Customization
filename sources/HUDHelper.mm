//
//  HUDHelper.mm
//  TrollSpeed
//
//  Created by Lessica on 2024/1/24.
//

#import <spawn.h>
#import <notify.h>
#import <fts.h>
#import <dirent.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <mach-o/dyld.h>

#import "HUDHelper.h"
#import "IKPrefs.h"
#import "NSUserDefaults+Private.h"

extern "C" char **environ;

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern "C" int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
extern "C" int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
extern "C" int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);

BOOL IsHUDEnabled(void)
{
    static char *executablePath = NULL;
    uint32_t executablePathSize = 0;
    _NSGetExecutablePath(NULL, &executablePathSize);
    executablePath = (char *)calloc(1, executablePathSize);
    _NSGetExecutablePath(executablePath, &executablePathSize);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

#if !TARGET_OS_SIMULATOR
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
#endif

    int rc;
    pid_t task_pid;
    const char *args[] = { executablePath, "-check", NULL };
    rc = posix_spawn(&task_pid, executablePath, NULL, &attr, (char **)args, environ);
    if (rc != 0) {
        log_debug(OS_LOG_DEFAULT, "posix_spawn error %s", strerror(rc));
    }

    posix_spawnattr_destroy(&attr);

    if (rc != 0) {
        return NO;
    }

    log_debug(OS_LOG_DEFAULT, "spawned %{public}s -check pid = %{public}d", executablePath, task_pid);
    
    int status;
    do {
        if (waitpid(task_pid, &status, 0) != -1)
        {
            log_debug(OS_LOG_DEFAULT, "child status %d", WEXITSTATUS(status));
        }
    } while (!WIFEXITED(status) && !WIFSIGNALED(status));

    return WEXITSTATUS(status) != 0;
}

#define LAUNCH_DAEMON_PATH JBROOT_PATH_CSTRING("/Library/LaunchDaemons/ch.xxtou.hudservices.plist")

void SetHUDEnabled(BOOL isEnabled)
{
    notify_post(NOTIFY_DISMISSAL_HUD);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

#if !TARGET_OS_SIMULATOR
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
#endif

    if (access(LAUNCH_DAEMON_PATH, F_OK) == 0)
    {
        if (!isEnabled) {
            [NSThread sleepForTimeInterval:FADE_OUT_DURATION];
        }

        int rc;
        pid_t task_pid;
        static const char *executablePath = JBROOT_PATH_CSTRING("/usr/bin/launchctl");
        const char *args[] = { executablePath, isEnabled ? "load" : "unload", LAUNCH_DAEMON_PATH, NULL };
        rc = posix_spawn(&task_pid, executablePath, NULL, &attr, (char **)args, environ);
        if (rc != 0) {
            log_debug(OS_LOG_DEFAULT, "posix_spawn error %s", strerror(rc));
        }

        posix_spawnattr_destroy(&attr);

        if (rc != 0) {
            return;
        }

        log_debug(OS_LOG_DEFAULT, "spawned %{public}s -exit pid = %{public}d", executablePath, task_pid);

        int status;
        do {
            if (waitpid(task_pid, &status, 0) != -1)
            {
                log_debug(OS_LOG_DEFAULT, "child status %d", WEXITSTATUS(status));
            }
        } while (!WIFEXITED(status) && !WIFSIGNALED(status));

        return;
    }

    static char *executablePath = NULL;
    uint32_t executablePathSize = 0;
    _NSGetExecutablePath(NULL, &executablePathSize);
    executablePath = (char *)calloc(1, executablePathSize);
    _NSGetExecutablePath(executablePath, &executablePathSize);

    if (isEnabled)
    {
        posix_spawnattr_setpgroup(&attr, 0);
        posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);

        int rc;
        pid_t task_pid;
        const char *args[] = { executablePath, "-hud", NULL };
        rc = posix_spawn(&task_pid, executablePath, NULL, &attr, (char **)args, environ);
        if (rc != 0) {
            log_debug(OS_LOG_DEFAULT, "posix_spawn error %s", strerror(rc));
        }

        posix_spawnattr_destroy(&attr);

        if (rc != 0) {
            return;
        }

        log_debug(OS_LOG_DEFAULT, "spawned %{public}s -hud pid = %{public}d", executablePath, task_pid);

        int unused;
        waitpid(task_pid, &unused, WNOHANG);
    }
    else
    {
        [NSThread sleepForTimeInterval:FADE_OUT_DURATION];

        int rc;
        pid_t task_pid;
        const char *args[] = { executablePath, "-exit", NULL };
        rc = posix_spawn(&task_pid, executablePath, NULL, &attr, (char **)args, environ);
        if (rc != 0) {
            log_debug(OS_LOG_DEFAULT, "posix_spawn error %s", strerror(rc));
        }

        posix_spawnattr_destroy(&attr);

        if (rc != 0) {
            return;
        }

        log_debug(OS_LOG_DEFAULT, "spawned %{public}s -exit pid = %{public}d", executablePath, task_pid);

        int status;
        do {
            if (waitpid(task_pid, &status, 0) != -1)
            {
                log_debug(OS_LOG_DEFAULT, "child status %d", WEXITSTATUS(status));
            }
        } while (!WIFEXITED(status) && !WIFSIGNALED(status));
    }
}

#if DEBUG
void SimulateMemoryPressure(void)
{
    static NSString *nsExecutablePath = nil;
    static const char *executablePath = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *mainBundle = [NSBundle mainBundle];
        nsExecutablePath = [mainBundle pathForResource:@"memory_pressure" ofType:nil];
        if (nsExecutablePath) {
            executablePath = [nsExecutablePath UTF8String];
        }
    });

    if (!executablePath) {
        return;
    }

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

#if !TARGET_OS_SIMULATOR
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
#endif

    pid_t task_pid;
    const char *args[] = { executablePath, "-l", "critical", NULL };
    posix_spawn(&task_pid, executablePath, NULL, &attr, (char **)args, environ);
    posix_spawnattr_destroy(&attr);

    log_debug(OS_LOG_DEFAULT, "spawned %{public}s -l critical pid = %{public}d", executablePath, task_pid);
}
#endif

NSUserDefaults *GetStandardUserDefaults(void)
{
    static NSUserDefaults *_userDefaults = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *containerPath = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject] stringByDeletingLastPathComponent];
        NSURL *containerURL = [NSURL fileURLWithPath:containerPath];
        _userDefaults = [[NSUserDefaults alloc] _initWithSuiteName:nil container:containerURL];
        [_userDefaults registerDefaults:@{
            HUDUserDefaultsKeyUsesCustomOffset: @NO,
            HUDUserDefaultsKeyRealCustomOffsetX: @0,
            HUDUserDefaultsKeyRealCustomOffsetY: @0,
            HUDUserDefaultsKeyUsesCustomFontSize: @NO,
            HUDUserDefaultsKeyRealCustomFontSize: @9,
        }];
    });
    return _userDefaults;
}

#pragma mark - IslandKit 数据目录

// 设置 App 会往这几个子目录写东西：备用头像、手动绑定的歌词时间轴
static NSArray<NSString *> *IKDataSubdirectories(void)
{
    return @[ @"WeChatAvatars", @"Timelines" ];
}

static const uid_t IKMobileUID = 501;
static const gid_t IKMobileGID = 501;

static void IKRepairInheritedTemporaryDirectory(void);

// 数据目录这一棵树的修复（原 IKRepairDataDirectory 的全部内容）
static BOOL IKRepairDataDirectoryTree(void)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = IKDataDir;
    struct stat st;
    // 数据目录本身是符号链接或普通文件时不动它：下面的 chown 只能落在这个目录里面
    if (lstat(root.fileSystemRepresentation, &st) == 0 && !S_ISDIR(st.st_mode)) {
        return NO;
    }
    BOOL ok = YES;
    for (NSString *name in IKDataSubdirectories()) {
        NSString *sub = [root stringByAppendingPathComponent:name];
        if (lstat(sub.fileSystemRepresentation, &st) == 0 && !S_ISDIR(st.st_mode)) { ok = NO; continue; }
        if (![fm createDirectoryAtPath:sub withIntermediateDirectories:YES attributes:nil error:nil]) ok = NO;
    }
    if (getuid() != 0) {
        return ok;
    }

    // 只改目录的属主：设置 App 写文件都是“写临时文件再改名”，删改文件也只需要目录可写，
    // 用不着动文件本身。不碰文件还能避免一个坑：普通用户可以在这里放一个指向系统文件的硬链接，
    // root 去 chown 它就等于把那个系统文件交给了 mobile。
    // FTS_PHYSICAL：不跟随符号链接；FTS_XDEV：不跨文件系统；改权限也不跟随符号链接
    char *paths[] = { (char *)root.fileSystemRepresentation, NULL };
    FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
    if (!fts) {
        return NO;
    }
    FTSENT *entry;
    while ((entry = fts_read(fts)) != NULL) {
        switch (entry->fts_info) {
            case FTS_D:
                if (lchown(entry->fts_accpath, IKMobileUID, IKMobileGID) != 0) ok = NO;
                if (fchmodat(AT_FDCWD, entry->fts_accpath, (entry->fts_statp->st_mode & 07777) | 0755,
                             AT_SYMLINK_NOFOLLOW) != 0) ok = NO;
                break;
            case FTS_DNR:
            case FTS_ERR:
            case FTS_NS:
                ok = NO;
                break;
            default:
                break;
        }
    }
    fts_close(fts);
    return ok;
}

BOOL IKRepairDataDirectory(void)
{
    BOOL ok = IKRepairDataDirectoryTree();
    // 顺带把本 App 的临时目录交还给 mobile。结果不计入返回值：返回值仍只表示数据目录
    //（悬浮进程启动时把它记进 island.log 的 dataDirectory repaired=…）
    if (getuid() == 0) {
        IKRepairInheritedTemporaryDirectory();
    }
    return ok;
}

// 用当前用户的身份检查：数据目录和子目录都能写。缺的子目录在父目录可写时顺手建出来
static BOOL IKDataDirectoryWritable(void)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = IKDataDir;
    if (access(root.fileSystemRepresentation, F_OK) != 0 &&
        ![fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil]) {
        return NO;
    }
    if (access(root.fileSystemRepresentation, W_OK | X_OK) != 0) {
        return NO;
    }
    for (NSString *name in IKDataSubdirectories()) {
        NSString *sub = [root stringByAppendingPathComponent:name];
        if (access(sub.fileSystemRepresentation, F_OK) != 0) {
            if (![fm createDirectoryAtPath:sub withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
        } else if (access(sub.fileSystemRepresentation, W_OK | X_OK) != 0) {
            return NO;
        }
    }
    return YES;
}

// 以 root 身份启动自身的 -ik-data 并等它结束（它调用 IKRepairDataDirectory：修数据目录，再修本 App 的临时目录）。
// 子进程继承本进程的环境变量，所以拿得到本 App 的 TMPDIR。模拟器里什么也不做
static void IKRunRootDataRepair(void)
{
#if !TARGET_OS_SIMULATOR
    uint32_t executablePathSize = 0;
    _NSGetExecutablePath(NULL, &executablePathSize);
    char *executablePath = (char *)calloc(1, executablePathSize);
    if (!executablePath || _NSGetExecutablePath(executablePath, &executablePathSize) != 0) {
        free(executablePath);
        return;
    }

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);

    pid_t task_pid = 0;
    const char *args[] = { executablePath, "-ik-data", NULL };
    int rc = posix_spawn(&task_pid, executablePath, NULL, &attr, (char **)args, environ);
    posix_spawnattr_destroy(&attr);
    free(executablePath);
    if (rc != 0) {
        log_debug(OS_LOG_DEFAULT, "posix_spawn -ik-data error %s", strerror(rc));
        return;
    }

    int status = 0;
    pid_t waited;
    do {
        waited = waitpid(task_pid, &status, 0);
    } while (waited == -1 && errno == EINTR);
    log_debug(OS_LOG_DEFAULT, "-ik-data finished waited=%d status=%d", waited, status);
#endif
}

BOOL IKEnsureDataDirectoryWritable(void)
{
    if (IKDataDirectoryWritable()) {
        return YES;
    }
    IKRunRootDataRepair();
    return IKDataDirectoryWritable();
}

#pragma mark - 本 App 的临时目录

// 悬浮进程（root）继承了设置 App 的 TMPDIR，它在里面建的东西归 root。临时目录本身变成 root 的之后，
// 系统的文件导出面板（“没有储存到 tmp 的权限”）、相册选图（要先把照片拷进 tmp）都会失败

// 认 TMPDIR 指向的本 App 数据容器里的 tmp。只认这两种写法（末尾可以带斜杠）：
//   /private/var/mobile/Containers/Data/Application/<容器 UUID>/tmp
//   /var/mobile/Containers/Data/Application/<容器 UUID>/tmp
// 有空段（“//”）、“.”、“..”，多一层或少一层，容器名不是 UUID，都不认。返回不带末尾斜杠的路径，不认时返回 nil
static NSString *IKContainerTemporaryDirectory(const char *raw)
{
    if (!raw || raw[0] != '/') return nil;
    NSString *path = [NSString stringWithUTF8String:raw];
    if (!path) return nil;
    NSMutableArray<NSString *> *parts = [[path componentsSeparatedByString:@"/"] mutableCopy];
    [parts removeObjectAtIndex:0];   // 开头的“/”分出来的空段
    while (parts.count && parts.lastObject.length == 0) [parts removeLastObject];
    for (NSString *part in parts) {
        if (part.length == 0 || [part isEqualToString:@"."] || [part isEqualToString:@".."]) return nil;
    }
    NSArray<NSString *> *prefix = @[ @"var", @"mobile", @"Containers", @"Data", @"Application" ];
    NSUInteger skip = (parts.count && [parts[0] isEqualToString:@"private"]) ? 1 : 0;
    if (parts.count != skip + prefix.count + 2) return nil;
    if (![[parts subarrayWithRange:NSMakeRange(skip, prefix.count)] isEqualToArray:prefix]) return nil;
    if (![[NSUUID alloc] initWithUUIDString:parts[skip + prefix.count]]) return nil;
    if (![parts.lastObject isEqualToString:@"tmp"]) return nil;
    return [@"/" stringByAppendingString:[parts componentsJoinedByString:@"/"]];
}

// root 侧：把 TMPDIR 指向的本 App 临时目录交还给 mobile。只改这一个目录本身（属主改成 501:501，
// 补上属主的 rwx），不递归、不碰里面的文件、不跟随符号链接。它的上一级（容器目录）和它自己都必须是真目录
static void IKRepairInheritedTemporaryDirectory(void)
{
    const char *raw = getenv("TMPDIR");
    if (!raw || !raw[0]) {
        return;   // 没有继承到 TMPDIR（例如由 launchd 直接启动），没有要修的
    }
    NSString *tmp = IKContainerTemporaryDirectory(raw);
    if (!tmp) {
        log_debug(OS_LOG_DEFAULT, "tmp repair skipped: TMPDIR is not an app container tmp");
        return;
    }
    struct stat parent, st;
    if (lstat(tmp.stringByDeletingLastPathComponent.fileSystemRepresentation, &parent) != 0 || !S_ISDIR(parent.st_mode)) {
        log_debug(OS_LOG_DEFAULT, "tmp repair skipped: container is not a real directory");
        return;
    }
    const char *path = tmp.fileSystemRepresentation;
    if (lstat(path, &st) != 0 || !S_ISDIR(st.st_mode)) {
        // 不存在时交给设置 App 自己建（容器归 mobile）；符号链接、普通文件一律不动
        log_debug(OS_LOG_DEFAULT, "tmp repair skipped: tmp missing or not a real directory");
        return;
    }
    if ((st.st_uid != IKMobileUID || st.st_gid != IKMobileGID) && lchown(path, IKMobileUID, IKMobileGID) != 0) {
        log_debug(OS_LOG_DEFAULT, "tmp repair lchown failed: %{public}s", strerror(errno));
    }
    mode_t mode = st.st_mode & 07777;
    if ((mode & S_IRWXU) != S_IRWXU && fchmodat(AT_FDCWD, path, mode | S_IRWXU, AT_SYMLINK_NOFOLLOW) != 0) {
        log_debug(OS_LOG_DEFAULT, "tmp repair fchmodat failed: %{public}s", strerror(errno));
    }
}

// 去掉末尾的斜杠（根目录除外）
static NSString *IKTrimmedDirectoryPath(NSString *path)
{
    while (path.length > 1 && [path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
    return path;
}

// 当前进程的临时目录（NSTemporaryDirectory），不带末尾斜杠
static NSString *IKCurrentTemporaryDirectory(void)
{
    return IKTrimmedDirectoryPath(NSTemporaryDirectory() ?: @"");
}

// 真的在 dir 里建一个探测文件再删掉，看当前进程能不能写（access() 看不到 ACL 之类的限制）。能写返回 0，否则返回 errno
static int IKProbeWritable(NSString *dir)
{
    if (!dir.length) return ENOENT;
    char *name = strdup([dir stringByAppendingPathComponent:@".ik-write-probe-XXXXXX"].fileSystemRepresentation);
    if (!name) return ENOMEM;
    int fd = mkstemp(name);
    int err = fd < 0 ? errno : 0;
    if (fd >= 0) {
        close(fd);
        unlink(name);
    }
    free(name);
    return err;
}

// 设置 App 侧：临时目录存在（不存在就自己建）、是目录、能写
static BOOL IKTemporaryDirectoryWritable(void)
{
    NSString *tmp = IKCurrentTemporaryDirectory();
    if (!tmp.length) return NO;
    struct stat st;
    if (stat(tmp.fileSystemRepresentation, &st) != 0) {
        if (errno != ENOENT || mkdir(tmp.fileSystemRepresentation, 0755) != 0) return NO;
    } else if (!S_ISDIR(st.st_mode)) {
        return NO;
    }
    return IKProbeWritable(tmp) == 0;
}

BOOL IKEnsureTemporaryDirectoryWritable(void)
{
    if (IKTemporaryDirectoryWritable()) {
        return YES;
    }
    IKRunRootDataRepair();
    return IKTemporaryDirectoryWritable();
}

// 路径里的容器 UUID 换成 <uuid>，诊断里不带设备上的具体容器名
static NSString *IKRedactContainerIDs(NSString *path)
{
    static NSRegularExpression *uuid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        uuid = [NSRegularExpression regularExpressionWithPattern:
                @"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" options:0 error:nil];
    });
    if (!path.length) return @"（空）";
    return [uuid stringByReplacingMatchesInString:path options:0 range:NSMakeRange(0, path.length) withTemplate:@"<uuid>"];
}

// 一个目录的状态：存在与否、属主、权限、当前进程能否写。countForeign 时再数一下第一层里属主不是当前用户的项
static NSString *IKDescribeDirectory(NSString *path, BOOL countForeign)
{
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) {
        return errno == ENOENT ? @"不存在" : [NSString stringWithFormat:@"无法查看（%s）", strerror(errno)];
    }
    if (S_ISLNK(st.st_mode)) return @"是符号链接";
    if (!S_ISDIR(st.st_mode)) return @"不是目录";
    int err = IKProbeWritable(path);
    NSMutableString *text = [NSMutableString stringWithFormat:@"存在，属主 uid %u gid %u 权限 %03o，当前进程%@",
                             st.st_uid, st.st_gid, st.st_mode & 0777,
                             err ? [NSString stringWithFormat:@"不可写（%s）", strerror(err)] : @"可写"];
    if (countForeign) {
        DIR *dir = opendir(path.fileSystemRepresentation);
        if (dir) {
            unsigned total = 0, foreign = 0;
            struct dirent *entry;
            while ((entry = readdir(dir)) != NULL && total < 1000) {
                if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
                struct stat child;
                total++;
                if (fstatat(dirfd(dir), entry->d_name, &child, AT_SYMLINK_NOFOLLOW) == 0 && child.st_uid != getuid()) foreign++;
            }
            closedir(dir);
            [text appendFormat:@"，里面 %u 项中 %u 项属主不是 uid %u", total, foreign, getuid()];
        } else {
            [text appendFormat:@"，列不出内容（%s）", strerror(errno)];
        }
    }
    return text;
}

NSString *IKAppStorageDiagnostic(void)
{
    NSString *tmp = IKCurrentTemporaryDirectory();
    const char *env = getenv("TMPDIR");
    NSString *envText = !env ? @"未设置"
        : [IKTrimmedDirectoryPath(@(env)) isEqualToString:tmp] ? @"与之相同" : IKRedactContainerIDs(@(env));
    NSMutableString *data = [IKDescribeDirectory(IKDataDir, NO) mutableCopy];
    for (NSString *name in IKDataSubdirectories()) {
        NSString *sub = [IKDataDir stringByAppendingPathComponent:name];
        if (access(sub.fileSystemRepresentation, F_OK) == 0 && access(sub.fileSystemRepresentation, W_OK | X_OK) != 0) {
            [data appendFormat:@"，%@ 不可写", name];
        }
    }
    return [NSString stringWithFormat:@"存储诊断（uid %u）：临时目录 %@ %@；TMPDIR %@；数据目录 %@ %@",
            getuid(), IKRedactContainerIDs(tmp), IKDescribeDirectory(tmp, YES), envText, IKDataDir, data];
}
