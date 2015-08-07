//
//  MCGraylog.m
//  MCGraylog
//
//  Created by Jordan on 2013-05-06.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import "MCGraylog.h"
#import "Private Headers/Internals.h"

@import Darwin.Availability;
@import Darwin.POSIX.sys.socket;
@import Darwin.POSIX.netinet.in;
@import Darwin.POSIX.arpa.inet;
@import Darwin.POSIX.netdb;
@import Darwin.POSIX.sys.time;

#import <zlib.h>

static GraylogLogLevel max_log_level       = GraylogLogLevelDebug;
static dispatch_queue_t _graylog_queue     = NULL;
static int   graylog_socket                = -1;
static const uLong max_chunk_size          = 65507;
static const Byte  chunked[2]              = {0x1e, 0x0f};
static const uint16_t graylog_default_port = 12201;
static const int chunked_size              = 2;

static NSString* const MCGraylogLogFacility = @"mcgraylog";

#define P1 7
#define P2 31


typedef Byte message_id_t[8];

typedef struct {
    Byte chunked[2];
    message_id_t message_id;
    Byte sequence;
    Byte total;
} graylog_header;


#pragma mark - Init

static
int
graylog_init_socket(NSURL* const graylog_url)
{
    // get the host name string
    if (!graylog_url.host) {
        NSLog(@"nil address given as graylog_url");
        return -1;
    }
    
    // get the port number
    int port = graylog_url.port.intValue;
    if (!port)
        port = graylog_default_port;
    
    // need to cast the host to a CFStringRef for the next part
    CFStringRef const hostname = (__bridge CFStringRef)(graylog_url.host);
    
    // try to resolve the hostname
    CFHostRef const host = CFHostCreateWithName(kCFAllocatorDefault, hostname);
    
    if (!host) {
        NSLog(@"Could not allocate CFHost to lookup IP address of graylog");
        return -1;
    }
    
    CFStreamError stream_error;
    if (!CFHostStartInfoResolution(host, kCFHostAddresses, &stream_error)) {
        NSLog(@"Failed to resolve IP address for %@ [%ld, %d]",
              graylog_url, stream_error.domain, stream_error.error);
        CFRelease(host);
        return -1;
    }
    
    Boolean has_been_resolved = false;
    CFArrayRef const addresses = CFHostGetAddressing(host, &has_been_resolved);
    if (!has_been_resolved) {
        NSLog(@"Failed to get addresses for %@", graylog_url);
        CFRelease(host);
        return -1;
    }
    

    const size_t addresses_count = CFArrayGetCount(addresses);
    
    for (size_t i = 0; i < addresses_count; i++) {
        
        CFDataRef const address =
            (CFDataRef)CFArrayGetValueAtIndex(addresses, i);

        const socklen_t address_length = (socklen_t)CFDataGetLength(address);
        const int pf_version =
            address_length == sizeof(struct sockaddr_in6) ? PF_INET6 : PF_INET;

        struct sockaddr_in6 addr;
        memcpy(&addr, CFDataGetBytePtr(address), address_length);
        addr.sin6_port = htons(port);

        graylog_socket = socket(pf_version, SOCK_DGRAM, IPPROTO_UDP);

        if (graylog_socket == -1) {
            NSLog(@"Failed to allocate socket for graylog: %@", @(strerror(errno)));
            CFRelease(host);
            return -1;
        }
        
        const int connect_result =
            connect(graylog_socket, (struct sockaddr*)&addr, address_length);

        if (connect_result == -1) {
            if (i == (addresses_count - 1))
                NSLog(@"Failed to connect to all addresses of %@", graylog_url);

            NSLog(@"Failed to connect to address of %@ (%d): %@",
                  graylog_url, errno, @(strerror(errno)));

            close(graylog_socket);
            graylog_socket = -1;
            continue;
        }

        CFRelease(host);
        return 0;
    }
    
    
    CFRelease(host);
    return -1;
}


int
graylog_init(NSURL* const graylog_url, const GraylogLogLevel init_level)
{
    // must create our own concurrent queue radar://14611706
    _graylog_queue = dispatch_queue_create("com.marketcircle.graylog",
                                           DISPATCH_QUEUE_CONCURRENT);
    if (!_graylog_queue) {
        graylog_deinit();
        return -1;
    }
    
    max_log_level = init_level;

    if (graylog_init_socket(graylog_url) == -1) {
        graylog_deinit();
        return -1;
    }
    
    return 0;
}

static void empty_func(__unused void* const ctx) {}

void
graylog_deinit()
{
    if (_graylog_queue) {
        dispatch_barrier_sync_f(_graylog_queue, NULL, empty_func);
        _graylog_queue = NULL;
    }
    
    if (graylog_socket != -1) {
        close(graylog_socket);
        graylog_socket = -1;
    }
    
    max_log_level = GraylogLogLevelDebug;
}


#pragma mark - Accessors

GraylogLogLevel
graylog_log_level()
{
    return max_log_level;
}


