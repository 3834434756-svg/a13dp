#import <UIKit/UIKit.h>

@interface AppInfo : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *bundleId;
@property (nonatomic, strong) NSString *bundlePath;
@property (nonatomic, strong) NSString *dataPath;
@property (nonatomic, strong) UIImage *icon;
@end

@interface AppList : NSObject
+ (NSArray<AppInfo *> *)allApps;
@end
