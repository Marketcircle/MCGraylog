//
//  MCGraylogTests.m
//  MCGraylog
//
//  Created by Mark Rada on 7/21/2013.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

@import XCTest;
#import "MCGraylog.h"


@interface MCGraylogTests : XCTestCase
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
    XCTAssertEqual(GraylogLogLevelDebug, graylog_log_level(),
                   @"Default log level is too low");
}


- (void) testCanSetLogLevel {
    graylog_set_log_level(GraylogLogLevelAlert);
    XCTAssertEqual(GraylogLogLevelAlert, graylog_log_level());
    
    graylog_set_log_level(GraylogLogLevelInfo);
    XCTAssertEqual(GraylogLogLevelInfo, graylog_log_level());

    graylog_set_log_level(GraylogLogLevelCritical);
    XCTAssertEqual(GraylogLogLevelCritical, graylog_log_level());
}


- (void) testInitSetsLevel {
    graylog_init([NSURL URLWithString:@"http://localhost:12201/"],
                 GraylogLogLevelInfo);
    XCTAssertEqual(GraylogLogLevelInfo, graylog_log_level());
}


- (void) testInitFailureReturnsNonZero {
    int result = graylog_init([NSURL URLWithString:@"cannot-resolve.com:22"],
                              GraylogLogLevelDebug);
    XCTAssertTrue(result != 0, @"graylog_init did not fail!");
}


- (void) testInitWithoutPortUsesDefaultGraylogPort {
    int result = graylog_init([NSURL URLWithString:@"http://localhost/"],
                              GraylogLogLevelAlert);
    // a bit fragile, since we might fail for another reason
    XCTAssertTrue(result == 0, @"Setup failed when given no port");
}


- (void) testDeinitCanBeCalledSafely {
    for (int i = 0; i < 100; i++)
        graylog_deinit();
}


- (void) testUnreachableHostFailsGracefully {
    NSURL* unresolvable = [NSURL URLWithString:@"graylog://oetuhoenutheo.com/"];
    int result = graylog_init(unresolvable, GraylogLogLevelAlert);
    XCTAssertEqual(-1, result, @"Managed to resolve the unresolvable");
}

@end
