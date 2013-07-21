//
//  MCGraylog.h
//  MCGraylog
//
//  Created by Jordan on 2013-05-06.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    GraylogLogLevelEmergency = 0,
    GraylogLogLevelAlert = 1,
    GraylogLogLevelCritical = 2,
    GraylogLogLevelError = 3,
    GraylogLogLevelWarning = 4,
    GraylogLogLevelNotice = 5,
    GraylogLogLevelInformational = 6,
    GraylogLogLevelDebug = 7
} GraylogLogLevel;

/**
 * Perform some up front work needed for all future log messages
 *
 * @return 0 on success, otherwise -1.
 */
int graylog_init(const char* address, const char* port);

void graylog_log(GraylogLogLevel lvl,
                 const char* facility,
                 const char* msg,
                 NSDictionary *data);


