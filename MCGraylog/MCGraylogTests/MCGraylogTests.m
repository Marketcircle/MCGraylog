//
//  MCGraylogTests.m
//  MCGraylog
//
//  Created by Mark Rada on 7/21/2013.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import "MCGraylog.h"
#import "MCGraylog+Private.h"
#import "NSURL+MCGraylog.h"


@interface MCGraylogTests : SenTestCase
@property (nonatomic,strong) MCGraylog* logger;
@end


@implementation MCGraylogTests


- (void) setUp {
    [super setUp];
    self.logger = [MCGraylog logger];
}


#pragma mark Tests

- (void) testDefaultLogLevelIsDebug { // Debug is the highest level
    STAssertEquals(GraylogLogLevelDebug, self.logger.maximumLevel,
                   @"Default log level is too low");
}


- (void) testInitHostWithNoPortUsesDefaultPort {
}


- (void) testInitFailureReturnsNilAndSetsError {

    NSError* error = nil;
    MCGraylog* derp = [[MCGraylog alloc] initWithLevel:GraylogLogLevelError
                                       toGraylogServer:nil
                                            asFacility:@"test"
                                          asynchronous:YES
                                                 error:&error];
    
    STAssertNil(derp, @"Somehow initialized with nil host");
}


- (void) testInitWithoutPortUsesDefaultGraylogPort {
    NSURL* url = [NSURL URLWithString:@"graylog://localhost/"];
    
    NSError* error = nil;
    MCGraylog* derp = [[MCGraylog alloc] initWithLevel:GraylogLogLevelError
                                       toGraylogServer:url
                                            asFacility:@"test"
                                          asynchronous:YES
                                                 error:&error];
    
    // a bit fragile, since we might fail for another reason
    STAssertNotNil(derp, @"Setup failed when given no port");
    STAssertNil(error, @"Got error during ini: %@", error);
}



- (void) testMessageMustNotBeNil {
    STAssertThrows([self.logger log:GraylogLogLevelError message:nil],
                   @"graylog_log should throw when given nil facility");
}


- (void) testLoggingEmptyFacility {
    STAssertThrows([MCGraylog loggerWithLevel:MCGraylogDefaultLogLevel
                              toGraylogServer:[NSURL localhost:MCGraylogDefaultPort]
                                   asFacility:@""],
                   @"Did not catch empty facility name");
    STAssertThrows([MCGraylog loggerWithLevel:MCGraylogDefaultLogLevel
                              toGraylogServer:[NSURL localhost:MCGraylogDefaultPort]
                                   asFacility:nil],
                   @"Did not catch nil facility name");
}


@end
