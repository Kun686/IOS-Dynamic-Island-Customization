#import "IKContainerScan.h"
#import "IKLyricEvidence.h"
#import "IKPlaybackDiagnostic.h"
#import <dirent.h>
#import <errno.h>
#import <fcntl.h>
#import <sys/stat.h>

static double IKScanUptime(void) { return NSProcessInfo.processInfo.systemUptime; }

IKScanLimits IKDefaultScanLimits(void) {
    return (IKScanLimits){.depth = 10, .entries = 60000, .rows = 240, .headers = 600, .seconds = 6, .clock = NULL};
}

// One report row: files in one directory that share a redacted name.
static NSMutableDictionary *IKScanGroup(NSString *directory, NSString *file, NSString *ext) {
    return [@{@"dir": directory, @"file": file, @"ext": ext, @"count": @0, @"sampled": @0,
              @"min": @(ULLONG_MAX), @"max": @0ULL, @"headers": [NSMutableSet set]} mutableCopy];
}

static BOOL IKScanLyricRow(NSDictionary *group) {
    return [@[@"lrc", @"qrc", @"yrc", @"krc"] containsObject:group[@"ext"]] || [group[@"headers"] containsObject:@"timed-text"];
}

static NSData *IKScanName(const char *name) { return [NSData dataWithBytes:name length:strlen(name) + 1]; }

