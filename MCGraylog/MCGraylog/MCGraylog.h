//
//  MCGraylog.h
//  MCGraylog
//
//  Created by Jordan on 2013-05-06.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    GraylogLogLevelEmergency     = 0,
    GraylogLogLevelAlert         = 1,
    GraylogLogLevelCritical      = 2,
    GraylogLogLevelError         = 3,
    GraylogLogLevelWarning       = 4,
    GraylogLogLevelWarn          = 4,
    GraylogLogLevelNotice        = 5,
    GraylogLogLevelInformational = 6,
    GraylogLogLevelInfo          = 6,
    GraylogLogLevelDebug         = 7
} GraylogLogLevel;

NSString* const MCGraylogLogFacility = @"mcgraylog";


/**
 * Perform some up front work needed for all future log messages
 *
 * @return 0 on success, otherwise -1.
 */
int graylog_init(const char* address, const char* port);

/**
 * Free any global state that was created by graylog_init.
 */
void graylog_deinit();


/**
 * Log a message to the Graylog server (or some other compatible service).
 *
 * @param lvl Log level, the severity of the message
 * @param facility Arbitrary string indicating the subsystem the message came
 *                 from (i.e. sync, persistence, etc.)
 * @param msg The actual log message, or maybe some monosodium glutamate
 * @param data Any additional information that might be useful that is JSON
 *             serializable (e.g. numbers, strings, arrays, dictionaries)
 */
void graylog_log(GraylogLogLevel lvl,
                 const char* facility,
                 const char* msg,
                 NSDictionary* data);
