#import "DouyinPlugin.h"
#import "DouyinOpenSDKAuth.h"

@interface DouyinPlugin ()

@property(nonatomic, strong) FlutterMethodChannel *channel;

@end

@implementation DouyinPlugin
+ (void)registerWithRegistrar:(NSObject <FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *channel = [FlutterMethodChannel
            methodChannelWithName:@"douyin"
                  binaryMessenger:[registrar messenger]];
    DouyinPlugin *instance = [[DouyinPlugin alloc] init];
    instance.channel = channel;
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([@"init" isEqualToString:call.method]) {
        [self handleInitCall:call];
        result(@"success");
    } else if ([@"AuthorizedLogin" isEqualToString:call.method]) {
        [self handleAuthorCall:call];
        result(@"success");
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)handleAuthorCall:(FlutterMethodCall *)call {
    NSDictionary *args = call.arguments;
    NSString *scopeKey = [args valueForKey:@"scope"];
    NSArray *components = [scopeKey componentsSeparatedByString:@","];
    NSOrderedSet *permission = [NSOrderedSet orderedSetWithArray:components];
    DouyinOpenSDKAuthRequest *request = [[DouyinOpenSDKAuthRequest alloc] init];
    NSOrderedSet *additionalPermission = [NSOrderedSet orderedSetWithObjects:@{@"permission": @"mobile"}, nil];
    request.permissions = permission;
    request.additionalPermissions = additionalPermission;
    [request sendAuthRequestViewController:self.getCurrentViewController completeBlock:^(DouyinOpenSDKAuthResponse *resp) {
        NSDictionary *arguments = @{
                @"code": @(resp.errCode),
                @"permission": [resp.grantedPermissions.array componentsJoinedByString:@","],
                @"authCode": resp.code
        };
        [self.channel invokeMethod:@"onAuthorCallback" arguments:arguments];
    }];
}

- (void)handleInitCall:(FlutterMethodCall *)call {
    NSDictionary *args = call.arguments;
    NSString *apiKey = [args valueForKey:@"apiKey"];
    [[DouyinOpenSDKApplicationDelegate sharedInstance] registerAppId:apiKey];
}

- (UIViewController *)getCurrentViewController {
    UIApplication *sharedApplication = [UIApplication sharedApplication];
    UIWindow *keyWindow = sharedApplication.keyWindow;
    UIViewController *rootViewController = keyWindow.rootViewController;

    return [self currentViewControllerFrom:rootViewController];
}

- (UIViewController *)currentViewControllerFrom:(UIViewController *)viewController {
    while (viewController) {
        if ([viewController isKindOfClass:[UITabBarController class]]) {
            viewController = ((UITabBarController *) viewController).selectedViewController;
        } else if ([viewController isKindOfClass:[UINavigationController class]]) {
            viewController = ((UINavigationController *) viewController).visibleViewController;
        } else if (viewController.presentedViewController) {
            viewController = viewController.presentedViewController;
        } else {
            break;
        }
    }
    return viewController;
}


@end
