#import "GeneratedPluginRegistrant.h"
#import "AppDelegate.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  [GeneratedPluginRegistrant registerWithRegistry:self];
  // Additional setup after plugin registration
  return [super application:application didFinishLaunchingWithOptions:launchOptions];
}

@end
