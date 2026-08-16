#import <Foundation/Foundation.h>

@interface ModifyHTTPServer : NSObject
@property (nonatomic, weak) id delegate;
@property (nonatomic, readonly) uint16_t port;
- (BOOL)startOnPort:(uint16_t)port;
- (void)stop;
@end