// Opens a directory below `root` one level at a time. Every level refuses a symbolic link, so a directory
// replaced by a link while the scan runs cannot lead outside the container.
static int IKScanOpen(int root, NSArray<NSData *> *components) {
    int current = root;
    for (NSData *component in components) {
        int next = openat(current, component.bytes, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        int error = errno;
        if (current != root) close(current);
        if (next < 0) { errno = error; return -1; }
        current = next;
    }
    return current == root ? -1 : current;
}

NSString *IKContainerScanReport(NSURL *container, NSString *bundle, IKScanLimits limits) {
    if (!container.isFileURL || ![bundle isKindOfClass:NSString.class]) return nil;
    double (*clock)(void) = limits.clock ?: IKScanUptime;
    double started = clock();
    int root = open(container.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (root < 0) return nil;

    // Directories below a keyword-named directory are read before the rest, so a large unrelated cache cannot use up the limits first.
    // Each queued directory is (raw name components, redacted path, level).
    NSMutableArray<NSArray *> *hot = [NSMutableArray array], *cold = [NSMutableArray array];
    for (NSString *name in @[@"Documents", @"Library", @"tmp"]) [cold addObject:@[@[IKScanName(name.UTF8String)], name, @1]];
    NSUInteger hotHead = 0, coldHead = 0;
    NSUInteger entries = 0, directories = 0, matched = 0, symlinks = 0, unreadable = 0, tooDeep = 0, headerReads = 0, unlisted = 0;
    BOOL entryLimit = NO, timeLimit = NO, headerLimit = NO, rowLimit = NO;
    NSMutableDictionary<NSString *, NSMutableDictionary *> *groups = [NSMutableDictionary dictionary];
    NSMutableOrderedSet<NSString *> *keywordDirectories = [NSMutableOrderedSet orderedSet];

    while (!entryLimit && !timeLimit && (hotHead < hot.count || coldHead < cold.count)) {
        BOOL inside = hotHead < hot.count;
        NSArray *directory = inside ? hot[hotHead++] : cold[coldHead++];
        NSArray<NSData *> *components = directory[0];
        NSString *shown = directory[1];
        NSUInteger level = [directory[2] unsignedIntegerValue];
        if (clock() - started > limits.seconds) { timeLimit = YES; break; }
        int fd = IKScanOpen(root, components);
        DIR *stream = fd < 0 ? NULL : fdopendir(fd);
        if (!stream) {
            if (level > 1 || errno != ENOENT) unreadable++;
            if (fd >= 0) close(fd);
            continue;
        }
        directories++;
        struct dirent *entry;
        while ((entry = readdir(stream))) {
            if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
            if (entries >= limits.entries) { entryLimit = YES; break; }
            entries++;
            if ((entries & 63) == 0 && clock() - started > limits.seconds) { timeLimit = YES; break; }
            unsigned char type = entry->d_type;
            if (type == DT_UNKNOWN) {
                struct stat info;
                if (fstatat(fd, entry->d_name, &info, AT_SYMLINK_NOFOLLOW)) { unreadable++; continue; }
                type = S_ISDIR(info.st_mode) ? DT_DIR : S_ISREG(info.st_mode) ? DT_REG : S_ISLNK(info.st_mode) ? DT_LNK : DT_UNKNOWN;
            }
            if (type == DT_LNK) { symlinks++; continue; }
            if (type != DT_DIR && type != DT_REG) continue;
            NSString *name = [[NSString alloc] initWithBytes:entry->d_name length:strlen(entry->d_name) encoding:NSUTF8StringEncoding];
            BOOL keyword = IKEvidenceKeyword(name);
            if (type == DT_DIR) {
                if (!name.length) { unreadable++; continue; }
                if (level == 1 && [shown isEqual:@"Library"] && [name isEqual:@"IslandKit"]) continue;  // our own output
                NSString *childShown = [NSString stringWithFormat:@"%@/%@", shown, IKRedactPathSegment(name)];
                if (keyword) [keywordDirectories addObject:childShown];
                if (level + 1 > limits.depth) { tooDeep++; continue; }
                NSArray *child = [components arrayByAddingObject:IKScanName(entry->d_name)];
                [(inside || keyword ? hot : cold) addObject:@[child, childShown, @(level + 1)]];
                continue;
            }
            if (!inside && !keyword) continue;
            matched++;
            NSString *ext = @"";
            NSString *file = name.length ? IKRedactFileName(name, &ext) : @"<text>";
            NSString *key = [NSString stringWithFormat:@"%@/%@", shown, file];
            NSMutableDictionary *group = groups[key];
            // Collect more names than rows so the lyric-looking ones can be kept when the report is cut.
            if (!group && groups.count >= limits.rows * 4) { rowLimit = YES; unlisted++; continue; }
            BOOL sample = (!group || [group[@"sampled"] unsignedIntegerValue] < 8) && name.length;
            if (sample && headerReads >= limits.headers) { headerLimit = YES; sample = NO; }
            unsigned long long bytes = 0;
            NSString *header = nil;
            if (sample) {
                // Type, size and header come from one descriptor opened inside this directory.
                headerReads++;
                NSDictionary *shape = IKLyricShapeAt(fd, entry->d_name, ext);
                if (!shape) { unreadable++; continue; }
                bytes = [shape[@"bytes"] unsignedLongLongValue];
                header = [shape[@"header"] isKindOfClass:NSString.class] ? shape[@"header"] : @"unreadable";
            } else {
                struct stat info;
                if (fstatat(fd, entry->d_name, &info, AT_SYMLINK_NOFOLLOW) || !S_ISREG(info.st_mode)) { unreadable++; continue; }
                bytes = info.st_size > 0 ? (unsigned long long)info.st_size : 0;
            }
            if (!group) group = groups[key] = IKScanGroup(shown, file, ext);
            group[@"count"] = @([group[@"count"] unsignedIntegerValue] + 1);
            group[@"min"] = @(MIN([group[@"min"] unsignedLongLongValue], bytes));
            group[@"max"] = @(MAX([group[@"max"] unsignedLongLongValue], bytes));
            if (header) {
                group[@"sampled"] = @([group[@"sampled"] unsignedIntegerValue] + 1);
                [group[@"headers"] addObject:header];
            }
        }
        closedir(stream);
    }
    close(root);
    BOOL unfinished = hotHead < hot.count || coldHead < cold.count;

    // Keep rows that look like lyric files when there are too many, then print in path order.
    NSArray<NSString *> *order = [groups.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        BOOL x = IKScanLyricRow(groups[a]), y = IKScanLyricRow(groups[b]);
        return x == y ? [a compare:b] : (x ? NSOrderedAscending : NSOrderedDescending);
    }];
    NSUInteger directoryRows = MIN(keywordDirectories.count, limits.rows / 4);
    NSUInteger fileRows = MIN(order.count, limits.rows - directoryRows);
    if (fileRows < order.count || directoryRows < keywordDirectories.count) rowLimit = YES;
    for (NSUInteger i = fileRows; i < order.count; i++) unlisted += [groups[order[i]][@"count"] unsignedIntegerValue];
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < directoryRows; i++) [rows addObject:[NSString stringWithFormat:@"  %@/ directory", keywordDirectories[i]]];
    for (NSString *key in [order subarrayWithRange:NSMakeRange(0, fileRows)]) {
        NSDictionary *group = groups[key];
        NSUInteger count = [group[@"count"] unsignedIntegerValue], sampled = [group[@"sampled"] unsignedIntegerValue];
        NSArray *headers = [[group[@"headers"] allObjects] sortedArrayUsingSelector:@selector(compare:)];
        unsigned long long low = [group[@"min"] unsignedLongLongValue], high = [group[@"max"] unsignedLongLongValue];
        NSString *bytes = low == high ? [NSString stringWithFormat:@"%llu", low] : [NSString stringWithFormat:@"%llu..%llu", low, high];
        [rows addObject:[NSString stringWithFormat:@"  %@/%@ ext=%@ files=%lu bytes=%@ header=%@ sampled=%lu", group[@"dir"], group[@"file"],
            [group[@"ext"] length] ? group[@"ext"] : @"-", (unsigned long)count, bytes,
            headers.count ? [headers componentsJoinedByString:@"+"] : @"unsampled", (unsigned long)sampled]];
    }
    [rows sortUsingSelector:@selector(compare:)];

    NSMutableArray<NSString *> *limited = [NSMutableArray array];
    if (entryLimit) [limited addObject:@"entries"];
    if (timeLimit) [limited addObject:@"time"];
    if (rowLimit) [limited addObject:@"rows"];
    if (headerLimit) [limited addObject:@"headers"];
    if (tooDeep) [limited addObject:@"depth"];
    // complete=1 only when every directory was read and every matching file is listed with a sampled header budget left.
    BOOL complete = !unfinished && !limited.count;
    NSString *summary = [NSString stringWithFormat:
        @"container scan app=%@ directories=%lu entries=%lu matched=%lu rows=%lu unlisted=%lu symlinks=%lu unreadable=%lu tooDeep=%lu complete=%d limited=%@ seconds=%.1f",
        bundle, (unsigned long)directories, (unsigned long)entries, (unsigned long)matched, (unsigned long)rows.count,
        (unsigned long)unlisted, (unsigned long)symlinks, (unsigned long)unreadable, (unsigned long)tooDeep,
        complete, limited.count ? [limited componentsJoinedByString:@"+"] : @"none", clock() - started];
    [rows insertObject:summary atIndex:0];
    return [rows componentsJoinedByString:@"\n"];
}
