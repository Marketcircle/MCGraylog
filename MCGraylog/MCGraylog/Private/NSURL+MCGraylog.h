//
//  NSURL+MCGraylog.h
//  MCGraylog
//
//  Created by Mark Rada on 7/27/2013.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSURL (MCGraylog)

+ (NSURL*)localhost:(size_t)port;
+ (NSURL*)host:(NSString*)host port:(size_t)port;

@end
