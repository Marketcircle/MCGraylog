//
//  MCGraylogTests.m
//  MCGraylogTests
//
//  Created by Jordan on 2013-05-06.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#include "MCGraylog.h"


@interface MCGraylogTests : SenTestCase
@end


@implementation MCGraylogTests

- (void) testCanSetup
{
    int result = graylog_init("localhost", "12201");
    STAssertEquals(0, result, @"Failed to initialize graylog");
}

@end
