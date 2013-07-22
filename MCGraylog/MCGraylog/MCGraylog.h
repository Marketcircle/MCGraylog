//
//  MCGraylog.h
//  MCGraylog
//
//  Created by Jordan on 2013-05-06.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef enum {
    GraylogLogLevelUnknown       = 0,
    GraylogLogLevelFatal         = 0,
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


#pragma mark Init/Deinit

/**
 * Perform some up front work needed for all future log messages
 *
 * @param address domain where the graylog server is located
 * @param port port number that graylog server is listening on
 * @param level minimum log level required to actually send messages to graylog;
 *        if a message is logged with a higher level it will be ignored
 * @return 0 on success, otherwise -1.
 */
int graylog_init(const char* address,
                 const char* port,
                 GraylogLogLevel level);

/**
 * Free any global state that was created by graylog_init.
 */
void graylog_deinit();


#pragma mark Properties

/**
 * @return the current log level;
 */
GraylogLogLevel graylog_log_level();

/**
 * @param level the new log level
 */
void graylog_set_log_level(GraylogLogLevel level);

/**
 * @todo Put this in a private header
 */
dispatch_queue_t graylog_queue();


#pragma mark Logging

/**
 * @todo Consider making the log level parameter an NSNumber
 *
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
                 NSString* facility,
                 NSString* message,
                 NSDictionary* data);


#define GRAYLOG_LOG(level, facility, format, ...) {                         \
    NSString* message = [NSString stringWithFormat:format, ##__VA_ARGS__];  \
    graylog_log(level, facility, message, nil);                             \
}

#define GRAYLOG_EMERGENCY(facility, format, ...) \
    GRAYLOG_LOG(GraylogLogLevelEmergency, facility, format, ##__VA_ARGS__)

#define GRAYLOG_ALERT(facility, format, ...) \
    GRAYLOG_LOG(GraylogLogLevelAlert, facility, format, ##__VA_ARGS__)

#define GRAYLOG_CRITICAL(facility, format, ...) \
    GRAYLOG_LOG(GraylogLogLevelCritical, facility, format, ##__VA_ARGS__)

#define GRAYLOG_ERROR(facility, format, ...) \
    GRAYLOG_LOG(GraylogLogLevelError, facility, format, ##__VA_ARGS__)

#define GRAYLOG_WARN(facility, format, ...) \
    GRAYLOG_LOG(GraylogLogLevelWarn, facility, format, ##__VA_ARGS__)

#define GRAYLOG_NOTICE(facility, format, ...) \
    GRAYLOG_LOG(GraylogLogLevelNotice, facility, format, ##__VA_ARGS__)

#define GRAYLOG_INFO(facility, format, ...) \
    GRAYLOG_LOG(GraylogLogLevelInfo, facility, format, ##__VA_ARGS__)

#define GRAYLOG_DEBUG(facility, format, ...) \
    GRAYLOG_LOG(GraylogLogLevelDebug, facility, format, ##__VA_ARGS__)
