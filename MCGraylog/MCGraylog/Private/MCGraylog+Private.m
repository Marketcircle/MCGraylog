//
//  MCGraylog+Private.m
//  MCGraylog
//
//  Created by Mark Rada on 7/27/2013.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import "MCGraylog+Private.h"


@implementation MCGraylog (Private)


- (CFSocketRef)socket {
    return self->socket;
}


- (dispatch_queue_t)queue {
    return self->queue;
}


@end
