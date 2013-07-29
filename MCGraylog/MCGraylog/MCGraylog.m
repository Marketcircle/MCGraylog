//
//  MCGraylog.m
//  MCGraylog
//
//  Created by Jordan on 2013-05-06.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import "MCGraylog.h"
#import "Private/MCGraylog+Private.h"
#import "Private/NSURL+MCGraylog.h"

#import <Availability.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <zlib.h>
#import <netdb.h>
#import <sys/time.h>

NSString* const MCGraylogDefaultFacility = @"MCGraylog";
const size_t MCGraylogDefaultPort = 12201;
const GraylogLogLevel MCGraylogDefaultLogLevel = GraylogLogLevelDebug;

static const uLong MCGraylogMaxChunkSize = 65507;
static const Byte  chunked[2]            = {0x1e, 0x0f};

#define CHUNKED_SIZE 2
#define P1 7
#define P2 31

typedef Byte message_id_t[8];

typedef struct {
    Byte chunked[2];
    message_id_t message_id;
    Byte sequence;
    Byte total;
} graylog_header;



@implementation MCGraylog

+ (MCGraylog*)logger
{
    return [self loggerWithLevel:MCGraylogDefaultLogLevel];
}

+ (MCGraylog*)loggerWithLevel:(GraylogLogLevel)initLevel
{
    return [self loggerWithLevel:initLevel
                 toGraylogServer:[NSURL localhost:MCGraylogDefaultPort]];
}

+ (MCGraylog*)loggerWithLevel:(GraylogLogLevel)initLevel
              toGraylogServer:(NSURL*)host
{
    return [self loggerWithLevel:initLevel
                 toGraylogServer:host
                      asFacility:MCGraylogDefaultFacility];
}

+ (MCGraylog*)loggerWithLevel:(GraylogLogLevel)initLevel
              toGraylogServer:(NSURL*)host
                   asFacility:(NSString*)facility
{
    return [self loggerWithLevel:initLevel
                 toGraylogServer:host
                      asFacility:facility
                    asynchronous:YES];
}

+ (MCGraylog*)loggerWithLevel:(GraylogLogLevel)initLevel
              toGraylogServer:(NSURL*)host
                   asFacility:(NSString*)facility
                 asynchronous:(BOOL)async
{
    NSError* error = nil;
    MCGraylog* logger = [[self alloc] initWithLevel:initLevel
                                    toGraylogServer:host
                                         asFacility:facility
                                       asynchronous:async
                                              error:&error];

    NSAssert(logger, @"Failed to initialize logger: %@", error);
    
    return logger;
}


