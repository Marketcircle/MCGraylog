//
//  NSURL+MCGraylog.m
//  MCGraylog
//
//  Created by Mark Rada on 7/27/2013.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import "NSURL+MCGraylog.h"

@implementation NSURL (MCGraylog)

+ (NSURL*)localhost:(size_t)port {
    return [self host:@"localhost" port:port];
}

+ (NSURL*)host:(NSString *)host port:(size_t)port {
    NSString* url = [NSString stringWithFormat:@"%@:%zu", host, port];
    return [[self alloc] initWithScheme:@"graylog" host:url path:@"/"];
}

@end
