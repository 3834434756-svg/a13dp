#import <Foundation/Foundation.h>

@interface AIClient : NSObject
+ (instancetype)shared;
@property (nonatomic, strong) NSString *baseURL;
@property (nonatomic, strong) NSString *apiKey;
@property (nonatomic, strong) NSString *model;
- (NSString *)chat:(NSArray<NSDictionary *> *)messages error:(NSError **)error;
@end
