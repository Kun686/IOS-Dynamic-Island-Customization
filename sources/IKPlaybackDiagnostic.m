#import "IKPlaybackDiagnostic.h"
#import <errno.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

BOOL IKMetadataSymbol(id key) {
    if (![key isKindOfClass:NSString.class] || ![key length] || [key length] > 96) return NO;
    for (NSUInteger i=0; i<[key length]; i++) {
        unichar c = [key characterAtIndex:i];
        BOOL letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
        if (!letter && (!i || ((c < '0' || c > '9') && c != '.' && c != '-'))) return NO;
    }
    return YES;
}

BOOL IKLyricSymbol(NSString *key) {
    NSString *lower = key.lowercaseString;
    return [lower containsString:@"lyric"] || [lower containsString:@"lrc"] ||
           [lower containsString:@"qrc"] || [lower containsString:@"yrc"] || [lower containsString:@"krc"];
}

static NSString *IKHeaderKind(NSData *sample) {
    if (!sample) return @"unreadable";
    if (!sample.length) return @"empty";
    const uint8_t *bytes = sample.bytes;
    NSString *text = nil;
    if (sample.length >= 2 && ((bytes[0]==0xfe && bytes[1]==0xff) || (bytes[0]==0xff && bytes[1]==0xfe))) {
        text = [[NSString alloc] initWithData:sample encoding:NSUnicodeStringEncoding];
    } else if (sample.length >= 4 && bytes[1]==0 && (bytes[0]=='[' || bytes[0]=='<')) {
        text = [[NSString alloc] initWithData:sample encoding:NSUTF16LittleEndianStringEncoding];
    } else if (sample.length >= 4 && bytes[0]==0 && (bytes[1]=='[' || bytes[1]=='<')) {
        text = [[NSString alloc] initWithData:sample encoding:NSUTF16BigEndianStringEncoding];
    } else {
        for (NSUInteger i=0; i<sample.length; i++)
            if (bytes[i]<32 && bytes[i]!=9 && bytes[i]!=10 && bytes[i]!=13) return @"binary";
        // The prefix may stop in the middle of a UTF-8 or GB18030 character.
        NSStringEncoding gb = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
        for (NSUInteger trim=0; !text && trim<4 && trim<sample.length; trim++) {
            NSData *prefix = trim ? [sample subdataWithRange:NSMakeRange(0,sample.length-trim)] : sample;
            text = [[NSString alloc] initWithData:prefix encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithData:prefix encoding:gb];
        }
    }
    if (!text.length) return @"unknown";
    NSRange timing = [text rangeOfString:@"\\[(?:[0-9]{1,3}:[0-5][0-9]|[0-9]+,[0-9]+\\])" options:NSRegularExpressionSearch];
    return timing.location != NSNotFound ? @"timed-text" : @"text";
}

static NSArray<NSString *> *IKFileExtensions(void) {
    return @[@"lrc",@"qrc",@"yrc",@"krc",@"txt",@"json",@"xml",@"dat",@"bin",@"plist",@"cache",@"other"];
}

NSDictionary *IKLyricShapeAt(int directory, const char *name, NSString *extension) {
    if (!name || !*name) return nil;
    // O_NONBLOCK keeps a FIFO swapped in after the directory listing from blocking the open.
    int file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (file < 0) return nil;
    struct stat info;
    if (fstat(file, &info) || !S_ISREG(info.st_mode)) { close(file); return nil; }
    uint8_t buffer[512];
    size_t total = 0;
    BOOL failed = NO;
    while (total < sizeof(buffer)) {
        ssize_t n = read(file, buffer + total, sizeof(buffer) - total);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) failed = YES;
        if (n <= 0) break;
        total += (size_t)n;
    }
    close(file);
    NSData *sample = failed && !total ? nil : [NSData dataWithBytes:buffer length:total];
    NSString *ext = extension.lowercaseString;
    if (![IKFileExtensions() containsObject:ext ?: @""]) ext = @"other";
    unsigned long long bytes = info.st_size > 0 ? (unsigned long long)info.st_size : 0;
    return @{@"ext":ext, @"bytes":@(bytes), @"header":bytes ? IKHeaderKind(sample) : @"empty"};
}

NSDictionary *IKLyricFileShape(NSURL *url) {
    if (!url.isFileURL) return nil;
    return IKLyricShapeAt(AT_FDCWD, url.fileSystemRepresentation, url.pathExtension);
}

