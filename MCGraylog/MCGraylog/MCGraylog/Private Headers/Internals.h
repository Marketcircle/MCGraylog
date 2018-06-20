//
//  Internals.h
//  MCGraylog
//
//  Created by Mark Rada on 7/22/2013.
//  Copyright (c) 2013 Marketcircle. All rights reserved.
//

#ifndef MCGraylog_Internals_h
#define MCGraylog_Internals_h

dispatch_queue_t graylog_queue();

void
_graylog_log(const GraylogLogLevel level,
             __unsafe_unretained NSString* const facility,
             __unsafe_unretained NSString* const message,
             __unsafe_unretained NSNumber* const timestamp,
             __unsafe_unretained NSDictionary* const data);


#endif