- (id) initWithLevel:(GraylogLogLevel)initLevel
     toGraylogServer:(NSURL*)host
          asFacility:(NSString*)facility
        asynchronous:(BOOL)async
               error:(NSError**)error;
{
    if (![super init]) return nil;
    
    const char* address = [host.host cStringUsingEncoding:NSUTF8StringEncoding];
    if (!address) {
        *error = [NSError errorWithDomain:NSArgumentDomain
                                     code:0
                                 userInfo:@{@"reason": @"nil/empty address"}];
        return nil;
    }
    
    
    // for the port number, if nothing was specified, we can just use the
    // default Graylog port number
    NSNumber* port = host.port;
    if (!port)
        port = @(MCGraylogDefaultPort);
    
    if (!facility || !facility.length) {
        *error = [NSError errorWithDomain:NSArgumentDomain
                                     code:0
                                 userInfo:@{@"reason": @"nil/empty facility"}];
        return nil;
    }
    
    self->_facility = facility;
    
    
    // TODO: find out why I can't call dispatch_barrier_sync on a global queue
    if (async) {
        const char* qname =
        [[NSString stringWithFormat:@"com.marketcircle.graylog.%@", facility]
         cStringUsingEncoding:NSUTF8StringEncoding];
        
        self->queue = dispatch_queue_create(qname, DISPATCH_QUEUE_CONCURRENT);
        
        if (!self->queue) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:ENOMEM
                                     userInfo:nil];
            return nil;
        }
    }
    
    self->socket = CFSocketCreate(kCFAllocatorDefault,
                                  PF_INET,
                                  SOCK_DGRAM,
                                  IPPROTO_UDP,
                                  kCFSocketNoCallBack,
                                  NULL, // callback function
                                  NULL); // callback context
    if (!self->socket) {
        // in production, we should only have errors because
        // of ENOMEM, but this error might be caused by something
        // else
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                     code:ENOMEM
                                 userInfo:nil];
        return nil;
    }

    // TODO: handle IPv6 addresses...

    const char* port_str =
    [port.stringValue cStringUsingEncoding:NSASCIIStringEncoding];

    struct addrinfo* graylog_info = NULL;
    int getaddr_result = getaddrinfo(address, port_str, NULL, &graylog_info);
    if (getaddr_result) {
        
        NSString* message =
        [NSString stringWithCString:gai_strerror(getaddr_result)
                           encoding:NSUTF8StringEncoding];
        
        *error = [NSError errorWithDomain:@"SocketErrorDomain"
                                     code:0
                                 userInfo:@{@"message": message}];
        return nil;
    }
    
    struct in_addr addr;
    memset(&addr, 0, sizeof(struct in_addr));
    addr.s_addr = ((struct sockaddr_in*)(graylog_info->ai_addr))->sin_addr.s_addr;

    freeaddrinfo(graylog_info); // done with this guy now
    
    struct sockaddr_in graylog_address;
    memset(&graylog_address, 0, sizeof(struct sockaddr_in));
    graylog_address.sin_family      = AF_INET;
    graylog_address.sin_addr.s_addr = inet_addr(inet_ntoa(addr));
    graylog_address.sin_port        = htons(port.integerValue);

    CFDataRef address_data = CFDataCreate(kCFAllocatorDefault,
                                          (const uint8_t*)&graylog_address,
                                          sizeof(struct sockaddr_in));

    // timeout of 1 because we aren't actually connecting to anything
    CFSocketError connection_error = CFSocketConnectToAddress(self->socket,
                                                              address_data,
                                                              1);
    CFRelease(address_data); // done with this guy now
    
    if (connection_error != kCFSocketSuccess) {
        *error = [NSError errorWithDomain:@"SocketErrorDomain"
                                     code:0
                                 userInfo:@{@"message":
                                                @"Failed to bind socket"}];
        return nil;
    }

    self.maximumLevel = initLevel;
    
    return self;
}


- (void) dealloc {

#if __MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_8
    if (self->queue)
        dispatch_release(self->queue);
#endif
    
    if (self->socket) {
        CFSocketInvalidate(self->socket);
        CFRelease(self->socket);
    }
    
}


static
NSData*
format_message(MCGraylog* self,
               GraylogLogLevel level,
               NSString* message,
               NSDictionary* xtra_data)
{
    NSMutableDictionary* dictionary =
    [NSMutableDictionary dictionaryWithCapacity:8];
    
    dictionary[@"version"]       = @"1.0";
    dictionary[@"host"]          = NSHost.currentHost.localizedName;
    dictionary[@"timestamp"]     = @([[NSDate date] timeIntervalSince1970]);
    dictionary[@"level"]         = @(level),
    dictionary[@"facility"]      = self->_facility;
    dictionary[@"short_message"] = message;

    [xtra_data enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL* stop) {
        // TODO: do we just want to silently ignore the @"id" key?
        if (![key isEqual: @"id"])
            dictionary[[NSString stringWithFormat:@"_%@", key]] = obj;
    }];
    

    NSError* error = nil;
    NSData*   data = nil;
    @try {
        data = [NSJSONSerialization dataWithJSONObject:dictionary
                                               options:0
                                                 error:&error];
    }
    @catch (NSException* exception) {
        [self log:GraylogLogLevelError
          message:@"Logger failed to serialize message: %@", exception];
        return nil;
    }
    
    if (error) {
        [self log:GraylogLogLevelError
          message:@"Logger failed to serialize message: %@", error];
        return nil;
    }

    return data;
}


