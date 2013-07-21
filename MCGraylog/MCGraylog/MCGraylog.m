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

static dispatch_queue_t graylog_queue;
static CFSocketRef graylog_socket;
static const uLong max_chunk_size = 65507;

typedef Byte message_id_t[8];

typedef struct {
    Byte chunked[2];
    message_id_t message_id;
    Byte sequence;
    Byte total;
} graylog_header;


static
void
socket_callback(CFSocketRef s,
                CFSocketCallBackType callbackType,
                CFDataRef address,
                const void *data,
                void *info)
{
    NSLog(@"callback stuff...herp derp");
}


void
graylog_init(const char* address,
             const char* port)
{
    graylog_queue = dispatch_queue_create("com.marketcircle.graylog",
                                          DISPATCH_QUEUE_SERIAL);

    graylog_socket = CFSocketCreate(kCFAllocatorDefault, 0, SOCK_DGRAM, IPPROTO_UDP, (kCFSocketConnectCallBack | kCFSocketWriteCallBack), socket_callback, NULL);

    struct addrinfo *res;
    struct in_addr addr;

    getaddrinfo(address, port, NULL, &res);

    addr.s_addr = ((struct sockaddr_in *)(res->ai_addr))->sin_addr.s_addr;
    freeaddrinfo(res);

    char* hostname = inet_ntoa(addr);
    struct sockaddr_in graylog_address;

    graylog_address.sin_len = sizeof(hostname);
    graylog_address.sin_family = AF_INET;
    graylog_address.sin_addr.s_addr = inet_addr(hostname);
    graylog_address.sin_port = htons(atoi(port));

    CFDataRef address_data = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)&graylog_address, sizeof(graylog_address));

    CFSocketError connection_error = CFSocketConnectToAddress(graylog_socket, address_data, -1);

    if (connection_error != kCFSocketSuccess) {

        // Error handling
    }

}

void graylog_log(GraylogLogLevel lvl, const char* facility, const char* msg, NSDictionary *data){
    char hostname[1024];
    hostname[1023] = '\0';
    gethostname(hostname, 1023);

    NSMutableDictionary *graylog_dictionary = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                               @"1.0", @"version",
                                               [NSString stringWithFormat:@"%s", hostname], @"host",
                                               [NSString stringWithFormat:@"%s", msg], @"short_message",
                                               [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]], @"timestamp",
                                               [NSNumber numberWithInt:lvl], @"level",
                                               [NSString stringWithFormat:@"%s", facility], @"facility",
                                               nil
                                               ];

    for (id key in data) {
        if (![key isEqual: @"id"])
            [graylog_dictionary setObject:[data objectForKey:key] forKey:[NSString stringWithFormat:@"_%@",key]];
    }

    NSData *graylog_data = [NSJSONSerialization dataWithJSONObject:graylog_dictionary options:0 error:NULL];

    char *buf = malloc(graylog_data.length);

    z_stream strm;
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    strm.avail_in = (uInt)graylog_data.length;
    strm.next_in = (Bytef *)graylog_data.bytes;
    strm.avail_out = (UInt)graylog_data.length;
    strm.next_out = (Bytef *)buf;

    deflateInit(&strm, Z_DEFAULT_COMPRESSION);
    deflate(&strm, Z_FINISH);
    deflateEnd(&strm);

    dispatch_async(graylog_queue, ^{
        char hostname[1024];
        hostname[1023] = '\0';
        gethostname(hostname, 1023);

        NSMutableDictionary *graylog_dictionary = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                                   @"1.0", @"version",
                                                   [NSString stringWithFormat:@"%s", hostname], @"host",
                                                   [NSString stringWithFormat:@"%s", msg], @"short_message",
                                                   [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]], @"timestamp",
                                                   [NSNumber numberWithInt:lvl], @"level",
                                                   [NSString stringWithFormat:@"%s", facility], @"facility",
                                                   nil
                                                   ];

        for (id key in data) {
            if (![key isEqual: @"id"])
                [graylog_dictionary setObject:[data objectForKey:key] forKey:[NSString stringWithFormat:@"_%@",key]];
        }

        NSData *graylog_data = [NSJSONSerialization dataWithJSONObject:graylog_dictionary options:0 error:NULL];

        char *buf = malloc(graylog_data.length);

        z_stream strm;
        strm.zalloc = Z_NULL;
        strm.zfree = Z_NULL;
        strm.opaque = Z_NULL;
        strm.avail_in = (uInt)graylog_data.length;
        strm.next_in = (Bytef *)graylog_data.bytes;
        strm.avail_out = (UInt)graylog_data.length;
        strm.next_out = (Bytef *)buf;

        deflateInit(&strm, Z_DEFAULT_COMPRESSION);
        deflate(&strm, Z_FINISH);
        deflateEnd(&strm);


        uLong chunk_count = (strm.total_out % max_chunk_size) ?
                                strm.total_out / max_chunk_size + 1 :
                                strm.total_out / max_chunk_size;
        long remain = strm.total_out;

        // Generate a message_id hash from hostname and timestamp
        struct timeval time;
        gettimeofday(&time, NULL);


        uint64 P1 = 7;
        uint64 P2 = 31;
        uint64 hash = P1;
        char *message_string = malloc(strlen(hostname) + ceil(log10(abs(time.tv_usec))) + 1);
        sprintf(message_string, "%s%u", hostname, time.tv_usec);

        for (const char* p = message_string; *p != 0; p++) {
            hash = hash * P2 + *p;
        }

        for (int i=0;i<chunk_count;i++){
            char *chunk = malloc(max_chunk_size);
            long toCopy = remain > max_chunk_size ? max_chunk_size : remain;
            memcpy(chunk, buf, toCopy);
            buf += toCopy;
            remain -= toCopy;

            NSData *chunkData = [NSData dataWithBytesNoCopy:chunk length:toCopy freeWhenDone:YES];

            // Append chunk header if we're sending multiple chunks
            if (chunk_count > 1){

                graylog_header *header = malloc(sizeof(graylog_header));
                Byte chunked[2] = {0x1e, 0x0f};
                memcpy(header->message_id, &hash, sizeof(message_id_t));
                memcpy(header->chunked, &chunked, 2);
                header->sequence = i;
                header->total = chunk_count;


                NSMutableData *chunkHeader = [NSMutableData dataWithBytes:header length:12];
                [chunkHeader appendData:chunkData];
                chunkData = chunkHeader;
            }

            NSData *graylog_data_compressed = chunkData;//[NSData dataWithBytesNoCopy:buf length:strm.total_out freeWhenDone:YES];
            CFSocketSendData(graylog_socket, NULL, (__bridge CFDataRef)(graylog_data_compressed), 1);

        }
    });
}
