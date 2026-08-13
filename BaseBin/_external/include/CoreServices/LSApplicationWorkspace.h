#import "LSApplicationProxy.h"
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
- (NSArray<LSApplicationProxy *> *)allApplications;
- (BOOL)registerApplication:(NSURL *)bundleURL;
- (BOOL)unregisterApplication:(NSURL *)bundleURL;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleIdentifier;
@end
