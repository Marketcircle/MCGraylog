//
//  MCGraylog.m
//  MCGraylog
//
//  Created by Jordan on 2013-05-06.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import "MCGraylog.h"
#import "Private Headers/Internals.h"

#import <Availability.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <zlib.h>
#import <netdb.h>
#import <sys/time.h>


static GraylogLogLevel max_log_level   = GraylogLogLevelDebug;
static dispatch_queue_t _graylog_queue = NULL;
static CFSocketRef graylog_socket      = NULL;
static const uLong max_chunk_size      = 65507;
static const Byte  chunked[2]          = {0x1e, 0x0f};


NSString* const MCGraylogLogFacility = @"mcgraylog";
#define GRAYLOG_DEFAULT_PORT 12201
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


int
graylog_init(NSURL* graylog_url, GraylogLogLevel init_level)
{
    return graylog_init2(graylog_url, init_level, NO);
}


int
graylog_init2(NSURL* graylog_url, GraylogLogLevel init_level, BOOL sync)
{

    const char* address = [[graylog_url host]
                           cStringUsingEncoding:NSUTF8StringEncoding];
    if (!address) {
        NSLog(@"nil address given as graylog_url");
        return -1;
    }
    
    NSNumber* port = [graylog_url port];
    if (!port)
        port = @(GRAYLOG_DEFAULT_PORT);
    
    const char* port_str = [[port stringValue]
                            cStringUsingEncoding:NSASCIIStringEncoding];
    int port_num = [port intValue];
    

    // TODO: find out why I can't call dispatch_barrier_sync on a global queue
    if (!sync)
        _graylog_queue = dispatch_queue_create("com.marketcircle.graylog",
                                               DISPATCH_QUEUE_CONCURRENT);
    
    graylog_socket = CFSocketCreate(kCFAllocatorDefault,
                                    PF_INET,
                                    SOCK_DGRAM,
                                    IPPROTO_UDP,
                                    kCFSocketNoCallBack,
                                    NULL, // callback function
                                    NULL); // callback context

    
    // TODO: handle IPv6 addresses...
    struct addrinfo* graylog_info = NULL;

    int getaddr_result = getaddrinfo(address,
                                     port_str,
                                     NULL,
                                     &graylog_info);
    if (getaddr_result) {
        NSLog(@"MCGraylog: Failed to resolve address for graylog: %s",
              gai_strerror(getaddr_result));
        graylog_deinit();
        return -1;
    }
    
    struct in_addr addr;
    memset(&addr, 0, sizeof(struct in_addr));
    addr.s_addr = ((struct sockaddr_in*)(graylog_info->ai_addr))->sin_addr.s_addr;

    freeaddrinfo(graylog_info); // done with this guy now
    
    struct sockaddr_in graylog_address;
    memset(&graylog_address, 0, sizeof(struct sockaddr_in));
    graylog_address.sin_family      = AF_INET;
    graylog_address.sin_addr.s_addr = inet_addr(inet_ntoa(addr));
    graylog_address.sin_port        = htons(port_num);

    CFDataRef address_data = CFDataCreate(kCFAllocatorDefault,
                                          (const uint8_t*)&graylog_address,
                                          sizeof(struct sockaddr_in));

    CFSocketError connection_error = CFSocketConnectToAddress(graylog_socket,
                                                              address_data,
                                                              1);
    CFRelease(address_data); // done with this guy now
    
    if (connection_error != kCFSocketSuccess) {
        NSLog(@"MCGraylog: Failed to bind socket to server address [%ld]",
              connection_error);
        graylog_deinit();
        return -1;
    }
    
    max_log_level = init_level;

        graylog_deinit();
        return -1;
    }
    
    return 0;
}


void
graylog_deinit()
{
    if (_graylog_queue) {
        dispatch_barrier_sync(_graylog_queue, ^() {});
        DISPATCH_RELEASE(_graylog_queue);
        _graylog_queue = NULL;
    }
    
    if (graylog_socket) {
        CFSocketInvalidate(graylog_socket);
        CFRelease(graylog_socket);
        graylog_socket = NULL;
    }
    
    max_log_level = GraylogLogLevelDebug;
}


#pragma mark Accessors

GraylogLogLevel
graylog_log_level()
{
    return max_log_level;
}


void
graylog_set_log_level(GraylogLogLevel new_level)
{
    max_log_level = new_level;
}


dispatch_queue_t
graylog_queue()
{
    return _graylog_queue;
}


#pragma mark - Logging

