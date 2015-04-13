//
//  JNGraylogLogger_Tests.m
//  Javin
//
//  Created by Thomas Bartelmess on 2013-07-25.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MCGraylogLogger.h"

extern GraylogLogLevel graylog_level_for_javin_level(const DDLogLevel level);

@interface JNGraylogLogger_Tests : XCTestCase
@end

@implementation JNGraylogLogger_Tests

- (void)testLogLevelConversions {
    XCTAssertEqual(graylog_level_for_javin_level(DDLogLevelOff), GraylogLogLevelEmergency,
                   @"Failed to convert FATAL");
    XCTAssertEqual(graylog_level_for_javin_level(DDLogLevelVerbose), GraylogLogLevelDebug,
                   @"Failed to convert FATAL");
    XCTAssertEqual(graylog_level_for_javin_level(DDLogLevelError), GraylogLogLevelError,
                   @"Failed to convert ALERT");
    XCTAssertEqual(graylog_level_for_javin_level(DDLogLevelWarning), GraylogLogLevelWarn,
                   @"Failed to convert NOTICE");
    XCTAssertEqual(graylog_level_for_javin_level(DDLogLevelInfo), GraylogLogLevelInfo,
                   @"Failed to convert INFO");
    XCTAssertEqual(graylog_level_for_javin_level(DDLogLevelDebug), GraylogLogLevelDebug,
                   @"Failed to convert DEBUG");
    XCTAssertEqual(graylog_level_for_javin_level(DDLogLevelAll), GraylogLogLevelDebug,
                   @"Failed to convert ALL");
} /* - testLogLevelConversions */

- (void)testInvalidLogLevelFallsBackToHighestLogLevel {
    XCTAssertEqual(graylog_level_for_javin_level(900000), GraylogLogLevelFatal,
                   @"Fallback level was not the highest!");
} /* - testLogLevelConversions */

@end
