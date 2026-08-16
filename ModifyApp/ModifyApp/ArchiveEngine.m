#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import "ArchiveEngine.h"

@implementation ArchiveEngine

+ (NSDictionary *)listDirectory:(NSString *)path
{
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir]) {
        return @{@"error": @"path not found", @"path": path ?: @""};
    }
    NSMutableArray *items = [NSMutableArray array];
    NSArray *contents = [fm contentsOfDirectoryAtPath:path error:nil];
    for (NSString *name in contents) {
        NSString *full = [path stringByAppendingPathComponent:name];
        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
        BOOL dir = [attrs[NSFileType] isEqualToString:NSFileTypeDirectory];
        NSNumber *size = attrs[NSFileSize] ?: @(0);
        [items addObject:@{@"name": name, @"dir": @(dir), @"size": size}];
    }
    return @{@"path": path, @"items": items};
}

+ (NSDictionary *)readFile:(NSString *)path maxBytes:(NSUInteger)maxBytes
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return @{@"error": @"read failed", @"path": path ?: @""};

    if (maxBytes > 0 && data.length > maxBytes) {
        data = [data subdataWithRange:NSMakeRange(0, maxBytes)];
    }

    // Try plist
    NSError *plistError = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&plistError];
    if (!plistError && plist) {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self plistToJSON:plist] options:NSJSONWritingPrettyPrinted error:nil];
        if (jsonData) {
            return @{@"path": path, @"type": @"plist", @"content": [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]};
        }
    }

    // Try UTF-8 text
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text) {
        return @{@"path": path, @"type": @"text", @"content": text};
    }

    // Binary hex
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger i = 0; i < data.length; i += 16) {
        NSUInteger len = MIN(16, data.length - i);
        [hex appendFormat:@"%04zx: ", i];
        for (NSUInteger j = 0; j < len; j++) {
            [hex appendFormat:@"%02x ", ((uint8_t *)data.bytes)[i+j]];
        }
        [hex appendString:@"\n"];
    }
    return @{@"path": path, @"type": @"binary", @"content": hex, @"size": @(data.length)};
}

+ (NSDictionary *)writeFile:(NSString *)path content:(NSString *)content
{
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    BOOL ok = [data writeToFile:path options:NSDataWritingAtomic error:&error];
    if (ok) {
        return @{@"success": @YES, @"path": path, @"bytes": @(data.length)};
    }
    return @{@"success": @NO, @"error": error.localizedDescription ?: @"write failed"};
}

+ (NSDictionary *)editPlist:(NSString *)path keyPath:(NSString *)keyPath value:(NSString *)value type:(NSString *)type
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return @{@"error": @"read failed"};

    NSPropertyListFormat format;
    NSError *plistError = nil;
    NSMutableDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:&format error:&plistError];
    if (plistError) return @{@"error": @"not a plist"};

    NSArray *keys = [keyPath componentsSeparatedByString:@"."];
    if (keys.count == 0) return @{@"error": @"empty keypath"};

    id current = plist;
    for (NSUInteger i = 0; i < keys.count - 1; i++) {
        current = [current objectForKey:keys[i]];
        if (!current) return @{@"error": [NSString stringWithFormat:@"key not found: %@", keys[i]]};
    }

    id newValue = [self parseValue:value type:type];
    [current setObject:newValue forKey:keys.lastObject];

    NSData *newData = [NSPropertyListSerialization dataWithPropertyList:plist format:format options:0 error:&plistError];
    if (plistError) return @{@"error": plistError.localizedDescription};

    BOOL ok = [newData writeToFile:path options:NSDataWritingAtomic error:nil];
    return @{@"success": @(ok), @"path": path};
}

+ (id)parseValue:(NSString *)value type:(NSString *)type
{
    if ([type isEqualToString:@"int"]) return @([value integerValue]);
    if ([type isEqualToString:@"float"]) return @([value doubleValue]);
    if ([type isEqualToString:@"bool"]) return @([value boolValue]);
    return value;
}

+ (id)plistToJSON:(id)obj
{
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        [(NSDictionary *)obj enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
            result[[key description]] = [self plistToJSON:val];
        }];
        return result;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *result = [NSMutableArray array];
        for (id val in (NSArray *)obj) [result addObject:[self plistToJSON:val]];
        return result;
    }
    if ([obj isKindOfClass:[NSData class]]) {
        return [NSString stringWithFormat:@"<data:%lu>", (unsigned long)[(NSData *)obj length]];
    }
    return obj;
}

+ (NSDictionary *)sqlQuery:(NSString *)dbPath query:(NSString *)query
{
    sqlite3 *db = NULL;
    if (sqlite3_open([dbPath UTF8String], &db) != SQLITE_OK) {
        return @{@"error": @"open failed"};
    }
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, [query UTF8String], -1, &stmt, NULL) != SQLITE_OK) {
        NSString *err = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
        sqlite3_close(db);
        return @{@"error": err};
    }

    NSMutableArray *rows = [NSMutableArray array];
    int cols = sqlite3_column_count(stmt);
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        for (int i = 0; i < cols; i++) {
            const char *colName = sqlite3_column_name(stmt, i);
            NSString *key = colName ? [NSString stringWithUTF8String:colName] : [NSString stringWithFormat:@"col%d", i];
            int type = sqlite3_column_type(stmt, i);
            if (type == SQLITE_INTEGER) {
                row[key] = @(sqlite3_column_int64(stmt, i));
            } else if (type == SQLITE_FLOAT) {
                row[key] = @(sqlite3_column_double(stmt, i));
            } else if (type == SQLITE_TEXT) {
                row[key] = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, i)];
            } else if (type == SQLITE_NULL) {
                row[key] = [NSNull null];
            } else {
                const void *blob = sqlite3_column_blob(stmt, i);
                int len = sqlite3_column_bytes(stmt, i);
                row[key] = blob ? [NSString stringWithFormat:@"<blob:%d>", len] : @"";
            }
        }
        [rows addObject:row];
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return @{@"rows": rows, @"count": @(rows.count)};
}

+ (NSDictionary *)sqlExec:(NSString *)dbPath query:(NSString *)query
{
    sqlite3 *db = NULL;
    if (sqlite3_open([dbPath UTF8String], &db) != SQLITE_OK) {
        return @{@"error": @"open failed"};
    }
    char *errMsg = NULL;
    int rc = sqlite3_exec(db, [query UTF8String], NULL, NULL, &errMsg);
    NSString *err = errMsg ? [NSString stringWithUTF8String:errMsg] : nil;
    if (errMsg) sqlite3_free(errMsg);
    sqlite3_close(db);
    if (rc == SQLITE_OK) {
        return @{@"success": @YES, @"query": query};
    }
    return @{@"success": @NO, @"error": err ?: @"exec failed"};
}

@end
