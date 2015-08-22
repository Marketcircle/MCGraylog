//
//  main.m
//  GraylogCrashReporter
//
//  Created by Mark Rada on 2015-08-14.
//  Copyright (c) 2015 Marketcircle Inc. All rights reserved.
//

@import Foundation;
#import "MCGraylog.h"

static NSString* const facility = @"Crash Reporter";
static NSDate* previous_iteration_newest_create_date = nil;

static void forward_crash_reports(__unused void* ctx) {
@autoreleasepool {

    NSError* error = nil;

    NSURL* const log_dir =
        [NSURL fileURLWithPath:@"/Library/Logs/DiagnosticReports" isDirectory:YES];

    NSFileManager* const m = [NSFileManager defaultManager];

    NSArray* const reports = [m contentsOfDirectoryAtURL:log_dir
                              includingPropertiesForKeys:@[NSURLCreationDateKey]
                                                 options:NSDirectoryEnumerationSkipsHiddenFiles
                                                   error:&error];

    if (reports == nil) {
        GRAYLOG_ERROR(facility, @"Failed to get list of reports: %@", error);
        return;
    }

    NSDate* newest_create_date = previous_iteration_newest_create_date;

    for (NSURL* report in reports) {
        // for now, we only care about crash reports, we do not want to
        // forward routine diagnostics or other such reports
        if (![report.pathExtension isEqualToString:@"crash"]) continue;

        // first, determine if the log is actually new by referencing create date
        // against the newest create date for logs from the last time the timer fired
        NSDate* create_date = nil;

        if (![report getResourceValue:&create_date forKey:NSURLCreationDateKey error:&error]) {
            GRAYLOG_ERROR(facility, @"Failed to get create date for %@: %@", report, error);
            continue;
        }

        // if receiver is earlier than argument, then return value is negative
        if ([create_date timeIntervalSinceDate:previous_iteration_newest_create_date] <= 0.0)
            continue;

        // at this point, we want the log, so we should read it in; and do so without
        // caching, because we will only want to read the data in once ever
        NSData* const report_data = [NSData dataWithContentsOfURL:report
                                                          options:NSDataReadingUncached
                                                            error:&error];
        if (report_data == nil) {
            GRAYLOG_ERROR(facility, @"Failed to read report %@: %@", report, error);
            continue;
        }

        NSString* report_string =
            [[NSString alloc] initWithData:report_data encoding:NSUTF8StringEncoding];

        if (report_string == nil) {
            report_string =
                [[NSString alloc] initWithData:report_data encoding:NSASCIIStringEncoding];

            if (report_string == nil) {
                GRAYLOG_CRITICAL(facility, @"Report contained non-ASCII/non-UTF8 characters: %@",
                                 report);
                continue;
            }
        }

        if ([create_date timeIntervalSinceDate:newest_create_date] > 0.0)
            newest_create_date = create_date;

        graylog_log(GraylogLogLevelAlert,
                    facility,
                    report.lastPathComponent,
                    @{ @"full_message": report_string });


        sleep(1); // prevent overloading the UDP port
    }

    previous_iteration_newest_create_date = newest_create_date;
}
}

int main(__unused int argc, const char * argv[]) {

    previous_iteration_newest_create_date = [NSDate date];

    @autoreleasepool {
        NSURL* const graylog = [NSURL URLWithString:@(argv[1])];
        if (graylog_init(graylog, GraylogLogLevelInfo)) {
            NSLog(@"Failed to initialize graylog logger");
            abort();
        };
    }

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                     0,
                                                     0,
                                                     dispatch_get_main_queue());
    dispatch_source_set_timer(timer,
                              DISPATCH_TIME_NOW,
                              5 * 60 * NSEC_PER_SEC,
                              10 * NSEC_PER_SEC);
    dispatch_source_set_event_handler_f(timer, forward_crash_reports);
    dispatch_resume(timer);
    
    dispatch_main(); // kick it!

}
