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

#include "config.h"

#import "Test.h"
#import "PlatformUtilities.h"

#include <wtf/RetainPtr.h>

#if WK_API_ENABLED && !PLATFORM(IOS)

static bool doneOpening;
static bool doneLoading;

@interface WKOpenPanelTestDelegate : NSObject <WKUIDelegate, WKNavigationDelegate>
@end

@implementation WKOpenPanelTestDelegate

- (void)webView:(WKWebView *)webView runOpenPanelWithResultListener:(id<WKOpenPanelResultListener>)listener parameters:(WKUIOpenPanelParameters *)parameters
{
    EXPECT_NOT_NULL(webView);
    EXPECT_NOT_NULL(listener);
    EXPECT_NOT_NULL(parameters);
    doneOpening = true;
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    doneLoading = true;
}

@end

namespace TestWebKitAPI {

TEST(WebKit2, OpenPanelTest)
{
    auto webView = adoptNS([[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)]);
    auto delegate = adoptNS([[WKOpenPanelTestDelegate alloc] init]);

    auto window = adoptNS([[NSWindow alloc] initWithContentRect:[webView.get() frame] styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES]);
    [[window.get() contentView] addSubview:webView.get()];

    webView.get().UIDelegate = delegate.get();
    webView.get().navigationDelegate = delegate.get();

    NSURLRequest *request = [NSURLRequest requestWithURL:[[NSBundle mainBundle] URLForResource:@"basic-input-element" withExtension:@"html" subdirectory:@"TestWebKitAPI.resources"]];

    [webView.get() loadRequest:request];

    Util::run(&doneLoading);

    NSPoint clickPoint = NSMakePoint(100, 100);

    [[webView hitTest:clickPoint] mouseDown:[NSEvent mouseEventWithType:NSLeftMouseDown location:clickPoint modifierFlags:0 timestamp:0 windowNumber:[window.get() windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1]];

    [[webView hitTest:clickPoint] mouseUp:[NSEvent mouseEventWithType:NSLeftMouseUp location:clickPoint modifierFlags:0 timestamp:0 windowNumber:[window.get() windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1]];

    Util::run(&doneOpening);

    doneLoading = false;
    doneOpening = false;
}

}

#endif // WK_API_ENABLED && !PLATFORM(IOS)

