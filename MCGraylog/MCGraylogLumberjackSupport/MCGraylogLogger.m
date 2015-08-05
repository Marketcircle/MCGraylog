//
//  JNGraylogLogger.m
//  Javin
//
//  Created by Thomas Bartelmess on 2013-07-25.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <MCGraylog/MCGraylog.h>
#import <MCGraylog/Internals.h>
#import "MCGraylogLogger.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"

GraylogLogLevel graylog_level_for_javin_level(const DDLogLevel level);

static NSString* const JNGraylogLoggerFacility = @"Javin";
static Class dictClass = nil;

@implementation MCGraylogLogger {
    NSString* facility;
}

@synthesize loggerFacility = facility;

+ (void)initialize {
    dictClass = [NSDictionary class];
}

- (instancetype)initWithServer:(NSURL *)graylogServer graylogLevel:(GraylogLogLevel)level {
    return [self initWithServer:graylogServer graylogLevel:level facility:JNGraylogLoggerFacility];
}

- (instancetype)initWithServer:(NSURL*)graylogServer
                  graylogLevel:(GraylogLogLevel)level
                      facility:(NSString*)init_facility
{
    if (!(self = [super init])) return nil;

    graylog_init(graylogServer, level);
    self->facility = init_facility;

    return init_facility ? self : nil;
}

- (void)dealloc {
    graylog_deinit();
}

GraylogLogLevel
graylog_level_for_javin_level(const DDLogLevel level)
{
    switch (level) {
        case DDLogLevelOff:       return GraylogLogLevelEmergency;
        case DDLogLevelError:     return GraylogLogLevelError;
        case DDLogLevelWarning:   return GraylogLogLevelWarning;
        case DDLogLevelInfo:      return GraylogLogLevelInfo;
        case DDLogLevelDebug:     return GraylogLogLevelDebug;
        case DDLogLevelVerbose:   return GraylogLogLevelDebug;
        case DDLogLevelAll:       return GraylogLogLevelDebug;
        // DDLogLevel is a bit of strange enum, by which I mean it takes on non-standard values
        // and I worry that one day someone will just cast an int somewhere that is not a proper
        // DDLogLevel and then send it through this function...
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcovered-switch-default"
        default:
            return GraylogLogLevelEmergency;
#pragma clang diagnostic pop
    }
}

- (void)logMessage:(DDLogMessage* const)logMessage {
    NSString* logMsg = nil;
    if (self->_logFormatter)
        logMsg = [self->_logFormatter formatLogMessage:logMessage];
    else
        logMsg = logMessage->_message;

    const GraylogLogLevel level =
        graylog_level_for_javin_level(logMessage->_level);

    NSDictionary* dataDictionary = nil;
    if ([logMessage->_tag isKindOfClass:dictClass]) {
        dataDictionary = logMessage->_tag;
    }

    _graylog_log(level, self->facility, logMsg, dataDictionary);
}

@end

#pragma clang diagnostic pop
