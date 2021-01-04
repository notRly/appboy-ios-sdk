#import "ABKInAppMessageHTMLBaseViewController.h"
#import "ABKInAppMessageView.h"
#import "ABKUIUtils.h"
#import "ABKInAppMessageWindowController.h"
#import "ABKInAppMessageWebViewBridge.h"

static NSString *const ABKBlankURLString = @"about:blank";
static NSString *const ABKHTMLInAppButtonIdKey = @"abButtonId";
static NSString *const ABKHTMLInAppAppboyKey = @"appboy";
static NSString *const ABKHTMLInAppCloseKey = @"close";
static NSString *const ABKHTMLInAppFeedKey = @"feed";
static NSString *const ABKHTMLInAppCustomEventKey = @"customEvent";
static NSString *const ABKHTMLInAppCustomEventQueryParamNameKey = @"name";
static NSString *const ABKHTMLInAppExternalOpenKey = @"abExternalOpen";
static NSString *const ABKHTMLInAppDeepLinkKey = @"abDeepLink";
static NSString *const ABKHTMLInAppJavaScriptExtension = @"js";

@interface ABKInAppMessageHTMLBaseViewController () <ABKInAppMessageWebViewBridgeDelegate>

@property (nonatomic) ABKInAppMessageWebViewBridge *webViewBridge;

@end

@implementation ABKInAppMessageHTMLBaseViewController

#pragma mark - View Lifecycle

- (void)loadView {
  // View is full screen and covers status bar. It needs to be an ABKInAppMessageView to
  // ensure touches register as per custom logic in ABKInAppMessageWindow
  self.view = [[ABKInAppMessageView alloc] initWithFrame:[UIScreen mainScreen].bounds];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  self.view.translatesAutoresizingMaskIntoConstraints = NO;
  
  NSLayoutConstraint *leadConstraint = [NSLayoutConstraint constraintWithItem:self.view
                                                                    attribute:NSLayoutAttributeLeading
                                                                    relatedBy:NSLayoutRelationEqual
                                                                       toItem:self.view.superview
                                                                    attribute:NSLayoutAttributeLeading
                                                                   multiplier:1
                                                                     constant:0.0];
  NSLayoutConstraint *trailConstraint = [NSLayoutConstraint constraintWithItem:self.view.superview
                                                                     attribute:NSLayoutAttributeTrailing
                                                                     relatedBy:NSLayoutRelationEqual
                                                                        toItem:self.view
                                                                     attribute:NSLayoutAttributeTrailing
                                                                    multiplier:1
                                                                      constant:0.0];
  self.topConstraint = [NSLayoutConstraint constraintWithItem:self.view
                                                    attribute:NSLayoutAttributeTop
                                                    relatedBy:NSLayoutRelationEqual
                                                       toItem:self.view.superview
                                                    attribute:NSLayoutAttributeTop
                                                   multiplier:1
                                                     constant:self.view.frame.size.height];
  self.bottomConstraint = [NSLayoutConstraint constraintWithItem:self.view
                                                       attribute:NSLayoutAttributeBottom
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:self.view.superview
                                                       attribute:NSLayoutAttributeBottom
                                                      multiplier:1
                                                        constant:self.view.frame.size.height];
  [self.view.superview addConstraints:@[leadConstraint, trailConstraint, self.topConstraint, self.bottomConstraint]];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.edgesForExtendedLayout = UIRectEdgeNone;
  WKWebViewConfiguration *webViewConfiguration = [[WKWebViewConfiguration alloc] init];
  webViewConfiguration.allowsInlineMediaPlayback = YES;
  webViewConfiguration.suppressesIncrementalRendering = YES;
  if (@available(iOS 10.0, *)) {
    webViewConfiguration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
  } else {
    webViewConfiguration.requiresUserActionForMediaPlayback = NO;
  }
  
  ABKInAppMessageWindowController *parentViewController =
    (ABKInAppMessageWindowController *)self.parentViewController;
  if ([parentViewController.inAppMessageUIDelegate respondsToSelector:@selector(setCustomWKWebViewConfiguration)]) {
    webViewConfiguration = [parentViewController.inAppMessageUIDelegate setCustomWKWebViewConfiguration];
  }

  WKWebView *webView = [[WKWebView alloc] initWithFrame:self.view.frame configuration:webViewConfiguration];
  self.webView = webView;
  
  self.webViewBridge = [[ABKInAppMessageWebViewBridge alloc] initWithWebView:webView
                                                                inAppMessage:(ABKInAppMessageHTML *)self.inAppMessage appboyInstance:[Appboy sharedInstance]];
  self.webViewBridge.delegate = self;

  self.webView.allowsLinkPreview = NO;
  self.webView.navigationDelegate = self;
  self.webView.UIDelegate = self;
  self.webView.scrollView.bounces = NO;
  
  // Handle resizing during orientation changes
  self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

  if (@available(iOS 11.0, *)) {
    // Cover status bar when showing HTML IAMs
    [self.webView.scrollView setContentInsetAdjustmentBehavior:UIScrollViewContentInsetAdjustmentNever];
  }
  if (((ABKInAppMessageHTMLBase *)self.inAppMessage).assetsLocalDirectoryPath != nil) {
    NSString *localPath = [((ABKInAppMessageHTMLBase *)self.inAppMessage).assetsLocalDirectoryPath absoluteString];
    // Here we must use fileURLWithPath: to add the "file://" scheme, otherwise the webView won't recognize the
    // base URL and won't load the zip file resources.
    NSURL *html = [NSURL fileURLWithPath:[localPath stringByAppendingPathComponent:ABKInAppMessageHTMLFileName]];
    NSString *fullPath = [localPath stringByAppendingPathComponent:ABKInAppMessageHTMLFileName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
      NSLog(@"Can't find HTML at path %@, with file name %@. Aborting display.", [NSURL fileURLWithPath:localPath], ABKInAppMessageHTMLFileName);
      [self hideInAppMessage:NO];
    }
    [self.webView loadFileURL:html allowingReadAccessToURL:[NSURL fileURLWithPath:localPath]];
  } else {
    [self.webView loadHTMLString:self.inAppMessage.message baseURL:nil];
  }
  [self.view addSubview:self.webView];

  // Sets an observer for UIKeyboardWillHideNotification. This is a workaround for the
  // keyboard dismissal bug in iOS 12+ WKWebView filed here
  // https://bugs.webkit.org/show_bug.cgi?id=192564. The workaround is also from the post.
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide) name:UIKeyboardWillHideNotification object:nil];
}

