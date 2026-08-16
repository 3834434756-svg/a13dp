#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "AppList.h"

// Private API to enumerate installed apps
@interface LSApplicationProxy : NSObject
- (NSString *)localizedName;
- (NSString *)bundleIdentifier;
- (NSString *)bundleURL;
- (NSURL *)dataContainerURL;
- (NSURL *)bundleContainerURL;
- (NSString *)applicationType;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (NSArray *)allApplications;
@end

@implementation AppInfo
@end

@implementation AppList

+ (NSArray<AppInfo *> *)allApps
{
    NSMutableArray *result = [NSMutableArray array];
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!wsClass) return result;

    LSApplicationWorkspace *ws = [wsClass performSelector:@selector(defaultWorkspace)];
    NSArray *apps = [ws performSelector:@selector(allApplications)];

    for (LSApplicationProxy *proxy in apps) {
        NSString *type = [proxy applicationType];
        if (type && ![type isEqualToString:@"User"]) continue; // only user apps

        AppInfo *info = [[AppInfo alloc] init];
        info.name = [proxy localizedName] ?: [proxy bundleIdentifier];
        info.bundleId = [proxy bundleIdentifier];
        info.bundlePath = [proxy bundleURL];
        NSString *bundlePath = [proxy bundleURL];
        info.dataPath = [[proxy dataContainerURL] path];

        if (bundlePath && bundlePath.length) {
            NSString *iconFile = [self findIconInBundle:bundlePath];
            if (iconFile) {
                info.icon = [UIImage imageWithContentsOfFile:iconFile];
            }
        }
        [result addObject:info];
    }
    return result;
}

+ (NSString *)findIconInBundle:(NSString *)bundlePath
{
    NSString *infoPlistPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
    if (!info) return nil;

    NSArray *icons = info[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"];
    if (!icons.count) {
        icons = info[@"CFBundleIconFiles"];
    }
    for (NSString *iconName in icons) {
        NSString *candidate = [bundlePath stringByAppendingPathComponent:iconName];
        NSString *iconFile = [self existingIcon:candidate];
        if (iconFile) return iconFile;
    }
    return nil;
}

+ (NSString *)existingIcon:(NSString *)basePath
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:basePath]) return basePath;
    for (NSString *ext in @[@"png", @"jpg", @"jpeg"]) {
        NSString *candidate = [basePath stringByAppendingPathExtension:ext];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) return candidate;
    }
    return nil;
}

@end
