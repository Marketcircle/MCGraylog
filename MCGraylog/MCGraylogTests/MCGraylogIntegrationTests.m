//
//  MCGraylogIntegrationTests.m
//  MCGraylog
//
//  Created by Thomas Bartelmess on 2013-05-27.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//
#import <SenTestingKit/SenTestingKit.h>
#import "MCGraylog.h"



static NSTask * logstashTask;
static NSPipe * inputPipe;
static NSPipe * outputPipe;
@interface MCGraylogIntegrationTests : SenTestCase



@end

@implementation MCGraylogIntegrationTests
- (id)init
{
    self = [super init];
    if (self) {
        NSLog(@"init!");
    }
    return self;
}
+ (void)setUp {
    logstashTask = [[NSTask alloc] init];
    [logstashTask setLaunchPath:@"/usr/bin/java"];
    NSString * jarPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"logstash-1.1.12-flatjar" ofType:@"jar"];
    NSString * configFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"logstash" ofType:@"conf"];
    [logstashTask setArguments:[NSArray arrayWithObjects: @"-jar", jarPath, @"agent", @"-f", configFile, nil]];
    
    inputPipe = [[NSPipe alloc] init];
    
    logstashTask.standardInput = inputPipe;
    
    outputPipe = [[NSPipe alloc] init];
    
    logstashTask.standardOutput = outputPipe;

    [logstashTask launch];
    
    [[inputPipe fileHandleForWriting] writeData:[@"hello" dataUsingEncoding:NSASCIIStringEncoding]];
    
    [[inputPipe fileHandleForWriting] closeFile];
    
    NSLog(@"%@",[outputPipe.fileHandleForReading availableData]);
    NSLog(@"Launched");
}

+ (void)tearDown {
    [logstashTask terminate];
    [logstashTask waitUntilExit];
}

- (void)setUp {
    graylog_init("localhost", "12201");
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
    graylog_log(GraylogLogLevelInformational, "test", "message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"short_message"], @"message", @"Short message should be test");
    STAssertEqualObjects(response[@"@fields"][@"facility"], @"test", @"Short message should be test");
}
- (void)testDebugLevel {
    graylog_log(GraylogLogLevelDebug, "test", "message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelDebug), @"Wrong log level in response");
}

- (void)testAlertLevel {
    graylog_log(GraylogLogLevelAlert, "test", "message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelAlert), @"Wrong log level in response");
}

- (void)testCriticalLevel {
    graylog_log(GraylogLogLevelCritical, "test", "message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelCritical), @"Wrong log level in response");
}

- (void)testEmergencyLevel {
    graylog_log(GraylogLogLevelEmergency, "test", "message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelEmergency), @"Wrong log level in response");
}

- (void)testErrorLevel {
    graylog_log(GraylogLogLevelError, "test", "message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelError), @"Wrong log level in response");
}

- (void)testInformationalLevel {
    graylog_log(GraylogLogLevelInformational, "test", "message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelInformational), @"Wrong log level in response");
}

- (void)testNoticeLevel {
    graylog_log(GraylogLogLevelNotice, "test", "message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelNotice), @"Wrong log level in response");
}

- (void)testWarningLevel {
    graylog_log(GraylogLogLevelWarning, "test", "message", @{});
    NSDictionary * response = [self logstashResponse];
    STAssertEqualObjects(response[@"@fields"][@"level"], @(GraylogLogLevelWarning), @"Wrong log level in response");
}


@end
