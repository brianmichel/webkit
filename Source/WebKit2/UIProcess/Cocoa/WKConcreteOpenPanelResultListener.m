/*
 * Copyright (C) 2015 Brian Michel (brian.michel@gmail.com). All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "config.h"
#import "WKConcreteOpenPanelResultListener.h"

#if WK_API_ENABLED

#import "APIArray.h"
#import "APIObject.h"
#import "WKFoundation.h"
#import "WKSharedAPICast.h"
#import "WKURLCF.h"
#import "WebOpenPanelResultListenerProxy.h"

using namespace WebKit;

@implementation WKConcreteOpenPanelResultListener {
    WebOpenPanelResultListenerProxy *m_listener;
}

- (instancetype)initWithListenerProxy:(WebOpenPanelResultListenerProxy *)proxy {
    ASSERT_ARG(proxy, proxy);
    self = [super init];
    if (self)
        m_listener = proxy;

    return self;
}

#pragma mark - WKOpenPanelResultListener

- (void)chooseFiles:(NSArray *)fileURLs {
    NSUInteger count = [fileURLs count];
    if (!count)
        m_listener->cancel();
    else {
        Vector<RefPtr<API::Object>> urls;
        urls.reserveInitialCapacity(count);

        for (NSURL *fileURL in fileURLs)
            urls.uncheckedAppend(adoptRef(toImpl(WKURLCreateWithCFURL((CFURLRef)fileURL))));

        RefPtr<API::Array> fileURLsRef = API::Array::create(WTF::move(urls));
        m_listener->chooseFiles(fileURLsRef.get());
    }
}

- (void)cancel {
    m_listener->cancel();
}

@end

#endif // WK_API_ENABLED
