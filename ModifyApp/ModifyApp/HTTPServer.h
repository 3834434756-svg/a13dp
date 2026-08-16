#import <Foundation/Foundation.h>

@protocol ModifyHTTPServerDelegate <NSObject>
- (NSData *)handleRequest:(NSString *)method path:(NSString *)path body:(NSData *)body;
@end

@interface ModifyHTTPServer : NSObject
@property (nonatomic, weak) id<ModifyHTTPServerDelegate> delegate;
@property (nonatomic, readonly) uint16_t port;
- (BOOL)startOnPort:(uint16_t)port;
- (void)stop;
@end
