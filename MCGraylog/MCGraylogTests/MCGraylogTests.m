//
//  MCGraylogTests.m
//  MCGraylog
//
//  Created by Mark Rada on 7/21/2013.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import "MCGraylog.h"


@interface MCGraylogTests : SenTestCase
@end


@implementation MCGraylogTests


- (void) setUp
{
    [super setUp];
    graylog_deinit();
}


- (void) tearDown
{
    [super tearDown];
    graylog_deinit();
}


#pragma mark Tests

- (void) testDefaultLogLevelIsDebug { // which is the highest level
    STAssertEquals(GraylogLogLevelDebug, graylog_log_level(),
                   @"Default log level is too low");
}


- (void) testCanSetLogLevel {
    graylog_set_log_level(GraylogLogLevelAlert);
    STAssertEquals(GraylogLogLevelAlert, graylog_log_level(), nil);
    
    graylog_set_log_level(GraylogLogLevelAlert);
    STAssertEquals(GraylogLogLevelDebug, graylog_log_level(), nil);

    graylog_set_log_level(GraylogLogLevelDebug);
    STAssertEquals(GraylogLogLevelDebug, graylog_log_level(), nil);
}


- (void) testInitSetsLevel {
    graylog_init("localhost", "12201", GraylogLogLevelInfo);
    STAssertEquals(GraylogLogLevelInfo, graylog_log_level(), nil);
}


- (void) testInitFailureReturnsNonZero {
    int result = graylog_init("cannot resolve",
                              "12201",
                              GraylogLogLevelDebug);
    STAssertTrue(result != 0, @"graylog_init did not fail!");
    
    result = graylog_init("localhost",
                          "not a port",
                          GraylogLogLevelDebug);
    STAssertTrue(result != 0, @"graylog_init did not fail!");
}


- (void) testDeinitCanBeCalledSafely {
    for (int i = 0; i < 100; i++)
        graylog_deinit();
}


@end
