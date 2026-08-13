//
//  DOHiddenRootListController.m
//  Dopamine
//
//  Hidden root (RootHide style) blacklist management
//
//  Apps that are enabled in this list are blacklisted from root hiding,
//  i.e. systemhook/jailbreakd will not hide jailbreak traces inside them.
//
//  The list is stored at {jbroot}/var/mobile/Library/RootHide/RootHideConfig.plist
//  (key "appconfig" = dict of bundle identifier -> bool) and is consumed by
//  jailbreakd / systemhook at spawn time.

#import "DOHiddenRootListController.h"
#import "DOButtonCell.h"
#import "DOPSListController.h"
#import "DOUIManager.h"
#import "DOEnvironmentManager.h"
#import <CoreServices/LSApplicationWorkspace.h>
#import <libjailbreak/info.h>

static NSString *rootHideConfigPath(void)
{
    const char *rootPath = gSystemInfo.jailbreakInfo.rootPath;
    if (rootPath && rootPath[0]) {
        return [[NSString stringWithUTF8String:rootPath] stringByAppendingPathComponent:@"var/mobile/Library/RootHide/RootHideConfig.plist"];
    }
    return nil;
}

static NSMutableDictionary *rootHideConfig(void)
{
    NSMutableDictionary *config = [NSMutableDictionary dictionaryWithContentsOfFile:rootHideConfigPath()];
    if (!config) {
        config = [NSMutableDictionary dictionary];
    }
    return config;
}

@interface DOHiddenRootListController ()
@property (nonatomic) BOOL scanFailed;
@property (nonatomic) int reloadAttempts;
@end

@implementation DOHiddenRootListController

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self reloadHiddenRootApps];
    }
    return self;
}

- (void)reloadHiddenRootApps
{
    NSMutableArray *apps = [NSMutableArray new];
    NSMutableDictionary *hiddenRootDict = [self blacklistedAppsDict];

    NSMutableSet *seenIdentifiers = [NSMutableSet new];

    // Primary enumeration: LSApplicationWorkspace private API.
    // This works inside the app sandbox and returns every installed app
    // regardless of which container directory it lives in.
    NSArray *proxies = nil;
    @try {
        proxies = [[LSApplicationWorkspace defaultWorkspace] allInstalledApplications];
    }
    @catch (NSException *e) {
        proxies = nil;
    }

    if (proxies.count > 0) {
        for (LSApplicationProxy *proxy in proxies) {
            NSString *identifier = proxy.bundleIdentifier;
            if (!identifier || [seenIdentifiers containsObject:identifier]) continue;
            NSURL *bundleURL = proxy.bundleURL;
            if (!bundleURL) continue;
            [seenIdentifiers addObject:identifier];
            NSString *displayName = proxy.localizedName;
            if (!displayName.length) {
                NSDictionary *info = [self infoForAppPath:bundleURL.path];
                displayName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
            }
            if (!displayName.length) {
                displayName = bundleURL.path.lastPathComponent.stringByDeletingPathExtension;
            }
            [apps addObject:@{
                @"path": bundleURL.path,
                @"identifier": identifier,
                @"displayName": displayName,
                @"enabled": @([hiddenRootDict[identifier] boolValue]),
            }];
        }
    }

    // Fallback: scan the filesystem directly.
    // If the primary enumeration came up empty (e.g. private API unavailable)
    // and we have root/unsandboxed access, enumerate the app containers by hand.
    if (apps.count == 0) {
        [[DOEnvironmentManager sharedManager] runAsRoot:^{
            [[DOEnvironmentManager sharedManager] runUnsandboxed:^{
                NSArray *systemApps = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Applications" error:nil];
                for (NSString *appName in systemApps) {
                    if (![appName hasSuffix:@".app"]) continue;
                    NSString *appPath = [@"/Applications" stringByAppendingPathComponent:appName];
                    NSDictionary *info = [self infoForAppPath:appPath];
                    if (!info) continue;
                    NSString *identifier = info[@"CFBundleIdentifier"];
                    if (!identifier || [seenIdentifiers containsObject:identifier]) continue;
                    [seenIdentifiers addObject:identifier];
                    NSString *displayName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: appName.stringByDeletingPathExtension;
                    [apps addObject:@{
                        @"path": appPath,
                        @"identifier": identifier,
                        @"displayName": displayName,
                        @"enabled": @([hiddenRootDict[identifier] boolValue]),
                    }];
                }

                NSString *appContainerRoot = @"/var/containers/Bundle/Application";
                NSArray *containerUUIDs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appContainerRoot error:nil];
                for (NSString *uuid in containerUUIDs) {
                    NSString *uuidPath = [appContainerRoot stringByAppendingPathComponent:uuid];
                    NSArray *appsInUUID = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:uuidPath error:nil];
                    for (NSString *appName in appsInUUID) {
                        if (![appName hasSuffix:@".app"]) continue;
                        NSString *appPath = [uuidPath stringByAppendingPathComponent:appName];
                        NSDictionary *info = [self infoForAppPath:appPath];
                        if (!info) continue;
                        NSString *identifier = info[@"CFBundleIdentifier"];
                        if (!identifier || [seenIdentifiers containsObject:identifier]) continue;
                        [seenIdentifiers addObject:identifier];
                        NSString *displayName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: appName.stringByDeletingPathExtension;
                        [apps addObject:@{
                            @"path": appPath,
                            @"identifier": identifier,
                            @"displayName": displayName,
                            @"enabled": @([hiddenRootDict[identifier] boolValue]),
                        }];
                    }
                }
            }];
        }];
    }

    self.scanFailed = (apps.count == 0);

    // Empty result is most likely a transient launchd / sandbox race.
    // Retry a couple of times before giving up.
    if (self.scanFailed && self.reloadAttempts < 3) {
        self.reloadAttempts += 1;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self reloadHiddenRootApps];
            [self reloadSpecifiers];
        });
    }

    [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL aEnabled = [a[@"enabled"] boolValue];
        BOOL bEnabled = [b[@"enabled"] boolValue];
        if (aEnabled != bEnabled) {
            return aEnabled ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a[@"displayName"] localizedCaseInsensitiveCompare:b[@"displayName"]];
    }];

    _hiddenRootApps = [apps copy];
}

