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

#define HIDDEN_ROOT_PLIST_PATH @"/var/mobile/zp.hide.plist"

@interface DOHiddenRootListController ()

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

    // Scan system applications
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

    // Scan user applications (mobile app data container)
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

    BOOL success = [hiddenRootDict writeToFile:HIDDEN_ROOT_PLIST_PATH atomically:YES];

    if (success) {
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
