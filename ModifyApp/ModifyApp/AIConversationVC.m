#import "AIConversationVC.h"
#import "AIClient.h"
#import "ArchiveEngine.h"
#import "ToolRunner.h"

@implementation AIConversationVC

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = self.targetName ?: @"AI 修改";

    [self setupUI];
    [self appendLog:[NSString stringWithFormat:@"目标App: %@ (%@)", self.targetName ?: @"", self.targetBundleId ?: @""]];
    [self appendLog:@"存档目录: "];
    if (self.targetDataPath) {
        [self appendLog:self.targetDataPath];
        NSDictionary *listing = [ArchiveEngine listDirectory:self.targetDataPath];
        for (NSDictionary *item in listing[@"items"]) {
            [self appendLog:[NSString stringWithFormat:@"  %@ %@", item[@"dir"] ? @"[目录]" : @"", item[@"name"]]];
        }
    }
}

- (void)setupUI
{
    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 90;

    // API config
    self.baseURLField = [self makeField:@"Base URL (默认 https://api.deepseek.com/v1)" frame:CGRectMake(16, y, w - 32, 34)];
    self.baseURLField.text = [AIClient shared].baseURL;
    y += 42;
    self.apiKeyField = [self makeField:@"API Key (DeepSeek/OpenAI兼容)" frame:CGRectMake(16, y, w - 32, 34)];
    self.apiKeyField.secureTextEntry = YES;
    y += 42;
    self.modelField = [self makeField:@"模型 (默认 deepseek-chat)" frame:CGRectMake(16, y, w - 32, 34)];
    self.modelField.text = [AIClient shared].model;
    y += 42;

    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [saveBtn setTitle:@"保存配置" forState:UIControlStateNormal];
    saveBtn.frame = CGRectMake(16, y, 120, 34);
    [saveBtn addTarget:self action:@selector(saveConfig) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:saveBtn];
    y += 44;

    // Log
    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(16, y, w - 32, 200)];
    self.logView.editable = NO;
    self.logView.font = [UIFont systemFontOfSize:11];
    self.logView.layer.borderWidth = 0.5;
    self.logView.layer.borderColor = [UIColor.systemGray4Color CGColor];
    [self.view addSubview:self.logView];
    y += 208;

    // Input
    self.inputField = [self makeField:@"输入指令，如：把金币改成100000" frame:CGRectMake(16, y, w - 100, 34)];
    self.inputField.delegate = self;
    y += 42;
    UIButton *sendBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [sendBtn setTitle:@"发送" forState:UIControlStateNormal];
    sendBtn.frame = CGRectMake(w - 80, y - 34, 64, 34);
    [sendBtn addTarget:self action:@selector(sendRequest) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:sendBtn];
}

- (UITextField *)makeField:(NSString *)placeholder frame:(CGRect)frame
{
    UITextField *field = [[UITextField alloc] initWithFrame:frame];
    field.placeholder = placeholder;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.font = [UIFont systemFontOfSize:13];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.view addSubview:field];
    return field;
}

- (void)saveConfig
{
    AIClient *client = [AIClient shared];
    client.baseURL = self.baseURLField.text.length ? self.baseURLField.text : @"https://api.deepseek.com/v1";
    client.apiKey = self.apiKeyField.text;
    client.model = self.modelField.text.length ? self.modelField.text : @"deepseek-chat";
    [self appendLog:@"配置已保存"];
}

- (void)sendRequest
{
    NSString *instruction = self.inputField.text;
    if (!instruction.length) return;
    self.inputField.text = @"";
    [self appendLog:[NSString stringWithFormat:@">> %@", instruction]];
    [self saveConfig];

    // Build system prompt with tool context
    NSString *systemPrompt = [NSString stringWithFormat:
        @"你是iOS存档修改助手。目标App: %@ (%@)。数据目录: %@\n"
        @"你可以调用以下工具，每次只调用一个，返回格式为一行JSON: "
        @"{\"cmd\":\"list\",\"path\":\"...\"} / "
        @"{\"cmd\":\"read\",\"path\":\"...\"} / "
        @"{\"cmd\":\"write\",\"path\":\"...\",\"value\":\"...\"} / "
        @"{\"cmd\":\"plist\",\"path\":\"...\",\"keyPath\":\"...\",\"value\":\"...\",\"type\":\"int|float|bool|string\"} / "
        @"{\"cmd\":\"sqlq\",\"path\":\"...\",\"query\":\"...\"} / "
        @"{\"cmd\":\"sqle\",\"path\":\"...\",\"query\":\"...\"}\n"
        @"先列目录、读文件分析存档结构，找到金钱/金币字段后修改。每次调用后我会返回结果，你根据结果决定下一步，直到完成。",
        self.targetName ?: @"", self.targetBundleId ?: @"", self.targetDataPath ?: @""];

    NSMutableArray *messages = [NSMutableArray array];
    [messages addObject:@{@"role": @"system", @"content": systemPrompt}];
    [messages addObject:@{@"role": @"user", @"content": instruction}];

    [self runConversation:messages];
}

- (void)runConversation:(NSMutableArray *)messages
{
    AIClient *client = [AIClient shared];
    NSError *error = nil;
    NSString *reply = [client chat:messages error:&error];
    if (error) {
        [self appendLog:[NSString stringWithFormat:@"AI错误: %@", error.localizedDescription]];
        return;
    }
    [self appendLog:[NSString stringWithFormat:@"AI: %@", reply]];

    // Try to parse a JSON tool call (may be embedded in the reply)
    NSDictionary *call = [self parseToolCall:reply];
    if (call) {
        NSDictionary *result = [ToolRunner run:call];
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        NSString *resultStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        [self appendLog:[NSString stringWithFormat:@"工具(%@): %@", call[@"cmd"], resultStr]];
        [messages addObject:@{@"role": @"assistant", @"content": reply}];
        [messages addObject:@{@"role": @"user", @"content": [NSString stringWithFormat:@"工具结果: %@", resultStr]}];
        [self runConversation:messages];
    }
}

- (NSDictionary *)parseToolCall:(NSString *)text
{
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\{.*\\}" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match) return nil;
    NSString *jsonStr = [text substringWithRange:match.range];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:[jsonStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    if (!dict[@"cmd"]) return nil;
    return dict;
}

- (void)appendLog:(NSString *)message
{
    NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
    self.logView.text = [NSString stringWithFormat:@"%@[%@] %@\n", self.logView.text, ts, message];
    [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length, 0)];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self sendRequest];
    return YES;
}

@end
