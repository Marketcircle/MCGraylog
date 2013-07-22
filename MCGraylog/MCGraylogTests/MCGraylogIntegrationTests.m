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
    logstash   = [[NSTask alloc] init];
    inputPipe  = [[NSPipe alloc] init];
    outputPipe = [[NSPipe alloc] init];
    
    NSBundle* bundle = [NSBundle bundleForClass:[self class]];

    [logstash setLaunchPath:@"/usr/bin/java"];
    
    NSString * jarPath = [bundle pathForResource:@"logstash-1.1.12-flatjar"
                                          ofType:@"jar"];
    NSString * configFile = [bundle pathForResource:@"logstash"
                                             ofType:@"conf"];
    [logstash setArguments:@[@"-jar", jarPath, @"agent", @"-f", configFile]];
    logstash.standardInput  = inputPipe;
    logstash.standardOutput = outputPipe;
    [logstash launch];
    
    // wait until started up...
    [[inputPipe fileHandleForWriting]
        writeData:[@"blocking..." dataUsingEncoding:NSASCIIStringEncoding]];
    [[inputPipe fileHandleForWriting] closeFile];
    
    [outputPipe.fileHandleForReading availableData];
}


+ (void)tearDown {
    [logstash terminate];
}


- (void)setUp {
    [super setUp];
    graylog_init("localhost", "12201", GraylogLogLevelDebug);
}


- (void)tearDown {
    [super tearDown];
    graylog_deinit();
}


- (NSDictionary*) parseResponse:(NSData*)data {

    NSError*   parse_error = nil;
    NSDictionary* response = [NSJSONSerialization JSONObjectWithData:data
                                                             options:0
                                                               error:&parse_error];
    STAssertNotNil(response,
                   @"Failed to parse logstash response: %@. Error: %@",
                   [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding],
                   parse_error);
    
    return response;
}


- (NSDictionary*) logstashResponse {

    NSMutableData* data = [NSMutableData data];
    do {
        [data appendData:[outputPipe.fileHandleForReading availableData]];
    } while (data.length < 10); // TODO: why 10? magic number fuuuuuu
    
    return [self parseResponse:data];
}


- (NSDictionary*) waitForResponse:(NSTimeInterval)timeout {
    NSMutableData* data = [[NSMutableData alloc] init];
    
    NSDate* start = [NSDate date];
    while ([[NSDate date] timeIntervalSinceDate:start] < timeout)
        [data appendData:[outputPipe.fileHandleForReading availableData]];
    
    if (!data.length) return nil;

    return [self parseResponse:data];
}

- (dispatch_queue_t)graylogQueue {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND,
                                     0);
}


#define WAIT_FOR_RESPONSE NSDictionary* response = [self logstashResponse]
#define WAIT_FOR_NO_RESPONSE                            \
    dispatch_barrier_sync([self graylogQueue], ^() {}); \
    NSDictionary* response = [self waitForResponse:1];


#pragma mark Tests


- (void) testCorrectlySendsFacilityAndShortMessage {
    
    graylog_log(GraylogLogLevelInformational, @"test", @"message", @{});
    WAIT_FOR_RESPONSE;
    
    STAssertEqualObjects(response[@"@fields"][@"short_message"], @"message",
                         @"Short message should be test");
    STAssertEqualObjects(response[@"@fields"][@"facility"], @"test",
                         @"Short message should be test");
}


- (void) testLogLevels {
    [@[
       @(GraylogLogLevelUnknown),
       @(GraylogLogLevelFatal),
       @(GraylogLogLevelEmergency),
       @(GraylogLogLevelAlert),
       @(GraylogLogLevelCritical),
       @(GraylogLogLevelError),
       @(GraylogLogLevelWarning),
       @(GraylogLogLevelWarn),
       @(GraylogLogLevelNotice),
       @(GraylogLogLevelInformational),
       @(GraylogLogLevelInfo),
       @(GraylogLogLevelDebug)
       ]
     enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop) {
         graylog_log((GraylogLogLevel)[obj integerValue],
                     @"test",
                     @"message",
                     nil);
         WAIT_FOR_RESPONSE;
         STAssertEqualObjects(response[@"@fields"][@"level"],
                              obj,
                              @"Wrong log level in response");
     }];
}


- (void)testCustomTextField {
    graylog_log(GraylogLogLevelWarning,
                @"test",
                @"message",
                @{
                  @"custom_field": @"hello"
                  });
    WAIT_FOR_RESPONSE;
    STAssertEqualObjects(response[@"@fields"][@"_custom_field"], @"hello", nil);
}


- (void)testCustomNumberField {
    graylog_log(GraylogLogLevelWarning,
                @"test",
                @"message",
                @{
                  @"custom_field": @5
                  });
    WAIT_FOR_RESPONSE;
    STAssertEqualObjects(response[@"@fields"][@"_custom_field"], @5, nil);
}


- (void) testManyConcurrentLogs {
    STFail(@"Implement me!");
    return;
    
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,
                                                   0);
    dispatch_apply(100, q, ^(size_t index) {
        GRAYLOG_ALERT(@"test", @"%zd", index);
    });

    // some sort of assertion goes here...
}


- (void) testVariableArgumentsForMacros {
    STFail(@"Implement me!");
}


- (void) testMessageChunking {
    STFail(@"Implement me!");
}


- (void) testMessageNotLoggedIfLevelTooHigh {
    graylog_set_log_level(GraylogLogLevelEmergency);
    GRAYLOG_DEBUG(@"test", @"herp derp");
    WAIT_FOR_NO_RESPONSE; // wait a reasonable amount of time for the response
    STAssertNil(response, @"Something was still logged to graylog!");
}


- (void) testHandlesLoggingUnserializableObject {
    graylog_log(GraylogLogLevelDebug,
                @"test",
                @"message",
                @{
                  @"data": [NSData data]
                  });
    WAIT_FOR_RESPONSE; // block until we get the response
    
    NSString* actual = response[@"@short_message"];
    NSRange   range  = [actual rangeOfString:@"Failed to serialize message"];

    STAssertTrue(range.location != NSNotFound,
                 @"Expected serialization failure message, got: %@", response);
}


- (void) testLoggingEmptyString {
    GRAYLOG_ALERT(@"test", @"");
    WAIT_FOR_RESPONSE;
    STAssertEqualObjects(response[@"@short_message"], @"", nil);
}


- (void) testLoggingEmptyFacility {
    GRAYLOG_ALERT(@"", @"message");
    WAIT_FOR_RESPONSE;
    STAssertEqualObjects(response[@"@facility"], @"", nil);
}


- (void) testFacilityAndMessageMustNotBeNil {
    STFail(@"Implement me!");
}


@end
