//
//  JNGraylogLogger_Tests.m
//  Javin
//
//  Created by Thomas Bartelmess on 2013-07-25.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MCGraylogLogger.h"

extern GraylogLogLevel graylog_level_for_lumberjack_flag(const DDLogFlag level);

@interface JNGraylogLogger_Tests : XCTestCase
@end

@implementation JNGraylogLogger_Tests

- (void)testLogLevelConversions {
    XCTAssertEqual(graylog_level_for_lumberjack_level(DDLogFlagVerbose), GraylogLogLevelDebug,
                   @"Failed to convert FATAL");
    XCTAssertEqual(graylog_level_for_lumberjack_level(DDLogFlagError), GraylogLogLevelError,
                   @"Failed to convert ALERT");
    XCTAssertEqual(graylog_level_for_lumberjack_level(DDLogFlagWarning), GraylogLogLevelWarn,
                   @"Failed to convert WARN");
    XCTAssertEqual(graylog_level_for_lumberjack_level(DDLogFlagInfo), GraylogLogLevelInfo,
                   @"Failed to convert INFO");
    XCTAssertEqual(graylog_level_for_lumberjack_level(DDLogFlagDebug), GraylogLogLevelDebug,
                   @"Failed to convert DEBUG");
} /* - testLogLevelConversions */

- (void)testInvalidLogLevelFallsBackToHighestLogLevel {
    XCTAssertEqual(graylog_level_for_lumberjack_level(900000), GraylogLogLevelFatal,
                   @"Fallback level was not the highest!");
} /* - testLogLevelConversions */

@end
