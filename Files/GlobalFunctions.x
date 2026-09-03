#import "Headers.h"

// YouMod's bundle (For localizations)
NSBundle *YouModBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"YouMod" ofType:@"bundle"];
        if (tweakBundlePath) {
            bundle = [NSBundle bundleWithPath:tweakBundlePath];
        } else {
            bundle = [NSBundle bundleWithPath:[NSString stringWithFormat:jbroot(@"/Library/Application Support/%@.bundle"), @"YouMod"]];
        }
    });
    return bundle;
}

// YouTube icon image (YTIIcon)
UIImage *YouModYTIconImage(NSInteger iconType, BOOL useCustomColor, UIColor *customColor) {
    YTIIcon *icon = [%c(YTIIcon) new];
    icon.iconType = iconType;
    UIColor *targetColor = (useCustomColor && customColor) ? customColor : [UIColor labelColor];
    return [icon iconImageWithColor:targetColor];
}

// Language list
NSArray *getAllSystemLanguageTitles() {
    NSMutableArray *titles = [NSMutableArray array];
    NSArray *allLocales = [%c(YTLanguages) languageList];
    NSMutableSet *seenLanguages = [NSMutableSet set];
    NSLocale *currentLocale = [NSLocale currentLocale];
    
    for (NSString *localeId in allLocales) {
        NSDictionary *components = [NSLocale componentsFromLocaleIdentifier:localeId];
        NSString *langCode = components[NSLocaleLanguageCode];
        
        if (langCode && ![seenLanguages containsObject:langCode]) {
            [seenLanguages addObject:langCode];
            NSString *displayName = [currentLocale localizedStringForLocaleIdentifier:langCode];
            if (displayName) [titles addObject:displayName];
        }
    }
    return [titles sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

NSArray *getAllSystemLanguageValues() {
    NSArray *sortedTitles = getAllSystemLanguageTitles();
    NSMutableArray *sortedCodes = [NSMutableArray array];
    NSArray *allLocales = [%c(YTLanguages) languageList];
    NSLocale *currentLocale = [NSLocale currentLocale];
    
    NSMutableDictionary *titleToCodeMap = [NSMutableDictionary dictionary];
    for (NSString *localeId in allLocales) {
        NSDictionary *components = [NSLocale componentsFromLocaleIdentifier:localeId];
        NSString *langCode = components[NSLocaleLanguageCode];
        if (langCode) {
            NSString *displayName = [currentLocale localizedStringForLocaleIdentifier:langCode];
            if (displayName) titleToCodeMap[displayName] = langCode;
        }
    }
    
    for (NSString *title in sortedTitles) {
        [sortedCodes addObject:titleToCodeMap[title] ? titleToCodeMap[title] : @"en"];
    }
    return [sortedCodes copy];
}

// Get TopViewController
UIViewController *YouModTopViewController(UIViewController *root) {
    if (!root) {
        UIWindow *keyWindow = nil;
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        root = keyWindow.rootViewController;
    }
    while (root.presentedViewController) root = root.presentedViewController;
    if ([root isKindOfClass:UINavigationController.class])
        return YouModTopViewController(((UINavigationController *)root).topViewController);
    if ([root isKindOfClass:UITabBarController.class])
        return YouModTopViewController(((UITabBarController *)root).selectedViewController);
    return root;
}

// ─── Preferences cache ────────────────────────────────────────────────────────
// Replaces per-call NSUserDefaults IPC with a single in-memory snapshot.
// Rebuilt on launch and whenever the settings UI posts YouModPrefsDidChange.

static NSDictionary *gYMPrefsSnapshot = nil;
static dispatch_once_t gYMPrefsOnce;

NSDictionary *YMPrefsSnapshot(void) {
    dispatch_once(&gYMPrefsOnce, ^{ YMReloadPrefsCache(); });
    return gYMPrefsSnapshot ?: @{};
}

void YMReloadPrefsCache(void) {
    // Grab the whole persistent domain for this app in one IPC round-trip.
    NSString *domain = [[NSBundle mainBundle] bundleIdentifier] ?: @"com.google.ios.youtube";
    NSDictionary *fresh = [[NSUserDefaults standardUserDefaults] persistentDomainForName:domain];
    // Merge with standardUserDefaults registered defaults so IS_ENABLED works
    // for keys that were never explicitly written (i.e., their default is NO/0).
    NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:
                                   [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]];
    if (fresh) [merged addEntriesFromDictionary:fresh];
    gYMPrefsSnapshot = [merged copy];
}

// OLEDKeyboard (https://github.com/dayanch96/OledKeyboard)
BOOL isDarkMode(UIView *view) {
    if ([view respondsToSelector:@selector(_mapkit_isDarkModeEnabled)]) {
        return view._mapkit_isDarkModeEnabled;
    }
    return view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
}

BOOL isPad() {
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
}