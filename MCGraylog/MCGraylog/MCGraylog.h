//
//  MCGraylog.h
//  MCGraylog
//
//  Created by Jordan on 2013-05-06.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#ifdef __cplusplus
#import <Foundation/Foundation.h>
#else
@import Foundation;
#endif

typedef NS_ENUM(NSUInteger, GraylogLogLevel) {
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
};


#pragma mark Init/Deinit

/**
 * Perform some up front work needed for all future log messages
 *
 * @param graylog_url The URL (host and port) where Graylog2 is listening;
 *        if no port number is given, then the default Graylog2 port is used
 * @param level minimum log level required to actually send messages to graylog;
 *        if a message is logged with a higher level it will be ignored
 * @return 0 on success, otherwise -1.
 */
int graylog_init(NSURL* __nonnull const graylog_url, const GraylogLogLevel level);

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
void graylog_set_log_level(const GraylogLogLevel level);


#pragma mark Logging

/**
 * @todo Consider making the log level parameter an NSNumber
 *
 * Log a message to the Graylog server (or some other compatible service).
 *
 * @param level Log level, the severity of the message
 * @param facility Arbitrary string indicating the subsystem the message came
 *                 from (i.e. sync, persistence, etc.); value cannot be nil
 * @param message The actual log message, or maybe some monosodium glutamate;
 *            value cannot be nil
 * @param userInfo Any additional information that might be useful that is JSON
 *                serializable (e.g. numbers, strings, arrays, dictionaries)
 */
void graylog_log(const GraylogLogLevel level,
                 NSString* __nonnull const facility,
                 NSString* __nonnull const message,
                 NSDictionary* __nullable const userInfo);

void graylog_log2(const GraylogLogLevel level,
                  NSString* __nonnull const facility,
                  NSString* __nonnull const short_message,
                  NSString* __nonnull const full_message,
                  NSDictionary* __nullable const userInfo);

/**
 * Block until all queued log messages have been sent.
 */
void graylog_flush();


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