#pragma mark - Superclass methods

- (BOOL)prefersStatusBarHidden {
  return YES;
}

#pragma mark - NSNotificationCenter selectors

- (void)keyboardWillHide {
  [self.webView setNeedsLayout];
}

#pragma mark - WKDelegate methods

- (WKWebView *)webView:(WKWebView *)webView
createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures {
  if (navigationAction.targetFrame == nil) {
    [webView loadRequest:navigationAction.request];
  }
  return nil;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  NSURL *url = navigationAction.request.URL;
  
  if (url != nil &&
      ![ABKUIUtils string:url.absoluteString isEqualToString:ABKBlankURLString] &&
      ![ABKUIUtils string:url.path isEqualToString:[[(ABKInAppMessageHTMLBase *)self.inAppMessage assetsLocalDirectoryPath]
                                  absoluteString]] &&
      ![ABKUIUtils string:url.lastPathComponent isEqualToString:ABKInAppMessageHTMLFileName]) {
    [self setClickActionBasedOnURL:url];
    
    NSMutableDictionary *queryParams = [[self queryParameterDictionaryFromURL:url] mutableCopy];
    NSString *buttonId = queryParams[ABKHTMLInAppButtonIdKey];
    ABKInAppMessageWindowController *parentViewController =
      (ABKInAppMessageWindowController *)self.parentViewController;
    parentViewController.clickedHTMLButtonId = buttonId;
    
    if ([self delegateHandlesHTMLButtonClick:parentViewController.inAppMessageUIDelegate
                                         URL:url
                                    buttonId:buttonId]) {
      decisionHandler(WKNavigationActionPolicyCancel);
      return;
    } else if ([self isCustomEventURL:url]) {
      [self handleCustomEventWithQueryParams:queryParams];
      decisionHandler(WKNavigationActionPolicyCancel);
      return;
    } else if (![ABKUIUtils objectIsValidAndNotEmpty:buttonId]) {
      // Log a body click if not a custom event or a button click
      parentViewController.inAppMessageIsTapped = YES;
    }

    [parentViewController inAppMessageClickedWithActionType:self.inAppMessage.inAppMessageClickActionType
                                                        URL:url
                                           openURLInWebView:[self getOpenURLInWebView:queryParams]];
    decisionHandler(WKNavigationActionPolicyCancel);
    return;
  }

  decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  self.webView.backgroundColor = [UIColor clearColor];
  self.webView.opaque = NO;
  if (self.inAppMessage.animateIn) {
    [UIView animateWithDuration:InAppMessageAnimationDuration
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                      self.topConstraint.constant = 0;
                      self.bottomConstraint.constant = 0;
                      [self.view.superview layoutIfNeeded];
                    }
                     completion:^(BOOL finished){
                    }];
  } else {
    self.topConstraint.constant = 0;
    self.bottomConstraint.constant = 0;
    [self.view.superview layoutIfNeeded];
  }
  
  // Disable touch callout from displaying link information
  [self.webView evaluateJavaScript:@"document.documentElement.style.webkitTouchCallout='none';" completionHandler:nil];
}

