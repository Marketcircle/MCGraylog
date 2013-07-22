# MCGraylog [![Build Status](https://travis-ci.org/Marketcircle/MCGraylog.png?branch=master)](https://travis-ci.org/Marketcircle/MCGraylog)

MCGraylog is a Cocoa C library for logging to a Graylog2 server or any
other service that can grok GELF.

MCGraylog is asynchronous and concurrent, so you should not have to
worry about blocking while you log; but, there might be a slight delay
between the time that something is logged and it shows up in Graylog.


## Usage

```obj-c
#import <Foundation/Foundation.h>
#import <MCGraylog.h>

int
main(int argc, char** argv)
{
  // have to initialize some state first
  int init_error = graylog_init("localhost", "12201", GraylogLogLevelDebug);
  if (init_error)
    return -1;

  // the easiest way to log is using the macros
  GRAYLOG_NOTICE(@"test_app", @"My first test message");

  // macros accept format strings, if you want to give more detailed messages
  GRAYLOG_DEBUG(@"test_app", @"Test app has PID of %d", getpid());

  // alternatively, you can log a dictionary of additional information
  // as long as that dictionary can be serialized to JSON
  graylog_log(GraylogLogLevelEmergency,
              @"test_app",
              @"extra information",
              @{
                @"userInfo": @{ @"username": @"ferrous" }
                });
  
  // when you are done with MCGraylog, you can optionally shut it down
  graylog_deinit();
}
```

The full API is documented in `MCGraylog.h`. For testing, it may
be easier to setup Logstash, which can understand GELF, instead
of setting up Graylog for testing.

We use Logstash to test MCGraylog, so you can reference our test
configuration (and files) to get started more quickly.


## Contributing to MCGraylog

See CONTRIBUTING.markdown


## Copyright

Copyright (c) 2013, Marketcircle Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.
* Neither the name of Marketcircle Inc. nor the names of its
  contributors may be used to endorse or promote products derived
  from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Marketcircle Inc. BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
