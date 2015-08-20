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

static Class dictClass = nil;

@implementation MCGraylogLogger {
    NSString* facility;
}

@synthesize loggerFacility = facility;

+ (void)initialize {
    dictClass = [NSDictionary class];
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
graylog_level_for_lumberjack_flag(const DDLogFlag level)
{
    switch (level) {
        case DDLogFlagError:            return GraylogLogLevelError;
        case DDLogFlagWarning:          return GraylogLogLevelWarning;
        case DDLogFlagInfo:             return GraylogLogLevelInformational;
        case DDLogFlagDebug:            return GraylogLogLevelDebug;
        case DDLogFlagVerbose:          return GraylogLogLevelDebug;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcovered-switch-default"
        // DDLogFlag may add more levels in the future, so we need to do a bit
        // of future proofing
        default:                        return GraylogLogLevelEmergency;
#pragma clang diagnostic pop
    }
}

- (void)logMessage:(DDLogMessage* const)logMessage {
    const GraylogLogLevel level =
        graylog_level_for_lumberjack_flag(logMessage->_flag);

    NSString* msg = nil;
    if (self->_logFormatter)
        msg = [self->_logFormatter formatLogMessage:logMessage];
    else
        msg = logMessage->_message;

    NSNumber* const stamp = @((time_t)logMessage->_timestamp.timeIntervalSince1970);

    NSDictionary* dict = nil;
    if ([logMessage->_tag isKindOfClass:dictClass]) {
        dict = logMessage->_tag;
    }
    else if (logMessage->_tag) {
        dict = @{ @"_tag": logMessage->_tag };
    }

    _graylog_log(level, self->facility, msg, stamp, dict);
}

@end

#pragma clang diagnostic pop