NSString *IKFileShapeSummary(NSDictionary *shape) {
    if (![shape isKindOfClass:NSDictionary.class] || ![IKFileExtensions() containsObject:shape[@"ext"] ?: @""] ||
        ![@[@"unreadable",@"empty",@"binary",@"unknown",@"text",@"timed-text"] containsObject:shape[@"header"] ?: @""] ||
        ![shape[@"bytes"] isKindOfClass:NSNumber.class] || [shape[@"bytes"] longLongValue] < 0) return nil;
    return [NSString stringWithFormat:@"*.%@ bytes=%llu header=%@",shape[@"ext"],[shape[@"bytes"] unsignedLongLongValue],shape[@"header"]];
}

static NSString *IKReportLine(NSDictionary *s, NSString *bundle) {
    if (![s isKindOfClass:NSDictionary.class] || ![s[@"schema"] isEqual:@1] ||
        ![s[@"bundleID"] isKindOfClass:NSString.class] || [s[@"bundleID"] caseInsensitiveCompare:bundle]!=NSOrderedSame) return nil;
    NSDictionary *fields = s[@"fields"], *extra = s[@"customFields"], *sidecars = s[@"sidecarShapes"];
    if (![fields isKindOfClass:NSDictionary.class]) return nil;
    if (extra && (![extra isKindOfClass:NSDictionary.class] || extra.count > 40)) return nil;
    if (sidecars && ![sidecars isKindOfClass:NSDictionary.class]) return nil;
    NSArray *types = @[@"text",@"number",@"url",@"artwork",@"dictionary",@"array",@"data",@"other"];
    NSMutableArray *keys = [NSMutableArray array], *custom = [NSMutableArray array], *files = [NSMutableArray array];
    for (NSString *key in IKPlaybackFieldNames())
        if ([types containsObject:fields[key] ?: @""]) [keys addObject:[NSString stringWithFormat:@"%@/%@",key,fields[key]]];
    for (id key in extra)
        if (IKMetadataSymbol(key) && [types containsObject:extra[key]]) [custom addObject:[NSString stringWithFormat:@"%@/%@",key,extra[key]]];
    NSDictionary *nested = s[@"nestedFields"];
    if (nested && (![nested isKindOfClass:NSDictionary.class] || nested.count>8)) return nil;
    NSMutableArray *children = [NSMutableArray array];
    for (id key in nested) {
        if (IKMetadataSymbol(key) && [types containsObject:nested[key]]) [children addObject:[NSString stringWithFormat:@"%@/%@",key,nested[key]]];
    }
    [children sortUsingSelector:@selector(compare:)];
    [custom sortUsingSelector:@selector(compare:)];
    NSDictionary *objects = s[@"lyricObjects"];
    if (objects && (![objects isKindOfClass:NSDictionary.class] || objects.count > 8)) return nil;
    NSMutableArray *typesUsed = [NSMutableArray array];
    for (id key in objects) {
        NSDictionary *shape = objects[key];
        if (!IKMetadataSymbol(key) || ![shape isKindOfClass:NSDictionary.class] || !IKMetadataSymbol(shape[@"type"])) continue;
        [typesUsed addObject:[NSString stringWithFormat:@"%@%@/%@",key,[shape[@"array"] isEqual:@YES] ? @"[]" : @"",shape[@"type"]]];
    }
    [typesUsed sortUsingSelector:@selector(compare:)];
    for (NSString *ext in @[@"lrc",@"qrc",@"yrc",@"krc"]) {
        NSString *file = IKFileShapeSummary(sidecars[ext]);
        if (file) [files addObject:[@"<media>/" stringByAppendingString:file]];
        else if ([s[ext] isEqual:@YES]) [files addObject:ext]; // 0.6.3 snapshot
    }
    if (![@[@"absent",@"file",@"remote",@"other"] containsObject:s[@"asset"] ?: @""]) return nil;
    for (NSString *key in @[@"unknown",@"accessEvents",@"jumpEvents"])
        if (![s[key] isKindOfClass:NSNumber.class] || [s[key] integerValue]<0 || [s[key] integerValue]>999) return nil;
    NSDictionary *result = s[@"result"];
    NSString *evidence = @"observedOnly";
    if ([result isKindOfClass:NSDictionary.class]) {
        if (![@[@"metadata",@"publishedField",@"sidecar",@"audio",@"timedAudio",@"idle",@"clock",@"unwritten"] containsObject:result[@"source"] ?: @""] ||
            ![result[@"lines"] isKindOfClass:NSNumber.class] || [result[@"lines"] integerValue]<0 || [result[@"lines"] integerValue]>4000) return nil;
        NSString *name = IKMetadataSymbol(result[@"key"]) ? result[@"key"] : @"-";
        evidence = [NSString stringWithFormat:@"%@ key=%@ lines=%ld",result[@"source"],name,(long)[result[@"lines"] integerValue]];
    }
    NSUInteger undisclosed = MAX([s[@"unknown"] integerValue]-(NSInteger)custom.count,0);
    return [NSString stringWithFormat:@"player diagnostic app=%@ version=%@ fields=[%@] custom=[%@] nested=[%@] objects=[%@] otherKeys=%ld omitted=%lu asset=%@ sidecars=[%@] avAccess=%ld avJump=%ld timeline=%@",
            bundle,IKPlayerVersion(s[@"version"]),[keys componentsJoinedByString:@","],[custom componentsJoinedByString:@","],[children componentsJoinedByString:@","],
            [typesUsed componentsJoinedByString:@","],(long)[s[@"unknown"] integerValue],(unsigned long)undisclosed,s[@"asset"],[files componentsJoinedByString:@","],
            (long)[s[@"accessEvents"] integerValue],(long)[s[@"jumpEvents"] integerValue],evidence];
}