static
int
compress_message(MCGraylog* self,
                 NSData* message,
                 uint8_t** deflated_message,
                 size_t* deflated_message_size)
{
    // predict size first, then use that value for output buffer
    *deflated_message_size = compressBound([message length]);
    *deflated_message      = malloc(*deflated_message_size);

    int result = compress(*deflated_message,
                          deflated_message_size,
                          [message bytes],
                          [message length]);
    
    if (result != Z_OK) {
        [self log:GraylogLogLevelError
          message:@"Logger failed to compress message: %d", result];
        free(*deflated_message);
        return -1;
    }
    
    return 0;
}


static
void
send_log(MCGraylog* self,
         uint8_t* message,
         size_t message_size)
{
    // First, generate a message_id hash from hostname and a timestamp;

    // skip error check, only EFAULT is documented for this function
    // and it cannot be given since we are using memory on the stack
    struct timeval time;
    gettimeofday(&time, NULL);
    
    const char* message_string =
    [[NSHost.currentHost.localizedName
     stringByAppendingString:[@(time.tv_usec) stringValue]]
     cStringUsingEncoding:NSUTF8StringEncoding];
    
    // probably can't log to graylog at this point, just use NSLog
    if (!message_string) {
        NSLog(@"%@ Logger failed to generate a hash", self->_facility);
        return;
    }
    
    // calculate hash
    uint64 hash = P1;
    for (const char* p = message_string; *p; p++)
        hash = hash * P2 + *p;

    // calculate the number of chunks that we will need to make
    uLong chunk_count = message_size / MCGraylogMaxChunkSize;
    if (message_size % MCGraylogMaxChunkSize)
        chunk_count++;

    size_t remain = message_size;
    for (int i = 0; i < chunk_count; i++) {
        size_t bytes_to_copy = MIN(remain, MCGraylogMaxChunkSize);
        remain -= bytes_to_copy;

        NSData* chunk =
        [NSData dataWithBytesNoCopy:(message + (i * MCGraylogMaxChunkSize))
                             length:bytes_to_copy
                       freeWhenDone:NO];
        
        // Append chunk header if we're sending multiple chunks
        if (chunk_count > 1) {
            
            graylog_header header;
            memcpy(&header.message_id, &hash, sizeof(message_id_t));
            memcpy(&header.chunked, &chunked, CHUNKED_SIZE);
            header.sequence = (Byte)i;
            header.total    = (Byte)chunk_count;
            
            NSMutableData* new_chunk = [[NSMutableData alloc]
                initWithCapacity:(sizeof(graylog_header) + chunk.length)];
            [new_chunk appendBytes:&header length:sizeof(graylog_header)];
            [new_chunk appendData:chunk];
            chunk = new_chunk;
        }

        CFSocketError send_error = CFSocketSendData(self->socket,
                                                    NULL,
                                                    (__bridge CFDataRef)chunk,
                                                    1);
        if (send_error)
            NSLog(@"%@ Logger failed to send to graylog server: %ld",
                  self->_facility,
                  send_error);
        
    }

}


static
void
graylog_log(MCGraylog* self,
            GraylogLogLevel level,
            NSString* message,
            NSDictionary* data)
{
    NSData* formatted_message = format_message(self,
                                               level,
                                               message,
                                               data);
    if (!formatted_message)
        return;
    
    uint8_t* compressed_message      = NULL;
    size_t   compressed_message_size = 0;
    int compress_result = compress_message(self,
                                           formatted_message,
                                           &compressed_message,
                                           &compressed_message_size);
    if (compress_result)
        return;
    
    send_log(self, compressed_message, compressed_message_size);
    
    free(compressed_message); // don't forget!
}


- (void) log:(GraylogLogLevel)level message:(NSString *)message, ... {
    va_list args;
    [self log:level
      message:[[NSString alloc] initWithFormat:message arguments:args]
         data:nil];
}


- (void) log:(GraylogLogLevel)level
     message:(NSString *)message
        data:(NSDictionary *)data {
    
    // ignore messages that are not important enough to log
    if (level > self->_maximumLevel) return;
    
    NSAssert(message, @"Message cannot be nil");
    
    if (self->queue)
        dispatch_async(self->queue, ^() {
            graylog_log(self, level, message, data);
        });
    else
        graylog_log(self, level, message, data);
}


@end
