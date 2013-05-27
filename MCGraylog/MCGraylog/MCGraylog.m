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

static dispatch_queue_t graylog_queue;
static CFSocketRef graylog_socket;

void socket_callback(
    CFSocketRef s,
    CFSocketCallBackType callbackType,
    CFDataRef address,
    const void *data,
    void *info
);

void graylog_init(const char* address, const char* port) {
    graylog_queue = dispatch_queue_create("com.marketcircle.graylog", 0);
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
        NSData *graylog_data_compressed = [NSData dataWithBytesNoCopy:buf length:strm.total_out freeWhenDone:YES];
        CFSocketSendData(graylog_socket, NULL, (__bridge CFDataRef)(graylog_data_compressed), 1);
    });
}

void socket_callback(
    CFSocketRef s,
    CFSocketCallBackType callbackType,
    CFDataRef address,
    const void *data,
    void *info) {

    printf("callback stuff\n");
}