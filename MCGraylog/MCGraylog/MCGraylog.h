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
    GraylogLogLevelNotice        = 5,
    GraylogLogLevelInformational = 6,
    GraylogLogLevelDebug         = 7
} GraylogLogLevel;


extern NSString* const MCGraylogDefaultFacility;
extern const size_t MCGraylogDefaultPort;
extern const GraylogLogLevel MCGraylogDefaultLogLevel;



@interface MCGraylog : NSObject {
    CFSocketRef      socket;
    dispatch_queue_t queue;
};


/**
 */
+ (MCGraylog*)logger;

/**
 */
+ (MCGraylog*)loggerWithLevel:(GraylogLogLevel)initLevel;

/**
 */
+ (MCGraylog*)loggerWithLevel:(GraylogLogLevel)initLevel
              toGraylogServer:(NSURL*)host;

/**
 */
+ (MCGraylog*)loggerWithLevel:(GraylogLogLevel)initLevel
              toGraylogServer:(NSURL*)host
                   asFacility:(NSString*)facility;

/**
 *
 * @param initLevel
 * @param host
 * @param facility
 * @param async
 **/
+ (MCGraylog*)loggerWithLevel:(GraylogLogLevel)initLevel
              toGraylogServer:(NSURL*)host
                   asFacility:(NSString*)facility
                 asynchronous:(BOOL)async;


- (id) initWithLevel:(GraylogLogLevel)initLevel
     toGraylogServer:(NSURL*)host
          asFacility:(NSString*)facility
        asynchronous:(BOOL)async
               error:(NSError**)error;


@property (nonatomic,strong,readonly) NSString* facility;

@property (nonatomic) GraylogLogLevel maximumLevel;


- (void) log:(GraylogLogLevel)level
     message:(NSString*)message, ...;

- (void) log:(GraylogLogLevel)level
     message:(NSString*)message
        data:(NSDictionary*)data;

// TODO:
//- (void) logError:(NSError*)error;
//- (void) logException:(NSException*)exception;


@end


#pragma mark Init/Deinit

/**
 * Perform some up front work needed for all future log messages
 *
 * @param graylog_url The URL (host and port) where Graylog2 is listening;
 *        if no port number is given, then the default Graylog2 port is used
 * @param level minimum log level required to actually send messages to graylog;
 *        if a message is logged with a higher level it will be ignored
 * @param sync Whether or not to make all logging synchronous
 * @return 0 on success, otherwise -1.
 */


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
