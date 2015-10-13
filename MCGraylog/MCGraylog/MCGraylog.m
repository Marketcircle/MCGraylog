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

void graylog_deinit(void);
GraylogLogLevel graylog_log_level(void);
dispatch_queue_t graylog_queue(void);
void graylog_flush(void);


static GraylogLogLevel max_log_level       = GraylogLogLevelDebug;
static dispatch_queue_t _graylog_queue     = NULL;
static int   graylog_socket                = -1;
static const uLong max_chunk_size          = 8192;
static const Byte  chunked[2]              = {0x1e, 0x0f};
static const uint16_t graylog_default_port = 12201;
static const int chunked_size              = 2;

static NSString* hostname = nil;

static NSString* const GraylogFacilityKey = @"_facility";

#define P1 7
#define P2 31

#define likely(x) __builtin_expect(x, 1)
#define unlikely(x) __builtin_expect(x, 0)


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
    char name[255];
    if (gethostname(name, sizeof(name)) == -1) {
        NSLog(@"gethostname wants to return a hostname that is way too long (%d): %@",
              errno, @(strerror(errno)));
        return -1;
    }

    hostname = @(name);

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
    CFStringRef const host_string = (__bridge CFStringRef)(graylog_url.host);
    
    // try to resolve the hostname
    CFHostRef const host = CFHostCreateWithName(kCFAllocatorDefault, host_string);
    
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
    

    const CFIndex addresses_count = CFArrayGetCount(addresses);
    
    for (CFIndex i = 0; i < addresses_count; i++) {
        
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
                                           DISPATCH_QUEUE_SERIAL);
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


