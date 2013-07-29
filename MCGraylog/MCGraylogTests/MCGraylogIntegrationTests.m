//
//  MCGraylogIntegrationTests.m
//  MCGraylog
//
//  Created by Thomas Bartelmess on 2013-05-27.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import <Availability.h>
#import "MCGraylog.h"
#import "MCGraylog+Private.h"
#import "NSURL+MCGraylog.h"


static NSTask* logstash;
static NSPipe* inputPipe;
static NSPipe* outputPipe;


#define MINIMUM_OUTPUT_LENGTH 20
#define LOGSTASH_TIMEOUT 2.0


@interface MCGraylogIntegrationTests : SenTestCase
@property (nonatomic) NSMutableData* logstash_output;
@property (nonatomic) dispatch_semaphore_t output_semaphore;
@property (nonatomic,strong) MCGraylog* logger;
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
    
    self.logger = [MCGraylog logger];
    STAssertNotNil(self.logger, @"Failed to initialize graylog correctly");
    
    self.logstash_output  = [[NSMutableData alloc] init];
    self.output_semaphore = dispatch_semaphore_create(0);
    
    outputPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle* fh) {
        [self.logstash_output appendData:[fh availableData]];
        dispatch_semaphore_signal(self.output_semaphore);
    };
}


- (void)tearDown {
    outputPipe.fileHandleForReading.readabilityHandler = NULL;

#if __MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_8
    dispatch_release(self.output_semaphore);
#endif
    
    [super tearDown];
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


- (NSDictionary*) waitForResponse:(NSTimeInterval)timeout {
    long result = dispatch_semaphore_wait(self.output_semaphore,
                                          dispatch_time(DISPATCH_TIME_NOW,
                                                        timeout * NSEC_PER_SEC));
    if (result) return nil;

    if (self.logstash_output.length < MINIMUM_OUTPUT_LENGTH)
        return [self waitForResponse:timeout];
    
    return [self parseResponse:self.logstash_output];
}


- (NSDictionary*) logstashResponse {
    return [self waitForResponse:LOGSTASH_TIMEOUT];
}


#define WAIT_FOR_RESPONSE NSDictionary* response = [self logstashResponse]
#define WAIT_FOR_NO_RESPONSE                            \
    NSDictionary* response = [self waitForResponse:1];


#pragma mark Tests


- (void) testCorrectlySendsFacilityAndShortMessage {
    self.logger = [MCGraylog loggerWithLevel:GraylogLogLevelInformational
                             toGraylogServer:[NSURL localhost:MCGraylogDefaultPort]
                                  asFacility:@"test"];
    [self.logger log:GraylogLogLevelInformational
             message:@"message" data:nil];
    
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
       @(GraylogLogLevelNotice),
       @(GraylogLogLevelInformational),
       @(GraylogLogLevelDebug)
       ]
     enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop) {
         [self.logger log:(GraylogLogLevel)((NSNumber*)obj).integerValue
                  message:@"%d", ((NSNumber*)obj).integerValue];
         WAIT_FOR_RESPONSE;
         STAssertEqualObjects(response[@"@fields"][@"level"],
                              obj,
                              @"Wrong log level in response: %@", response);
         
         self.logstash_output = [[NSMutableData alloc] init]; // reset
     }];
}


- (void)testCustomTextField {
    [self.logger log:GraylogLogLevelWarning
             message:@"message"
                data:@{ @"custom_field": @"hello" }];
    WAIT_FOR_RESPONSE;
    STAssertEqualObjects(response[@"@fields"][@"_custom_field"], @"hello", nil);
}


- (void)testCustomNumberField {
    [self.logger log:GraylogLogLevelWarning
             message:@"message"
                data:@{ @"custom_field": @5 }];
    WAIT_FOR_RESPONSE;
    STAssertEqualObjects(response[@"@fields"][@"_custom_field"], @5, nil);
}


- (void) testManyConcurrentLogs {
    STFail(@"Finish implementing me!");
    return;

    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,
                                                   0);
    dispatch_apply(9000, q, ^(size_t index) {
        [self.logger log:GraylogLogLevelAlert message:@"%zd", index];
    });
    
    // some sort of assertion goes here...
}


- (void) testMessageChunking {
    STFail(@"Finish implementing me!");
    return;
    
    NSString* string = @"http://www.youtube.com/watch?v=HNTxr2NJHa0 ";
    for (int i = 0; i < 16; i++)
        string = [string stringByAppendingString:string];
    
    [self.logger log:GraylogLogLevelNotice
             message:@"%@", string];
}


- (void) testMessageNotLoggedIfLevelTooHigh {
    self.logger.maximumLevel = GraylogLogLevelEmergency;
    [self.logger log:GraylogLogLevelDebug
             message:@"herp derp"
                data:nil];
    WAIT_FOR_NO_RESPONSE; // wait a reasonable amount of time for the response
    STAssertNil(response,
                @"Something was still logged to graylog: %@", response);
}


- (void) testLoggingEmptyString {
    [self.logger log:GraylogLogLevelAlert
             message:@""
                data:nil];
    WAIT_FOR_RESPONSE;
    STAssertEqualObjects(response[@"@fields"][@"short_message"], @"",
                         [response description]);
}


- (void) testHandlesLoggingUnserializableObject {
    [self.logger log:GraylogLogLevelDebug
             message:@"message"
                data:@{ @"data": [NSData data] }];
    WAIT_FOR_RESPONSE; // block until we get the response
    
    NSString* actual = response[@"@short_message"];
    NSRange   range  = [actual rangeOfString:@"Failed to serialize message"];
    
    STAssertTrue(range.location != NSNotFound,
                 @"Expected serialization failure message, got: %@", response);
}


@end
