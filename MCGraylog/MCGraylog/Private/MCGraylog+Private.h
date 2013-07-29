//
//  MCGraylog+Private.h
//  MCGraylog
//
//  Created by Mark Rada on 7/27/2013.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <MCGraylog/MCGraylog.h>


@interface MCGraylog (Private)

- (CFSocketRef)socket;
- (dispatch_queue_t)queue;

@end