void
graylog_deinit()
{
    graylog_flush();
    _graylog_queue = NULL;

    if (graylog_socket != -1) {
        if (close(graylog_socket) == -1)
            NSLog(@"Graylog: failed to close socket: %@",
                  [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
        graylog_socket = -1;
    }

    // anything sent to Graylog after deinit will get logged
    // and in graylog_log it should end up going to NSLog
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
NSDictionary*
message_dictionary(const GraylogLogLevel lvl,
                   __unsafe_unretained NSString* const facility,
                   __unsafe_unretained NSString* const message,
                   __unsafe_unretained NSNumber* const timestamp,
                   __unsafe_unretained NSDictionary* const xtra_data)
{
    NSMutableDictionary* const dict =
        [NSMutableDictionary dictionaryWithCapacity:(xtra_data.count + 6)];

    dict[@"version"]         = @"1.1";
    dict[@"host"]            = hostname;
    dict[@"short_message"]   = message;
    dict[@"timestamp"]       = timestamp;
    dict[@"level"]           = @(lvl);
    dict[GraylogFacilityKey] = facility;

    for (NSString* key in xtra_data) {
        NSCAssert(![key isEqualToString:@"id"],
                  @"_id is a reserved graylog attribute: %@, %@", message, xtra_data);
        NSCAssert(![key isEqualToString:@"_id"],
                  @"_id is a reserved graylog attribute: %@, %@", message, xtra_data);

        if ([key hasPrefix:@"_"]) {
            dict[key] = xtra_data[key];
        }
        else if ([key isEqualToString:@"full_message"]) {
            dict[key] = xtra_data[key];
        }
        else {
            dict[[@"_" stringByAppendingString:key]] = xtra_data[key];
        }
    }

    return dict;
}

static
int
compress_message(__unsafe_unretained NSDictionary* const message,
                 uint8_t** const deflated_message,
                 size_t* const deflated_message_size)
{
    NSError* error = nil;
    NSData*   data = nil;
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        data = [NSJSONSerialization dataWithJSONObject:message
                                               options:0
                                                 error:&error];
#pragma clang diagnostic pop
    }
    @catch (NSException* exception) {
        GRAYLOG_ERROR(message[GraylogFacilityKey],
                      @"Failed to serialize message: %@", exception);
        return -3;
    }

    if (unlikely(error != nil)) {
        // hopefully this doesn't fail as well...
        GRAYLOG_ERROR(message[GraylogFacilityKey],
                      @"Failed to serialize message: %@", error);
        return -2;
    }

    const NSUInteger length = data.length;
    *deflated_message_size  = compressBound(length);
    *deflated_message       = malloc(*deflated_message_size);

    // predict size first, then use that value for output buffer
    const int result = compress(*deflated_message,
                                deflated_message_size,
                                data.bytes,
                                length);

    if (unlikely(result != Z_OK)) {
        // hopefully this doesn't fail...
        GRAYLOG_ERROR(message[GraylogFacilityKey],
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

    const char* const utf8_name = hostname.UTF8String;

    // calculate hash
    for (const char* p = utf8_name; *p; ++p)
        hash = hash * P2 + (uint64_t)*p;

    size_t current_time = mach_absolute_time();
    do {
        const size_t digit = current_time % 10;
        current_time /= 10;
        hash = hash * P2 + digit;
    } while (current_time);

    return hash;
}


static
int
send_chunk(const uint8_t* const message, const size_t message_size)
{
    const ssize_t send_result =
        send(graylog_socket, message, message_size, 0);

    if (likely(send_result == (ssize_t)message_size))
        return 0;

    NSCAssert(send_result == -1,
              @"Graylog message was truncated. "
               "Some kind of implementation error. %zd/%zd",
              send_result,
              message_size);

    if (errno == ENOBUFS) {
        NSLog(@"Failed to send(2) to Graylog due to transient issue, "
               "trying again in 2 seconds");
        sleep(2);
        return send_chunk(message, message_size);
    }

    NSLog(@"Failed to send(2) to Graylog (%d): %@", errno, @(strerror(errno)));
    return errno;
}

static
int
send_log(uint8_t* const message, const size_t message_size)
{
    // calculate the number of chunks that we will need to make
    uLong chunk_count = message_size / max_chunk_size;
    if (message_size % max_chunk_size)
        ++chunk_count;

    // in the most likely case, we only need one message chunk,
    // so we have a fast path for that case
    if (chunk_count == 1)
        return send_chunk(message, message_size);

    if (chunk_count > 128) {
        NSLog(@"Failed to send to Graylog: too many chunks (max 128, got %lu)", chunk_count);
        return EMSGSIZE;
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

        // do this or we overwrite header at appendBytes:length:
        chunk.length = sizeof(graylog_header);

        graylog_header* header = chunk.mutableBytes;
        memcpy(&header->chunked,    &chunked, chunked_size);
        memcpy(&header->message_id, &hash,    sizeof(message_id_t));
        header->sequence = (Byte)i;
        header->total    = (Byte)chunk_count;
            
        [chunk appendBytes:(message + (i*max_chunk_size))
                    length:bytes_to_copy];

        const int result = send_chunk((const uint8_t*)header, chunk_length);
        if (result != 0)
            return result;
    }

    return 0;
}

void
_graylog_log(const GraylogLogLevel level,
             __unsafe_unretained NSString* const facility,
             __unsafe_unretained NSString* const message,
             __unsafe_unretained NSNumber* const timestamp,
             __unsafe_unretained NSDictionary* const data)
{
    NSDictionary* const formatted_message = message_dictionary(level,
                                                               facility,
                                                               message,
                                                               timestamp,
                                                               data);

    uint8_t* compressed_message      = NULL;
    size_t   compressed_message_size = 0;
    const int compress_result = compress_message(formatted_message,
                                                 &compressed_message,
                                                 &compressed_message_size);
    if (unlikely(compress_result != 0)) {
        NSString* const uuid = NSUUID.UUID.UUIDString;
        GRAYLOG_ALERT(facility,
                      @"Failed to compress message for Graylog. "
                      @"Logged to asl instead, look for %@",
                      uuid);
        NSLog(@"MCGraylog [%@]: %@", uuid, message);
        return;
    }

    if (compressed_message_size > (1 * 1024 * 1024)) {
        free(compressed_message); // don't forget!

        NSString* const uuid = NSUUID.UUID.UUIDString;
        GRAYLOG_ALERT(facility,
                      @"Aborted sending message that was too long (%zd). "
                      @"Logged to ASL instead, look for %@",
                      compressed_message_size,
                      uuid);
        NSLog(@"MCGraylog [%@]: %@", uuid, message);
        return;
    }

    const int result = send_log(compressed_message, compressed_message_size);
    free(compressed_message); // don't forget!

    if (result != 0) {
        // do not try to alert graylog, as that might lead to an infinite loop
        NSLog(@"MCGraylog (%@): %@", @(strerror(result)), message);
    }
}


void
graylog_log(const GraylogLogLevel level,
            NSString* const facility,
            NSString* const message,
            NSDictionary* const data)
{
    // ignore messages that are not important enough to log
    if (level > max_log_level) return;
    
    if (_graylog_queue == NULL) {
        NSLog(@"Graylog[%@] %@\nuserInfo=%@", facility, message, data);
        return;
    }

    // this needs to be done before going async, we don't know when
    // the log block will actually execute
    NSNumber* const stamp = @(time(NULL));

    dispatch_async(_graylog_queue, ^{ @autoreleasepool {
        _graylog_log(level, facility, message, stamp, data);
    } });
}

void
graylog_log2(const GraylogLogLevel level,
             NSString* const facility,
             NSString* const short_message,
             NSString* const full_message,
             NSDictionary* const data)
{
    if (data) {
        NSMutableDictionary* const info = data.mutableCopy;
        info[@"full_message"] = full_message;
        graylog_log(level, facility, short_message, info);
    }
    else {
        graylog_log(level, facility, short_message, @{ @"full_message": full_message });
    }
}


static void empty_func(__unused void* const ctx) {}


void
graylog_flush()
{
    if (_graylog_queue == NULL) return;
    dispatch_barrier_sync_f(_graylog_queue, NULL, empty_func);
}
