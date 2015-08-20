//
//  JNGraylogLogger.h
//  Javin
//
//  Created by Thomas Bartelmess on 2013-07-25.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#ifdef __cplusplus
#import <Foundation/Foundation.h>
#import <CocoaLumberjack/CocoaLumberjack.h>
#import <MCGraylog/MCGraylog.h>
#else
@import Foundation;
@import CocoaLumberjack;
@import MCGraylog;
#endif

@interface MCGraylogLogger : DDAbstractLogger

- (instancetype)initWithServer:(NSURL*)graylogServer
                  graylogLevel:(GraylogLogLevel)level
                      facility:(NSString*)facility
NS_DESIGNATED_INITIALIZER;

@property (nonatomic,retain) NSString* loggerFacility;

@end
