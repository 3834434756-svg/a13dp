//
//  DOHiddenRootListController.m
//  Dopamine
//
//  Hidden root (RootHide style) blacklist management
//
//  Apps that are enabled in this list are injected with systemhook in "hidden root mode".
//  In that mode systemhook cleans up jailbreak traces from within the process, making
//  jailbreak detection based on file existence, environment variables and sysctl queries fail.
//
//  The list is stored at /var/mobile/zp.hide.plist (key = executable name, value = true)
//  and is consumed by systemhook at spawn time.

#import "DOHiddenRootListController.h"
#import "DOButtonCell.h"
#import "DOPSListController.h"
#import "DOUIManager.h"
#import "DOEnvironmentManager.h"
#import <CoreServices/LSApplicationWorkspace.h>

#define HIDDEN_ROOT_PLIST_PATH @"/var/mobile/zp.hide.plist"

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
    NSMutableDictionary *hiddenRootDict = [NSMutableDictionary dictionaryWithContentsOfFile:HIDDEN_ROOT_PLIST_PATH];
    if (!hiddenRootDict) {
        hiddenRootDict = [NSMutableDictionary dictionary];
    }

    NSMutableSet *seenExecutables = [NSMutableSet new];

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
            NSString *executable = proxy.bundleExecutable;
            if (!executable || [seenExecutables containsObject:executable]) continue;
            NSURL *bundleURL = proxy.bundleURL;
            if (!bundleURL) continue;
            [seenExecutables addObject:executable];
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
                @"executable": executable,
                @"displayName": displayName,
                @"enabled": @([hiddenRootDict[executable] boolValue]),
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
                    NSString *executable = info[@"CFBundleExecutable"];
                    if (!executable || [seenExecutables containsObject:executable]) continue;
                    [seenExecutables addObject:executable];
                    NSString *displayName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: appName.stringByDeletingPathExtension;
                    [apps addObject:@{
                        @"path": appPath,
                        @"executable": executable,
                        @"displayName": displayName,
                        @"enabled": @([hiddenRootDict[executable] boolValue]),
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
                        NSString *executable = info[@"CFBundleExecutable"];
                        if (!executable || [seenExecutables containsObject:executable]) continue;
                        [seenExecutables addObject:executable];
                        NSString *displayName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: appName.stringByDeletingPathExtension;
                        [apps addObject:@{
                            @"path": appPath,
                            @"executable": executable,
                            @"displayName": displayName,
                            @"enabled": @([hiddenRootDict[executable] boolValue]),
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

- (void)setAppEnabled:(NSNumber *)enabled specifier:(PSSpecifier *)specifier
{
    NSDictionary *appDict = [specifier propertyForKey:@"appDict"];
    NSString *executable = appDict[@"executable"];
    if (!executable) return;

    __block BOOL success = NO;
    [[DOEnvironmentManager sharedManager] runAsRoot:^{
        NSMutableDictionary *hiddenRootDict = [NSMutableDictionary dictionaryWithContentsOfFile:HIDDEN_ROOT_PLIST_PATH];
        if (!hiddenRootDict) {
            hiddenRootDict = [NSMutableDictionary dictionary];
        }

        if ([enabled boolValue]) {
            hiddenRootDict[executable] = @YES;
        }
        else {
            [hiddenRootDict removeObjectForKey:executable];
        }

        success = [hiddenRootDict writeToFile:HIDDEN_ROOT_PLIST_PATH atomically:YES];
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
