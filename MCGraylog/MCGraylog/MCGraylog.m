//
//  MCGraylog.m
//  MCGraylog
//
//  Created by Jordan on 2013-05-06.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import "MCGraylog.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <zlib.h>
#include <netdb.h>
#include <sys/time.h>

static GraylogLogLevel max_log_level        = GraylogLogLevelDebug;
static dispatch_queue_t graylog_queue       = NULL;
static CFSocketRef graylog_socket           = NULL;
static NSMutableDictionary* base_dictionary = nil;
static NSString* hostname                   = nil;
static const uLong max_chunk_size           = 65507;
static const Byte  chunked[2]               = {0x1e, 0x0f};


NSString* const MCGraylogLogFacility = @"mcgraylog";
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
graylog_init(const char* address,
             const char* port,
             GraylogLogLevel init_level)
{
    graylog_queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND,
                                              0);

    graylog_socket = CFSocketCreate(kCFAllocatorDefault,
                                    PF_INET,
                                    SOCK_DGRAM,
                                    IPPROTO_UDP,
                                    kCFSocketNoCallBack,
                                    NULL, // callback function
                                    NULL); // callback context

    
    // TODO: handle IPv6 addresses...
    struct addrinfo* graylog_info = NULL;

    int getaddr_result = getaddrinfo(address, port, NULL, &graylog_info);
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
    graylog_address.sin_port        = htons(atoi(port));

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

    // TODO: this is an ugly hack that we should fix up
    hostname = [[NSHost currentHost] localizedName];
    if (!hostname) {
        NSLog(@"MCGraylog: Failed to determine hostname");
        graylog_deinit();
        return -1;
    }
    
    base_dictionary = [@{
                         @"version": @"1.0",
                         @"host": hostname,
                        } mutableCopy];
    
    max_log_level = init_level;
    
    return 0; // successfully completed!
}


void
graylog_deinit()
{
    graylog_queue = NULL;
    
    if (graylog_socket) {
        CFSocketInvalidate(graylog_socket);
        CFRelease(graylog_socket);
        graylog_socket = NULL;
    }
    
    if (base_dictionary) {
        base_dictionary = nil;
    }
    
    if (hostname) {
        hostname = nil;
    }
    
    max_log_level = GraylogLogLevelDebug;
}


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


static
NSData*
format_message(GraylogLogLevel lvl,
               NSString* facility,
               NSString* message,
               NSDictionary* xtra_data)
{
    NSMutableDictionary* dictionary = [base_dictionary mutableCopy];
    dictionary[@"timestamp"]     = @([[NSDate date] timeIntervalSince1970]);
    dictionary[@"level"]         = @(lvl);
    dictionary[@"facility"]      = facility;
    dictionary[@"short_message"] = message;
    
    [xtra_data enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL* stop) {
        if (![key isEqual: @"id"])
            dictionary[[NSString stringWithFormat:@"_%@", key]] = obj;
    }];
    

    NSError* error = nil;
    NSData*   data = [NSJSONSerialization dataWithJSONObject:dictionary
                                                           options:0
                                                             error:&error];
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
        free(deflated_message);
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
    
    NSString* base_hash =
    [hostname stringByAppendingString:[@(time.tv_usec) stringValue]];
    
    const char* message_string =
    [base_hash cStringUsingEncoding:NSUTF8StringEncoding];
    
    // calculate hash
    uint64 hash = P1;
    for (const char* p = message_string; *p != 0; p++)
        hash = hash * P2 + *p;

    // calculate the number of chunks that we will need to make
    uLong chunk_count = message_size / max_chunk_size;
    if (message_size % max_chunk_size)
        chunk_count++;

    size_t remain = message_size;
    for (int i = 0; i < chunk_count; i++) {
        char*  chunk         = malloc(max_chunk_size);
        size_t bytes_to_copy = MIN(remain, max_chunk_size);
        memcpy(chunk, message + (i * max_chunk_size), bytes_to_copy);
        remain -= bytes_to_copy;
        
        NSData *chunkData = [NSData dataWithBytesNoCopy:chunk
                                                 length:bytes_to_copy
                                           freeWhenDone:YES];
        
        // Append chunk header if we're sending multiple chunks
        if (chunk_count > 1) {
            
            graylog_header* header = malloc(sizeof(graylog_header));
            memcpy(header->message_id, &hash, sizeof(message_id_t));
            memcpy(header->chunked, &chunked, CHUNKED_SIZE);
            header->sequence = (Byte)i;
            header->total    = (Byte)chunk_count;
            
            NSMutableData* chunkHeader = [NSMutableData dataWithBytes:header
                                                               length:12];
            [chunkHeader appendData:chunkData];
            chunkData = chunkHeader;
        }

        CFSocketError send_error = CFSocketSendData(graylog_socket,
                                                    NULL,
                                                    (__bridge CFDataRef)chunkData,
                                                    1);
        if (send_error)
            GRAYLOG_ERROR(MCGraylogLogFacility,
                          @"SendData failed: %ldl", send_error);
        
    }

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
    
    dispatch_async(graylog_queue, ^() {

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
    });
}
