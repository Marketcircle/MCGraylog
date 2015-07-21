//
//  JNGraylogLogger.h
//  Javin
//
//  Created by Thomas Bartelmess on 2013-07-25.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#import <CocoaLumberjack/CocoaLumberjack.h>
#import <MCGraylog/MCGraylog.h>

@interface MCGraylogLogger : DDAbstractLogger

- (instancetype)initWithServer:(NSURL*)graylogServer
                  graylogLevel:(GraylogLogLevel)level
    NS_DESIGNATED_INITIALIZER;

@property (nonatomic,retain) NSString* loggerFacility;

@end