- (NSDictionary *)infoForAppPath:(NSString *)appPath
{
    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    return [NSDictionary dictionaryWithContentsOfFile:infoPath];
}

- (NSMutableDictionary *)blacklistedAppsDict
{
    NSMutableDictionary *config = rootHideConfig();
    NSMutableDictionary *appconfig = [config[@"appconfig"] mutableCopy];
    if (!appconfig) {
        appconfig = [NSMutableDictionary dictionary];
    }
    return appconfig;
}

- (void)setAppEnabled:(NSNumber *)enabled specifier:(PSSpecifier *)specifier
{
    NSDictionary *appDict = [specifier propertyForKey:@"appDict"];
    NSString *identifier = appDict[@"identifier"];
    if (!identifier) return;
    NSString *configPath = rootHideConfigPath();
    if (!configPath) return;

    __block BOOL success = NO;
    [[DOEnvironmentManager sharedManager] runAsRoot:^{
        NSMutableDictionary *config = rootHideConfig();
        NSMutableDictionary *appconfig = [config[@"appconfig"] mutableCopy];
        if (!appconfig) {
            appconfig = [NSMutableDictionary dictionary];
        }

        if ([enabled boolValue]) {
            appconfig[identifier] = @YES;
        }
        else {
            [appconfig removeObjectForKey:identifier];
        }

        config[@"appconfig"] = appconfig;
        success = [config writeToFile:configPath atomically:YES];
    }];

    if (success) {
        self.reloadAttempts = 0;
        [self reloadHiddenRootApps];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadSpecifiers];
        });
    }
    else {
        UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Log_Error") message:DOLocalizedString(@"Error_Save_Hidden_Root_Body") preferredStyle:UIAlertControllerStyleAlert];
        [errorAlert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Ok") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:errorAlert animated:YES completion:nil];
    }
}

- (id)readAppEnabled:(PSSpecifier *)specifier
{
    NSDictionary *appDict = [specifier propertyForKey:@"appDict"];
    return appDict[@"enabled"];
}

- (void)reloadHiddenRootPressed
{
    [self reloadHiddenRootApps];
    [self reloadSpecifiers];
}

- (id)specifiers
{
    if (_specifiers == nil) {
        NSMutableArray *specifiers = [NSMutableArray new];

        PSSpecifier *headerGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
        headerGroupSpecifier.name = DOLocalizedString(@"Section_Hidden_Root");
        [specifiers addObject:headerGroupSpecifier];

        PSSpecifier *hintSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Hint_Hidden_Root") target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
        [hintSpecifier setProperty:@YES forKey:@"enabled"];
        [specifiers addObject:hintSpecifier];

        PSSpecifier *reloadSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
        [reloadSpecifier setProperty:@"Button_Refresh_Hidden_Root" forKey:@"title"];
        [reloadSpecifier setProperty:[DOButtonCell class] forKey:@"cellClass"];
        [reloadSpecifier setProperty:@44 forKey:@"height"];
        [reloadSpecifier setProperty:@"arrow.triangle.2.circlepath" forKey:@"image"];
        [reloadSpecifier setProperty:@"reloadHiddenRootPressed" forKey:@"action"];
        [specifiers addObject:reloadSpecifier];

        PSSpecifier *appsGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
        appsGroupSpecifier.name = DOLocalizedString(@"Section_Hidden_Root_Apps");
        [specifiers addObject:appsGroupSpecifier];

        if (_hiddenRootApps.count == 0) {
            PSSpecifier *emptySpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(self.scanFailed ? @"Error_Hidden_Root_Scan_Failed" : @"Hint_Hidden_Root_Empty") target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
            [emptySpecifier setProperty:@YES forKey:@"enabled"];
            [specifiers addObject:emptySpecifier];
        }

        for (NSDictionary *appDict in _hiddenRootApps) {
            PSSpecifier *appSpecifier = [PSSpecifier preferenceSpecifierNamed:appDict[@"displayName"] target:self set:@selector(setAppEnabled:specifier:) get:@selector(readAppEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [appSpecifier setProperty:@YES forKey:@"enabled"];
            [appSpecifier setProperty:appDict forKey:@"appDict"];
            [appSpecifier setProperty:appDict[@"enabled"] forKey:@"default"];
            [specifiers addObject:appSpecifier];
        }

        _specifiers = specifiers;
    }
    return _specifiers;
}

#pragma mark - Status Bar

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

@end
