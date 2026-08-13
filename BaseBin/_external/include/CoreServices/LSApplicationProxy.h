#import "LSBundleProxy.h"
@interface LSApplicationProxy : LSBundleProxy
@property (getter=isInstalled,nonatomic,readonly) BOOL installed;
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property (nonatomic,readonly) NSSet * claimedURLSchemes;
@property (nonatomic,readonly) NSString *bundleIdentifier;
@property (nonatomic,readonly) NSString *localizedName;
@property (nonatomic,readonly) NSString *shortVersionString;
@property (nonatomic,readonly) NSString *applicationType;
@property (nonatomic,readonly) BOOL isSystemApplication;
@property (nonatomic,readonly) BOOL isPlaceholder;
@end