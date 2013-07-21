//
//  MCGraylogIntegrationTests.m
//  MCGraylog
//
//  Created by Thomas Bartelmess on 2013-05-27.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import "MCGraylog.h"


static NSTask* logstash;
static NSPipe* inputPipe;
static NSPipe* outputPipe;


@interface MCGraylogIntegrationTests : SenTestCase
@end


@implementation MCGraylogIntegrationTests


+ (void)setUp {
    NSBundle*   bundle = [NSBundle bundleForClass:[self class]];
    NSArray* arguments =
    @[
      @"-jar", [bundle pathForResource:@"logstash-1.1.12-flatjar" ofType:@"jar"],
      @"agent",
      @"-f", [bundle pathForResource:@"logstash" ofType:@"conf"]
    ];

    inputPipe  = [[NSPipe alloc] init];
    outputPipe = [[NSPipe alloc] init];

    logstash   = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/java"
                                                arguments:arguments];
    logstash.standardInput  = inputPipe;
    logstash.standardOutput = outputPipe;
}

+ (void)tearDown {
    [logstash terminate];
}


- (void)setUp {
    [super setUp];
    graylog_init("localhost", "12201");
}

- (void)tearDown {
    [super tearDown];
    graylog_deinit();
}

- (NSDictionary *)logstashResponse {
    NSMutableData * data = [NSMutableData data];
    do {
        [data appendData:[outputPipe.fileHandleForReading availableData]];
        NSLog(@"%lu", data.length);
    } while (data.length < 10);
    
    NSError * jsonParseError = nil;
    
    NSDictionary * logstashResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonParseError];
    STAssertNotNil(logstashResponse, @"Failed to parse logstash response:%@. Error: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    return logstashResponse;
}

- (void)testBasicLogging {
    graylog_log(GraylogLogLevelInformational, @"test", @"message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"short_message"], @"message", @"Short message should be test");
    STAssertEqualObjects(response[@"@fields"][@"facility"], @"test", @"Short message should be test");
}
- (void)testDebugLevel {
    graylog_log(GraylogLogLevelDebug, @"test", @"message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelDebug), @"Wrong log level in response");
}

- (void)testAlertLevel {
    graylog_log(GraylogLogLevelAlert, @"test", @"message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelAlert), @"Wrong log level in response");
}

- (void)testCriticalLevel {
    graylog_log(GraylogLogLevelCritical, @"test", @"message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelCritical), @"Wrong log level in response");
}

- (void)testEmergencyLevel {
    graylog_log(GraylogLogLevelEmergency, @"test", @"message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelEmergency), @"Wrong log level in response");
}

- (void)testErrorLevel {
    graylog_log(GraylogLogLevelError, @"test", @"message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelError), @"Wrong log level in response");
}

- (void)testInformationalLevel {
    graylog_log(GraylogLogLevelInformational, @"test", @"message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelInformational), @"Wrong log level in response");
}

- (void)testNoticeLevel {
    graylog_log(GraylogLogLevelNotice, @"test", @"message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelNotice), @"Wrong log level in response");
}

- (void)testWarningLevel {
    graylog_log(GraylogLogLevelWarning, @"test", @"message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelWarning), @"Wrong log level in response");
}

- (void)testCustomTextField {
    graylog_log(GraylogLogLevelWarning, @"test", @"message", @{@"custom_field":@"hello"});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"_custom_field"], @"hello",@"");
}

- (void)testCustomNumberField {
    graylog_log(GraylogLogLevelWarning, @"test", @"message", @{@"custom_field":@5});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"_custom_field"], @5,@"");
}

@end
