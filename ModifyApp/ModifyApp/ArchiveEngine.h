#import <Foundation/Foundation.h>

@interface ArchiveEngine : NSObject
+ (NSDictionary *)listDirectory:(NSString *)path;
+ (NSDictionary *)readFile:(NSString *)path maxBytes:(NSUInteger)maxBytes;
+ (NSDictionary *)writeFile:(NSString *)path content:(NSString *)content;
+ (NSDictionary *)editPlist:(NSString *)path keyPath:(NSString *)keyPath value:(NSString *)value type:(NSString *)type;
+ (NSDictionary *)sqlQuery:(NSString *)dbPath query:(NSString *)query;
+ (NSDictionary *)sqlExec:(NSString *)dbPath query:(NSString *)query;
@end
