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

#if __MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_8
#define DISPATCH_RELEASE(q) if (q) dispatch_release(q)
#else
#define DISPATCH_RELEASE(q)
#endif

#endif
