//
//  MCGraylogTests.m
//  MCGraylogTests
//
//  Created by Jordan on 2013-05-06.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import "MCGraylogTests.h"
#import "MCGraylog.h"

@implementation MCGraylogTests

- (void)setUp
{
    [super setUp];
    
    // Set-up code here.
}

- (void)tearDown
{
    // Tear-down code here.
    
    [super tearDown];
}

- (void)testExample
{
    graylog_init("localhost", "12201");
    graylog_log(1,"foo_facility", "foo", [NSDictionary dictionaryWithObjectsAndKeys:@"one", @"1", @"two", @"2", nil]);
}

@end