static
NSData*
format_message(GraylogLogLevel lvl,
               NSString* facility,
               NSString* message,
               NSDictionary* xtra_data)
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:8];

    dict[@"version"]       = @"1.0";
    dict[@"host"]          = NSHost.currentHost.localizedName;
    dict[@"timestamp"]     = @(NSDate.date.timeIntervalSince1970);
    dict[@"facility"]      = facility;
    dict[@"level"]         = @(lvl);
    dict[@"short_message"] = message;
    
    [xtra_data enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL* stop) {
        if ([key isEqual: @"id"]) {
            GRAYLOG_WARN(MCGraylogLogFacility,
                         @"Ignoring id in userInfo key for log: %@", xtra_data);
        }
        else {
            dict[[NSString stringWithFormat:@"_%@", key]] = obj;
        }
    }];
    

    NSError* error = nil;
    NSData*   data = nil;
    @try {
        data = [NSJSONSerialization dataWithJSONObject:dict
                                               options:0
                                                 error:&error];
    }
    @catch (NSException* exception) {
        GRAYLOG_ERROR(MCGraylogLogFacility,
                      @"Failed to serialize message: %@", exception);
        return nil;
    }
    
    if (error) {
        // hopefully this doesn't fail as well...
        GRAYLOG_ERROR(MCGraylogLogFacility,
                      @"Failed to serialize message: %@", error);
        return nil;
    }

    return data;
}


static
int
compress_message(NSData* message,
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
        // hopefully this doesn't fail...
        GRAYLOG_ERROR(MCGraylogLogFacility,
                      @"Failed to compress message: %d", result);
        free(*deflated_message);
        return -1;
    }
    
    return 0;
}


static
void
send_log(uint8_t* message, size_t message_size)
{
    // First, generate a message_id hash from hostname and a timestamp;

    // skip error check, only EFAULT is documented for this function
    // and it cannot be given since we are using memory on the stack
    struct timeval time;
    gettimeofday(&time, NULL);
    
    NSString* nshash = [NSHost.currentHost.localizedName
                        stringByAppendingString:[@(time.tv_usec) stringValue]];
    const char* chash = [nshash cStringUsingEncoding:NSUTF8StringEncoding];
    
    // calculate hash
    uint64 hash = P1;
    for (const char* p = chash; *p != 0; p++)
        hash = hash * P2 + *p;

    // calculate the number of chunks that we will need to make
    uLong chunk_count = message_size / max_chunk_size;
    if (message_size % max_chunk_size)
        chunk_count++;

    size_t remain = message_size;
    for (int i = 0; i < chunk_count; i++) {
        size_t bytes_to_copy = MIN(remain, max_chunk_size);
        remain -= bytes_to_copy;

        NSData* chunk =
            [NSData dataWithBytesNoCopy:(message + (i*max_chunk_size))
                                 length:bytes_to_copy
                           freeWhenDone:NO];
        
        // Append chunk header if we're sending multiple chunks
        if (chunk_count > 1) {
            
            graylog_header header;
            memcpy(&header.message_id, &hash, sizeof(message_id_t));
            memcpy(&header.chunked, &chunked, CHUNKED_SIZE);
            header.sequence = (Byte)i;
            header.total    = (Byte)chunk_count;
            
            NSMutableData* new_chunk =
                [[NSMutableData alloc]
                    initWithCapacity:(sizeof(graylog_header) + chunk.length)];

            [new_chunk appendBytes:&header length:sizeof(graylog_header)];
            [new_chunk appendData:chunk];
            chunk = new_chunk;
        }

        CFSocketError send_error = CFSocketSendData(graylog_socket,
                                                    NULL,
                                                    (__bridge CFDataRef)chunk,
                                                    1);
        if (send_error)
            GRAYLOG_ERROR(MCGraylogLogFacility,
                          @"SendData failed: %ldl", send_error);
        
    }

}


static
void
_graylog_log(GraylogLogLevel level,
             NSString* facility,
             NSString* message,
             NSDictionary* data)
{
    NSData* formatted_message = format_message(level,
                                               facility,
                                               message,
                                               data);
    if (!formatted_message)
        return;
    
    uint8_t* compressed_message      = NULL;
    size_t   compressed_message_size = 0;
    int compress_result = compress_message(formatted_message,
                                           &compressed_message,
                                           &compressed_message_size);
    if (compress_result)
        return;
    
    send_log(compressed_message, compressed_message_size);
    
    free(compressed_message); // don't forget!
}


void
graylog_log(GraylogLogLevel level,
            NSString* facility,
            NSString* message,
            NSDictionary *data)
{
    // ignore messages that are not important enough to log
    if (level > max_log_level) return;
    
    if (!(facility && message))
        [NSException raise:NSInvalidArgumentException
                    format:@"Facility: %@; Message: %@", facility, message];
    
    if (_graylog_queue)
        dispatch_async(_graylog_queue, ^() {
            _graylog_log(level, facility, message, data);
        });
    else
        _graylog_log(level, facility, message, data);
}
