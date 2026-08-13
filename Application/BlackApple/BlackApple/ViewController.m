#import "ViewController.h"
#import <CoreServices/LSApplicationWorkspace.h>
#import <spawn.h>
#import <sys/stat.h>

#define HIDDEN_ROOT_PLIST_PATH @"/var/mobile/zp.hide.plist"
#define JB_APPLICATIONS_PATH   @"/var/jb/Applications"
#define DOPAMINE_BUNDLE_ID     @"com.zqbb.Dopamine"

typedef NS_ENUM(NSInteger, SectionType) {
    SectionStatus = 0,
    SectionActions,
    SectionApps,
};

@interface ViewController ()
@property (nonatomic, strong) NSArray *appDicts;
@property (nonatomic, assign) BOOL isJailbroken;
@property (nonatomic, assign) BOOL isRooted;
@end

@implementation ViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"黑苹果";
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self refreshState];
}

- (void)refreshState
{
    // Determine jailbreak status the same way systemhook does.
    struct stat st;
    self.isJailbroken = (stat("/var/jb", &st) == 0);
    self.isRooted = (geteuid() == 0);
    [self loadApps];
}

- (void)loadApps
{
    NSMutableArray *apps = [NSMutableArray new];
    NSDictionary *hiddenRootDict = [NSDictionary dictionaryWithContentsOfFile:HIDDEN_ROOT_PLIST_PATH];
    if (!hiddenRootDict) hiddenRootDict = @{};

    NSMutableSet *seenExecutables = [NSMutableSet new];

    NSArray *proxies = nil;
    @try {
        proxies = [[LSApplicationWorkspace defaultWorkspace] allInstalledApplications];
    }
    @catch (NSException *e) {
        proxies = nil;
    }

    for (LSApplicationProxy *proxy in proxies) {
        NSString *executable = proxy.bundleExecutable;
        if (!executable || [seenExecutables containsObject:executable]) continue;
        NSURL *bundleURL = proxy.bundleURL;
        if (!bundleURL) continue;
        [seenExecutables addObject:executable];

        NSString *displayName = proxy.localizedName;
        if (!displayName.length) displayName = bundleURL.path.lastPathComponent.stringByDeletingPathExtension;

        [apps addObject:@{
            @"path": bundleURL.path,
            @"executable": executable,
            @"displayName": displayName,
            @"enabled": @([hiddenRootDict[executable] boolValue]),
        }];
    }

    [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL aEnabled = [a[@"enabled"] boolValue];
        BOOL bEnabled = [b[@"enabled"] boolValue];
        if (aEnabled != bEnabled) {
            return aEnabled ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a[@"displayName"] localizedCaseInsensitiveCompare:b[@"displayName"]];
    }];

    _appDicts = [apps copy];
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshState];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case SectionStatus: return @"状态";
        case SectionActions: return @"操作";
        case SectionApps: return @"隐根名单（勾选的应用检测不到越狱环境）";
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case SectionStatus: return 3;
        case SectionActions: return 3;
        case SectionApps: return self.appDicts.count;
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == SectionApps) {
        static NSString *cellID = @"AppCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];
            UISwitch *sw = [UISwitch new];
            [sw addTarget:self action:@selector(appSwitchToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
        NSDictionary *appDict = self.appDicts[indexPath.row];
        cell.textLabel.text = appDict[@"displayName"];
        UISwitch *sw = (UISwitch *)cell.accessoryView;
        sw.tag = indexPath.row;
        sw.on = [appDict[@"enabled"] boolValue];
        return cell;
    }

    static NSString *cellID = @"StaticCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellID];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == SectionStatus) {
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = @"越狱状态";
                cell.detailTextLabel.text = self.isJailbroken ? @"已越狱" : @"未越狱";
                break;
            case 1:
                cell.textLabel.text = @"权限";
                cell.detailTextLabel.text = self.isRooted ? @"root" : @"受限";
                break;
            case 2:
                cell.textLabel.text = @"模式";
                cell.detailTextLabel.text = @"黑苹果独立控制";
                break;
        }
    }
    else if (indexPath.section == SectionActions) {
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = @"刷新";
                break;
            case 1:
                cell.textLabel.text = @"打开 Dopamine";
                break;
            case 2:
                cell.textLabel.text = @"注册到越狱环境 (/var/jb/Applications)";
                break;
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != SectionActions) return;

    switch (indexPath.row) {
        case 0:
            [self refreshState];
            break;
        case 1:
            [self openDopamine];
            break;
        case 2:
            [self activateToJailbreakEnvironment];
            break;
    }
}

#pragma mark - Actions

- (void)appSwitchToggled:(UISwitch *)sw
{
    NSDictionary *appDict = self.appDicts[sw.tag];
    NSString *executable = appDict[@"executable"];
    if (!executable) return;

    NSMutableDictionary *hiddenRootDict = [NSMutableDictionary dictionaryWithContentsOfFile:HIDDEN_ROOT_PLIST_PATH];
    if (!hiddenRootDict) hiddenRootDict = [NSMutableDictionary dictionary];

    if (sw.on) {
        hiddenRootDict[executable] = @YES;
    }
    else {
        [hiddenRootDict removeObjectForKey:executable];
    }

    BOOL success = [hiddenRootDict writeToFile:HIDDEN_ROOT_PLIST_PATH atomically:YES];
    if (!success) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存失败" message:@"无法写入 zp.hide.plist，请确认已通过 TrollStore 安装。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        sw.on = !sw.on;
    }
    else {
        [self loadApps];
    }
}

- (void)openDopamine
{
    LSApplicationProxy *dopamineProxy = [LSApplicationProxy applicationProxyForIdentifier:DOPAMINE_BUNDLE_ID];
    if (dopamineProxy && dopamineProxy.installed) {
        [[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:DOPAMINE_BUNDLE_ID];
    }
    else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"未找到 Dopamine" message:@"请先安装 Dopamine。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)activateToJailbreakEnvironment
{
    if (!self.isRooted) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需要权限" message:@"当前未获得 root 权限，无法注册。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSString *selfBundlePath = NSBundle.mainBundle.bundlePath;
    NSString *targetPath = [JB_APPLICATIONS_PATH stringByAppendingPathComponent:@"BlackApple.app"];

    [[NSFileManager defaultManager] removeItemAtPath:targetPath error:nil];
    NSError *error = nil;
    BOOL copied = [[NSFileManager defaultManager] copyItemAtPath:selfBundlePath toPath:targetPath error:&error];

    if (!copied) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"注册失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // Register the copied app with the system so it shows up on the home screen.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        pid_t pid;
        NSArray *uicachePaths = @[
            @"/var/jb/usr/bin/uicache",
            @"/var/jb/basebin/uicache",
        ];
        const char *uicachePath = NULL;
        for (NSString *path in uicachePaths) {
            struct stat st;
            if (stat(path.UTF8String, &st) == 0) {
                uicachePath = path.UTF8String;
                break;
            }
        }
        if (uicachePath) {
            posix_spawn(&pid, uicachePath, NULL, NULL, (char *const[]){ (char *)uicachePath, (char *)targetPath.UTF8String, NULL }, NULL);
        }
    });

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"注册成功" message:@"已将 BlackApple 复制到 /var/jb/Applications 并执行 uicache 注册。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