- (void)webView:(WKWebView *)webView
runJavaScriptAlertPanelWithMessage:(nonnull NSString *)message
                  initiatedByFrame:(nonnull WKFrameInfo *)frame
                 completionHandler:(nonnull void (^)(void))completionHandler {
  [self presentAlertWithMessage:message
               andConfiguration:^(UIAlertController *alert) {
    // Action labels matches Safari implementation
    // Close
    [alert addAction:[UIAlertAction actionWithTitle:@"Close"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
      completionHandler();
    }]];
  }];
}

- (void)webView:(WKWebView *)webView
runJavaScriptConfirmPanelWithMessage:(NSString *)message
                    initiatedByFrame:(WKFrameInfo *)frame
                   completionHandler:(void (^)(BOOL))completionHandler {
  [self presentAlertWithMessage:message andConfiguration:^(UIAlertController *alert) {
    // Action labels matches Safari implementation
    // Cancel
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction * _Nonnull action) {
      completionHandler(NO);
    }]];
    
    // OK
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
      completionHandler(YES);
    }]];
  }];
}

- (void)webView:(WKWebView *)webView
runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
                          defaultText:(NSString *)defaultText
                     initiatedByFrame:(WKFrameInfo *)frame
                    completionHandler:(void (^)(NSString * _Nullable))completionHandler {
  [self presentAlertWithMessage:prompt
               andConfiguration:^(UIAlertController *alert) {
    // Action labels matches Safari implementation
    // Text field
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
      textField.text = defaultText;
    }];
    
    // Cancel
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction * _Nonnull action) {
      completionHandler(nil);
    }]];
    
    // OK
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
      completionHandler(alert.textFields[0].text);
    }]];
  }];
}

- (BOOL)isCustomEventURL:(NSURL *)url {
  return ([ABKUIUtils string:url.scheme.lowercaseString isEqualToString:ABKHTMLInAppAppboyKey] &&
          [ABKUIUtils string:url.host isEqualToString:ABKHTMLInAppCustomEventKey]);
}

- (BOOL)getOpenURLInWebView:(NSDictionary *)queryParams {
  if ([queryParams[ABKHTMLInAppDeepLinkKey] boolValue] | [queryParams[ABKHTMLInAppExternalOpenKey] boolValue]) {
    return NO;
  }
  return self.inAppMessage.openUrlInWebView;
}

#pragma mark - Delegate

- (BOOL)delegateHandlesHTMLButtonClick:(id<ABKInAppMessageUIDelegate>)delegate
                                   URL:(NSURL *)url
                              buttonId:(NSString *)buttonId {
  if ([delegate respondsToSelector:@selector(onInAppMessageHTMLButtonClicked:clickedURL:buttonID:)]) {
    if ([delegate onInAppMessageHTMLButtonClicked:(ABKInAppMessageHTMLBase *)self.inAppMessage
                                       clickedURL:url
                                         buttonID:buttonId]) {
      NSLog(@"No in-app message click action will be performed by Braze as in-app message delegate %@ returned YES in onInAppMessageHTMLButtonClicked:", delegate);
      return YES;
    }
  }
  return NO;
}

