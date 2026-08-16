#import <Foundation/Foundation.h>
#import "HTTPServer.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <pthread.h>

@implementation ModifyHTTPServer {
    int _listenFd;
    pthread_t _thread;
    BOOL _running;
    uint16_t _port;
}

- (BOOL)startOnPort:(uint16_t)port
{
    _listenFd = socket(AF_INET, SOCK_STREAM, 0);
    if (_listenFd < 0) return NO;

    int yes = 1;
    setsockopt(_listenFd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(_listenFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(_listenFd);
        return NO;
    }
    if (listen(_listenFd, 16) < 0) {
        close(_listenFd);
        return NO;
    }

    _port = port;
    _running = YES;
    pthread_create(&_thread, NULL, serverLoop, (__bridge void *)self);
    return YES;
}

- (void)stop
{
    _running = NO;
    if (_listenFd >= 0) close(_listenFd);
}

static void *serverLoop(void *arg)
{
    ModifyHTTPServer *server = (__bridge ModifyHTTPServer *)arg;
    while (server->_running) {
        struct sockaddr_in clientAddr;
        socklen_t clientLen = sizeof(clientAddr);
        int clientFd = accept(server->_listenFd, (struct sockaddr *)&clientAddr, &clientLen);
        if (clientFd < 0) continue;
        [server handleClient:clientFd];
        close(clientFd);
    }
    return NULL;
}

- (void)handleClient:(int)clientFd
{
    // Read request (simplified, up to 1MB)
    NSMutableData *requestData = [NSMutableData data];
    char buffer[4096];
    ssize_t n;
    BOOL headerDone = NO;
    NSData *headerEnd = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];

    while ((n = read(clientFd, buffer, sizeof(buffer))) > 0) {
        [requestData appendBytes:buffer length:n];
        if (!headerDone && requestData.length >= 4) {
            NSRange range = [requestData rangeOfData:headerEnd options:0 range:NSMakeRange(0, requestData.length)];
            if (range.location != NSNotFound) {
                headerDone = YES;
                // Check Content-Length
                NSString *headerStr = [[NSString alloc] initWithData:[requestData subdataWithRange:NSMakeRange(0, range.location)] encoding:NSUTF8StringEncoding];
                NSUInteger contentLength = 0;
                for (NSString *line in [headerStr componentsSeparatedByString:@"\r\n"]) {
                    if ([line.lowercaseString hasPrefix:@"content-length:"]) {
                        contentLength = [[line substringFromIndex:15] integerValue];
                    }
                }
                NSUInteger bodyStart = range.location + 4;
                while (requestData.length < bodyStart + contentLength) {
                    n = read(clientFd, buffer, sizeof(buffer));
                    if (n <= 0) break;
                    [requestData appendBytes:buffer length:n];
                }
                break;
            }
        }
    }

    NSString *requestStr = [[NSString alloc] initWithData:requestData encoding:NSUTF8StringEncoding];
    if (!requestStr) return;

    // Parse request line
    NSArray *lines = [requestStr componentsSeparatedByString:@"\r\n"];
    if (lines.count == 0) return;
    NSArray *requestLine = [lines[0] componentsSeparatedByString:@" "];
    if (requestLine.count < 2) return;

    NSString *method = requestLine[0];
    NSString *rawPath = requestLine[1];
    NSString *path = rawPath;
    NSRange queryRange = [rawPath rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) {
        path = [rawPath substringToIndex:queryRange.location];
    }

    // Extract body
    NSData *body = nil;
    NSRange sepRange = [requestData rangeOfData:headerEnd options:0 range:NSMakeRange(0, requestData.length)];
    if (sepRange.location != NSNotFound) {
        NSUInteger bodyStart = sepRange.location + 4;
        if (bodyStart < requestData.length) {
            body = [requestData subdataWithRange:NSMakeRange(bodyStart, requestData.length - bodyStart)];
        } else {
            body = [NSData data];
        }
    }

    NSData *responseData = [self.delegate handleRequest:method path:path body:body];
    if (!responseData) responseData = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];

    NSString *responseHeader = [NSString stringWithFormat:
        @"HTTP/1.1 200 OK\r\n"
        @"Content-Type: application/json\r\n"
        @"Content-Length: %lu\r\n"
        @"Connection: close\r\n"
        @"\r\n", (unsigned long)responseData.length];
    NSData *headerData = [responseHeader dataUsingEncoding:NSUTF8StringEncoding];
    write(clientFd, headerData.bytes, headerData.length);
    write(clientFd, responseData.bytes, responseData.length);
}

@end
