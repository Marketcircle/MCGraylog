//
//  MCGraylog.h
//  MCGraylog
//
//  Created by Jordan on 2013-05-06.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <Foundation/Foundation.h>

void graylog_init(const char* address, const char* port);
void graylog_log(uint lvl, const char* facility, const char* msg, NSDictionary *data);
//void graylog_log(const char* string);