#pragma mark - Custom Event Handling

- (void)handleCustomEventWithQueryParams:(NSMutableDictionary *)queryParams {
  NSString *customEventName = [self parseCustomEventNameFromQueryParams:queryParams];
  NSMutableDictionary *eventProperties = [self parseCustomEventPropertiesFromQueryParams:queryParams];
  [[Appboy sharedInstance] logCustomEvent:customEventName withProperties:eventProperties];
}

- (NSString *)parseCustomEventNameFromQueryParams:(NSMutableDictionary *)queryParams {
  return queryParams[ABKHTMLInAppCustomEventQueryParamNameKey];
}

- (NSMutableDictionary *)parseCustomEventPropertiesFromQueryParams:(NSMutableDictionary *)queryParams {
  NSMutableDictionary *eventProperties = [queryParams mutableCopy];
  [eventProperties removeObjectForKey:ABKHTMLInAppCustomEventQueryParamNameKey];
  return eventProperties;
}

#pragma mark - Button Click Handling

// Set the inAppMessage's click action type based on given URL. It's going to be three types:
// * URL is appboy://close: set click action to be ABKInAppMessageNoneClickAction
// * URL is appboy://feed: set click action to be ABKInAppMessageDisplayNewsFeed
// * URL is anything else: set click action to be ABKInAppMessageRedirectToURI and the uri is the URL.
- (void)setClickActionBasedOnURL:(NSURL *)url {
  if ([ABKUIUtils string:url.scheme.lowercaseString isEqualToString:ABKHTMLInAppAppboyKey]) {
    if ([ABKUIUtils string:url.host.lowercaseString isEqualToString:ABKHTMLInAppCloseKey]) {
      [self.inAppMessage setInAppMessageClickAction:ABKInAppMessageNoneClickAction withURI:nil];
      return;
    } else if ([ABKUIUtils string:url.host.lowercaseString isEqualToString:ABKHTMLInAppFeedKey]) {
      [self.inAppMessage setInAppMessageClickAction:ABKInAppMessageDisplayNewsFeed withURI:nil];
      return;
    }
  }
  [self.inAppMessage setInAppMessageClickAction:ABKInAppMessageRedirectToURI withURI:url];
}

#pragma mark - Utility Methods

- (NSDictionary *)queryParameterDictionaryFromURL:(NSURL *)url {
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
  for (NSURLQueryItem *queryItem in components.queryItems) {
    dict[queryItem.name] = queryItem.value;
  }

  return [dict copy];
}

- (void)presentAlertWithMessage:(NSString *)message
               andConfiguration:(void (^)(UIAlertController *alert))configure {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                 message:message
                                                          preferredStyle:UIAlertControllerStyleAlert];
  configure(alert);
  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Animation

- (void)beforeMoveInAppMessageViewOnScreen {}

- (void)moveInAppMessageViewOnScreen {
  // Do nothing - moving the in-app message is handled in didFinishNavigation
  // though that logic should probably be gated by a call here. In a perfect world,
  // ABKInAppMessageWindowController would "request" VC's to show themselves,
  // and the VC's would report when they were shown so ABKInAppMessageWindowController
  // could log impressions.
}

- (void)beforeMoveInAppMessageViewOffScreen {
  self.topConstraint.constant = self.view.frame.size.height;
  self.bottomConstraint.constant = self.view.frame.size.height;
}

- (void)moveInAppMessageViewOffScreen {
  [self.view.superview layoutIfNeeded];
}

#pragma mark - ABKInAppMessageWebViewBridgeDelegate

- (void)webViewBridge:(ABKInAppMessageWebViewBridge *)webViewBridge
  receivedClickAction:(ABKInAppMessageClickActionType)clickAction {
  ABKInAppMessageWindowController *parentViewController =
    (ABKInAppMessageWindowController *)self.parentViewController;
  
  [self.inAppMessage setInAppMessageClickAction:clickAction withURI:nil];
  [parentViewController inAppMessageClickedWithActionType:self.inAppMessage.inAppMessageClickActionType
                                                      URL:nil
                                         openURLInWebView:false];
}

@end
