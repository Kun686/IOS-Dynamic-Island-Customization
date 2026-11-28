//
//  HUDHelper.mm
//  TrollSpeed
//
//  Created by Lessica on 2024/1/24.
//

#import <spawn.h>
#import <notify.h>
#import <fts.h>
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

BOOL IKRepairDataDirectory(void)
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

BOOL IKEnsureDataDirectoryWritable(void)
{
    if (IKDataDirectoryWritable()) {
        return YES;
    }

#if !TARGET_OS_SIMULATOR
    uint32_t executablePathSize = 0;
    _NSGetExecutablePath(NULL, &executablePathSize);
    char *executablePath = (char *)calloc(1, executablePathSize);
    if (!executablePath || _NSGetExecutablePath(executablePath, &executablePathSize) != 0) {
        free(executablePath);
        return NO;
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
        return NO;
    }

    int status = 0;
    pid_t waited;
    do {
        waited = waitpid(task_pid, &status, 0);
    } while (waited == -1 && errno == EINTR);
    log_debug(OS_LOG_DEFAULT, "-ik-data finished waited=%d status=%d", waited, status);
#endif

    return IKDataDirectoryWritable();
}
