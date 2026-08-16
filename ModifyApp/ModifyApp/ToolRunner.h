#import <Foundation/Foundation.h>
#import "ArchiveEngine.h"

@interface ToolRunner : NSObject
+ (NSDictionary *)run:(NSDictionary *)call;
@end

@implementation ToolRunner

+ (NSDictionary *)run:(NSDictionary *)call
{
    NSString *cmd = call[@"cmd"];
    NSString *path = call[@"path"] ?: @"";
    NSString *value = call[@"value"];
    NSString *keyPath = call[@"keyPath"];
    NSString *type = call[@"type"] ?: @"string";
    NSString *query = call[@"query"];

    if ([cmd isEqualToString:@"list"]) return [ArchiveEngine listDirectory:path];
    if ([cmd isEqualToString:@"read"]) return [ArchiveEngine readFile:path maxBytes:65536];
    if ([cmd isEqualToString:@"write"]) return [ArchiveEngine writeFile:path content:value];
    if ([cmd isEqualToString:@"plist"]) return [ArchiveEngine editPlist:path keyPath:keyPath value:value type:type];
    if ([cmd isEqualToString:@"sqlq"]) return [ArchiveEngine sqlQuery:path query:query];
    if ([cmd isEqualToString:@"sqle"]) return [ArchiveEngine sqlExec:path query:query];
    return @{@"error": [NSString stringWithFormat:@"未知命令 %@", cmd ?: @""]};
}

@end