void
graylog_set_log_level(const GraylogLogLevel new_level)
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
format_message(const GraylogLogLevel lvl,
               NSString* const facility,
               NSString* const message,
               NSDictionary* const xtra_data)
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:8];

    dict[@"version"]       = @"1.0";
    dict[@"host"]          = NSHost.currentHost.localizedName;
    dict[@"timestamp"]     = @(time(NULL));
    dict[@"facility"]      = facility;
    dict[@"level"]         = @(lvl);
    dict[@"short_message"] = message;
    
    [xtra_data enumerateKeysAndObjectsUsingBlock:
        ^(const id key, const id obj, BOOL* const stop) {
            if ([key isEqual: @"id"])
                dict[@"_userInfo_id"] = obj;
            else
                dict[[NSString stringWithFormat:@"_%@", key]] = obj;
        }];
    

    NSError* error = nil;
    NSData*   data = nil;
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        data = [NSJSONSerialization dataWithJSONObject:dict
                                               options:0
                                                 error:&error];
#pragma clang diagnostic pop
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
compress_message(NSData* const message,
                 uint8_t** const deflated_message,
                 size_t* const deflated_message_size)
{
    // predict size first, then use that value for output buffer
    *deflated_message_size = compressBound([message length]);
    *deflated_message      = malloc(*deflated_message_size);

    const int result = compress(*deflated_message,
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


// the hashing algorithm suggested by Graylog documenation
// for use in graylog_headers
static
uint64_t
graylog_hash()
{
    uint64_t hash = P1;

    NSString* const name = NSHost.currentHost.localizedName;
    const char* const utf8_name = name.UTF8String;

    // skip error check, only EFAULT is documented for this function
    // and it cannot be given since we are using memory on the stack
    struct timeval time;
    gettimeofday(&time, NULL);
    char time_str[16];
    snprintf(time_str, sizeof(time_str), "%d", time.tv_usec);

    // calculate hash
    for (const char* p = utf8_name; *p; ++p)
        hash = hash * P2 + *p;
    for (const char* p = time_str; *p; ++p)
        hash = hash * P2 + *p;

    return hash;
}


static
void
send_log(uint8_t* const message, const size_t message_size)
{
    // calculate the number of chunks that we will need to make
    uLong chunk_count = message_size / max_chunk_size;
    if (message_size % max_chunk_size)
        ++chunk_count;

    // in the most likely case, we only need one message chunk,
    // so we have a fast path for that case
    if (chunk_count == 1) {
        ssize_t send_result = send(graylog_socket, message, message_size, 0);
        if (send_result == -1)
            NSLog(@"Failed to send log to Graylog (%d): %@", errno, @(strerror(errno)));
        return;
    }

    // in the less likely case, we need to break the message up
    // and wish that we were using TCP instead of UDP, but whatevs

    const uint64_t hash = graylog_hash();
    size_t remain = message_size;

    for (uLong i = 0; i < chunk_count; ++i) {
        size_t bytes_to_copy = MIN(remain, max_chunk_size);
        remain -= bytes_to_copy;

        const size_t chunk_length = sizeof(graylog_header) + bytes_to_copy;
        NSMutableData* const chunk =
            [[NSMutableData alloc] initWithCapacity:chunk_length];

        graylog_header* header = chunk.mutableBytes;
        memcpy(&header->chunked,    &chunked, chunked_size);
        memcpy(&header->message_id, &hash,    sizeof(message_id_t));
        header->sequence = (Byte)i;
        header->total    = (Byte)chunk_count;
            
        [chunk appendBytes:(message + (i*max_chunk_size))
                    length:bytes_to_copy];

        const ssize_t send_result =
            send(graylog_socket, header, chunk_length, 0);

        if (send_result == -1)
            NSLog(@"Failed to send log to Graylog (%d): %@", errno, @(strerror(errno)));
    }
}


void
_graylog_log(const GraylogLogLevel level,
             __unsafe_unretained NSString* const facility,
             __unsafe_unretained NSString* const message,
             __unsafe_unretained NSDictionary* const data)
{
    NSData* const formatted_message = format_message(level,
                                                     facility,
                                                     message,
                                                     data);
    if (!formatted_message) return;

    uint8_t* compressed_message      = NULL;
    size_t   compressed_message_size = 0;
    const int compress_result =
    compress_message(formatted_message,
                     &compressed_message,
                     &compressed_message_size);
    if (compress_result) return;

    send_log(compressed_message, compressed_message_size);

    free(compressed_message); // don't forget!
}


void
graylog_log(const GraylogLogLevel level,
            NSString* const facility,
            NSString* const message,
            NSDictionary* const data)
{
    // ignore messages that are not important enough to log
    if (level > max_log_level) return;
    
    if (!(facility && message))
        [NSException raise:NSInvalidArgumentException
                    format:@"Facility: %@; Message: %@", facility, message];

    if (_graylog_queue == NULL) {
        NSLog(@"Graylog: %@: %@\nuserInfo=%@", facility, message, data);
        return;
    }

    dispatch_async(_graylog_queue, ^{ _graylog_log(level, facility, message, data); });
}