NSString *IKDiagnosticSummary(NSDictionary *s, NSString *bundle, double now, double wall) {
    if (![s[@"uptime"] isKindOfClass:NSNumber.class] || ![s[@"wall"] isKindOfClass:NSNumber.class]) return nil;
    double age = now-[s[@"uptime"] doubleValue], wallAge=wall-[s[@"wall"] doubleValue];
    if (!isfinite(age) || !isfinite(wallAge) || age<0 || age>90 || fabs(wallAge-age)>2) return nil;
    return IKReportLine(s,bundle);
}

static NSArray *IKHistoryEntries(NSURL *directory) {
    if (!directory.isFileURL) return nil;
    NSURL *url = [directory URLByAppendingPathComponent:IKPlaybackHistoryName];
    NSNumber *regular=nil, *size=nil;
    if (![url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil] || !regular.boolValue ||
        ![url getResourceValue:&size forKey:NSURLFileSizeKey error:nil] || size.unsignedIntegerValue>256*1024) return nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    NSData *bytes = [handle readDataUpToLength:256*1024+1 error:nil];
    [handle closeAndReturnError:nil];
    if (!bytes.length || bytes.length>256*1024) return nil;
    id entries = [NSPropertyListSerialization propertyListWithData:bytes options:0 format:NULL error:nil];
    return [entries isKindOfClass:NSArray.class] && [entries count]<=24 ? entries : nil;
}

// Each playback adapter is the sole writer in its own directory. Identical metadata shapes share one record.
void IKRememberDiagnostic(NSURL *directory, NSDictionary *packet) {
    NSMutableArray *entries = [IKHistoryEntries(directory) mutableCopy] ?: [NSMutableArray array];
    NSArray *identity = @[@"version",@"bundleID",@"fields",@"customFields",@"nestedFields",@"lyricObjects",@"unknown",@"asset",@"sidecarShapes",@"result"];
    NSUInteger match = [entries indexOfObjectPassingTest:^BOOL(id item, NSUInteger idx, BOOL *stop) {
        if (![item isKindOfClass:NSDictionary.class]) return NO;
        for (NSString *key in identity)
            if (packet[key] != item[key] && ![packet[key] isEqual:item[key]]) return NO;
        return YES;
    }];
    if (match != NSNotFound) [entries removeObjectAtIndex:match];
    if (entries.count >= 24) [entries removeObjectAtIndex:0];
    [entries addObject:packet];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:entries format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (data.length && data.length<=256*1024) [data writeToURL:[directory URLByAppendingPathComponent:IKPlaybackHistoryName] atomically:YES];
}

NSString *IKDiagnosticHistory(NSURL *directory, NSString *bundle) {
    NSMutableArray *lines = [NSMutableArray array];
    NSISO8601DateFormatter *date = [NSISO8601DateFormatter new];
    for (NSDictionary *packet in IKHistoryEntries(directory)) {
        NSString *summary = IKReportLine(packet,bundle);
        if (!summary || ![packet[@"wall"] isKindOfClass:NSNumber.class]) continue;
        double stamp = [packet[@"wall"] doubleValue];
        if (!isfinite(stamp) || stamp<=0 || stamp>1e11) continue;
        NSString *when = [date stringFromDate:[NSDate dateWithTimeIntervalSince1970:stamp]];
        [lines addObject:[NSString stringWithFormat:@"%@ %@",when,summary]];
    }
    return lines.count ? [lines componentsJoinedByString:@"\n"] : nil;
}
