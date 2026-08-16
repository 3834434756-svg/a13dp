#import <Foundation/Foundation.h>

@interface AIClient : NSObject
+ (instancetype)shared;
@property (nonatomic, strong) NSString *baseURL;
@property (nonatomic, strong) NSString *apiKey;
@property (nonatomic, strong) NSString *model;
- (NSString *)chat:(NSArray<NSDictionary *> *)messages error:(NSError **)error;
@end

@implementation AIClient

+ (instancetype)shared
{
    static AIClient *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[AIClient alloc] init];
        instance.baseURL = @"https://api.deepseek.com/v1";
        instance.model = @"deepseek-chat";
    });
    return instance;
}

- (NSString *)chat:(NSArray<NSDictionary *> *)messages error:(NSError **)error
{
    if (!self.apiKey.length) {
        if (error) *error = [NSError errorWithDomain:@"AIClient" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"未设置 API Key"}];
        return nil;
    }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/chat/completions", self.baseURL]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey] forHTTPHeaderField:@"Authorization"];

    NSDictionary *payload = @{
        @"model": self.model ?: @"deepseek-chat",
        @"messages": messages,
        @"max_tokens": @4096,
    };
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];

    __block NSString *result;
    __block NSError *blockError;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
        if (err) {
            blockError = err;
        } else {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (json[@"error"]) {
                blockError = [NSError errorWithDomain:@"AIClient" code:-2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"API错误: %@", json[@"error"]]}];
            } else {
                result = json[@"choices"][0][@"message"][@"content"];
            }
        }
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC));
    if (blockError && error) *error = blockError;
    return result;
}

@end
