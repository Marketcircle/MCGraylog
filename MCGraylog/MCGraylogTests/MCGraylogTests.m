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
    
    graylog_set_log_level(GraylogLogLevelInfo);
    STAssertEquals(GraylogLogLevelInfo, graylog_log_level(), nil);

    graylog_set_log_level(GraylogLogLevelCritical);
    STAssertEquals(GraylogLogLevelCritical, graylog_log_level(), nil);
}


- (void) testInitSetsLevel {
    graylog_init([NSURL URLWithString:@"http://localhost:12201/"],
                 GraylogLogLevelInfo);
    STAssertEquals(GraylogLogLevelInfo, graylog_log_level(), nil);
}


- (void) testInitFailureReturnsNonZero {
    int result = graylog_init([NSURL URLWithString:@"cannot-resolve.com:22"],
                              GraylogLogLevelDebug);
    STAssertTrue(result != 0, @"graylog_init did not fail!");
}


- (void) testInitWithoutPortUsesDefaultGraylogPort {
    int result = graylog_init([NSURL URLWithString:@"http://localhost/"],
                              GraylogLogLevelAlert);
    // a bit fragile, since we might fail for another reason
    STAssertTrue(result == 0, @"Setup failed when given no port");
}


- (void) testDeinitCanBeCalledSafely {
    for (int i = 0; i < 100; i++)
        graylog_deinit();
}


@end
