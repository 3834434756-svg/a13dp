#import <UIKit/UIKit.h>
#import "HTTPServer.h"
#import "AppList.h"
#import "ArchiveEngine.h"

@interface MainViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, ModifyHTTPServerDelegate>
@property (nonatomic, strong) NSArray<AppInfo *> *apps;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedApps;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *serverStatusLabel;
@property (nonatomic, strong) ModifyHTTPServer *server;
@property (nonatomic, strong) NSMutableArray<NSString *> *logLines;
@property (nonatomic, strong) UITextView *logView;
@end

@implementation MainViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"修改App";

    self.selectedApps = [NSMutableSet set];
    self.logLines = [NSMutableArray array];

    [self setupUI];
    [self loadApps];

    self.server = [[ModifyHTTPServer alloc] init];
    self.server.delegate = self;
    if ([self.server startOnPort:8765]) {
        [self appendLog:@"HTTP 服务已启动: http://127.0.0.1:8765"];
        self.serverStatusLabel.text = [NSString stringWithFormat:@"服务运行中: http://127.0.0.1:%d  (同局域网可用本机IP)", self.server.port];
    } else {
        self.serverStatusLabel.text = @"服务启动失败";
    }
}

- (void)setupUI
{
    CGFloat w = self.view.bounds.size.width;
    self.serverStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 100, w - 32, 40)];
    self.serverStatusLabel.font = [UIFont systemFontOfSize:13];
    self.serverStatusLabel.textColor = [UIColor systemGreenColor];
    self.serverStatusLabel.numberOfLines = 2;
    [self.view addSubview:self.serverStatusLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 150, w, 300) style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(16, 460, w - 32, 200)];
    self.logView.editable = NO;
    self.logView.font = [UIFont systemFontOfSize:11];
    self.logView.layer.borderWidth = 0.5;
    self.logView.layer.borderColor = [UIColor.systemGray4Color CGColor];
    self.logView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    [self.view addSubview:self.logView];
}

- (void)loadApps
{
    self.apps = [AppList allApps];
    [self.tableView reloadData];
    [self appendLog:[NSString stringWithFormat:@"已加载 %lu 个App", (unsigned long)self.apps.count]];
}

- (void)appendLog:(NSString *)message
{
    NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
    [self.logLines addObject:[NSString stringWithFormat:@"[%@] %@", ts, message]];
    if (self.logLines.count > 500) {
        [self.logLines removeObjectsInRange:NSMakeRange(0, self.logLines.count - 500)];
    }
    self.logView.text = [self.logLines componentsJoinedByString:@"\n"];
    [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length, 0)];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.apps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
    }
    AppInfo *info = self.apps[indexPath.row];
    cell.textLabel.text = info.name;
    cell.detailTextLabel.text = info.bundleId;
    cell.imageView.image = info.icon ?: [UIImage systemImageNamed:@"app"];
    cell.accessoryType = [self.selectedApps containsObject:info.bundleId] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    AppInfo *info = self.apps[indexPath.row];
    if ([self.selectedApps containsObject:info.bundleId]) {
        [self.selectedApps removeObject:info.bundleId];
    } else {
        [self.selectedApps addObject:info.bundleId];
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - HTTP API

- (NSData *)handleRequest:(NSString *)method path:(NSString *)path body:(NSData *)body
{
    NSMutableDictionary *response = [NSMutableDictionary dictionary];

    if ([path isEqualToString:@"/api/apps"]) {
        NSMutableArray *arr = [NSMutableArray array];
        for (AppInfo *info in self.apps) {
            [arr addObject:@{@"name": info.name ?: @"", @"bundleId": info.bundleId ?: @"", @"bundlePath": info.bundlePath ?: @"", @"dataPath": info.dataPath ?: @""}];
        }
        response[@"apps"] = arr;
    }
    else if ([path isEqualToString:@"/api/selected"]) {
        response[@"selected"] = [self.selectedApps allObjects];
    }
    else if ([path isEqualToString:@"/api/select"]) {
        NSDictionary *req = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
        NSString *bundleId = req[@"bundleId"];
        NSNumber *select = req[@"select"];
        if (bundleId) {
            if (select.boolValue) [self.selectedApps addObject:bundleId];
            else [self.selectedApps removeObject:bundleId];
            response[@"ok"] = @YES;
        }
    }
    else if ([path isEqualToString:@"/api/context"]) {
        // AI context: selected app data containers
        NSMutableArray *targets = [NSMutableArray array];
        for (AppInfo *info in self.apps) {
            if ([self.selectedApps containsObject:info.bundleId]) {
                [targets addObject:@{@"name": info.name ?: @"", @"bundleId": info.bundleId ?: @"", @"dataPath": info.dataPath ?: @"", @"bundlePath": info.bundlePath ?: @""}];
            }
        }
        response[@"selectedApps"] = targets;
        response[@"instructions"] = @[
            @"你可以用以下工具操作选中App：",
            @"list <path> - 列目录",
            @"read <path> [maxBytes] - 读文件(自动识别 plist/文本/二进制hex)",
            @"write <path> <text> - 写文本文件",
            @"plist <path> <keypath> <value> <int|float|bool|string> - 修改plist数值",
            @"sqlq <dbPath> <query> - SQLite 查询",
            @"sqle <dbPath> <query> - SQLite 执行",
        ];
    }
    else if ([path isEqualToString:@"/api/exec"]) {
        NSDictionary *req = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
        NSString *cmd = req[@"cmd"];
        NSString *arg = req[@"arg"] ?: @"";
        NSString *arg2 = req[@"arg2"];
        NSString *arg3 = req[@"arg3"];

        if ([cmd isEqualToString:@"list"]) {
            response[@"result"] = [ArchiveEngine listDirectory:arg];
        } else if ([cmd isEqualToString:@"read"]) {
            NSUInteger maxBytes = req[@"maxBytes"] ? [req[@"maxBytes"] unsignedIntegerValue] : 65536;
            response[@"result"] = [ArchiveEngine readFile:arg maxBytes:maxBytes];
        } else if ([cmd isEqualToString:@"write"]) {
            response[@"result"] = [ArchiveEngine writeFile:arg content:arg2];
        } else if ([cmd isEqualToString:@"plist"]) {
            NSString *type = req[@"type"] ?: @"string";
            response[@"result"] = [ArchiveEngine editPlist:arg keyPath:arg2 value:arg3 type:type];
        } else if ([cmd isEqualToString:@"sqlq"]) {
            response[@"result"] = [ArchiveEngine sqlQuery:arg query:arg2];
        } else if ([cmd isEqualToString:@"sqle"]) {
            response[@"result"] = [ArchiveEngine sqlExec:arg query:arg2];
        } else {
            response[@"error"] = @"unknown cmd";
        }
    }
    else {
        response[@"error"] = @"not found";
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:response options:NSJSONWritingPrettyPrinted error:nil];
    return json ?: [NSData data];
}

@end
