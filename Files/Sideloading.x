// All Codes are adapt from YTLite and uYouEnhanced + Some of my research
#import "Headers.h"

// ─── Cached class references ──────────────────────────────────────────────────
static Class cls_YTUIUtils;

// AccessGroupID — result cached after first Keychain lookup.
// SecItemCopyMatching / SecItemAdd are IPC calls into securityd; running them
// on every keychain operation was expensive. The access group never changes at
// runtime so a single dispatch_once result is correct.
static NSString *accessGroupID(void) {
    static NSString *cachedGroup;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *query = @{
            (__bridge NSString *)kSecClass:            (__bridge NSString *)kSecClassGenericPassword,
            (__bridge NSString *)kSecAttrAccount:      @"bundleSeedID",
            (__bridge NSString *)kSecAttrService:      @"",
            (__bridge NSString *)kSecReturnAttributes: @YES,
        };
        CFDictionaryRef result = nil;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
        if (status == errSecItemNotFound) {
            status = SecItemAdd((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
        }
        if (status == errSecSuccess && result) {
            cachedGroup = [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kSecAttrAccessGroup];
            CFRelease(result);
        }
    });
    return cachedGroup;
}

// IAmYouTube (https://github.com/PoomSmart/IAmYouTube)
%hook YTVersionUtils
+ (NSString *)appName { return YT_NAME; }
+ (NSString *)appID { return YT_BUNDLE_ID; }
%end

%hook GCKBUtils
+ (NSString *)appIdentifier { return YT_BUNDLE_ID; }
%end

%hook GPCDeviceInfo
+ (NSString *)bundleId { return YT_BUNDLE_ID; }
%end

%hook OGLBundle
+ (NSString *)shortAppName { return YT_NAME; }
%end

%hook GVROverlayView
+ (NSString *)appName { return YT_NAME; }
%end

%hook OGLPhenotypeFlagServiceImpl
- (NSString *)bundleId { return YT_BUNDLE_ID; }
%end

%hook APMAEU
+ (BOOL)isFAS { return YES; }
%end

%hook GULAppEnvironmentUtil
+ (BOOL)isFromAppStore { return YES; }
%end

%hook SSOClientLogin
+ (NSString *)defaultSourceString { return YT_BUNDLE_ID; }
%end

%hook SSOConfiguration
- (id)initWithClientID:(id)clientID supportedAccountServices:(id)supportedAccountServices {
    self = %orig;
    [self setValue:YT_NAME forKey:@"_shortAppName"];
    [self setValue:YT_BUNDLE_ID forKey:@"_applicationIdentifier"];
    return self;
}
%end

%hook YTHotConfig
- (BOOL)clientInfraClientConfigIosEnableFillingEncodedHacksInnertubeContext { return NO; }
%end

%hook NSBundle
+ (NSBundle *)bundleWithIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:YT_BUNDLE_ID])
        return NSBundle.mainBundle;
    return %orig(identifier);
}
- (NSString *)bundleIdentifier {
    return [self isEqual:NSBundle.mainBundle] ? YT_BUNDLE_ID : %orig;
}
- (NSDictionary *)infoDictionary {
    NSDictionary *dict = %orig;
    if (![self isEqual:NSBundle.mainBundle])
        return %orig;
    NSMutableDictionary *info = [dict mutableCopy];
    if (info[@"CFBundleIdentifier"]) info[@"CFBundleIdentifier"] = YT_BUNDLE_ID;
    if (info[@"CFBundleDisplayName"]) info[@"CFBundleDisplayName"] = YT_NAME;
    if (info[@"CFBundleName"]) info[@"CFBundleName"] = YT_NAME;
    return info;
}
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (![self isEqual:NSBundle.mainBundle])
        return %orig;
    if ([key isEqualToString:@"CFBundleIdentifier"])
        return YT_BUNDLE_ID;
    if ([key isEqualToString:@"CFBundleDisplayName"] || [key isEqualToString:@"CFBundleName"])
        return YT_NAME;
    return %orig;
}
%end

// AccessGroupID — all keychain helpers use the cached version.
%hook SSOKeychainHelper
+ (id)accessGroup { return accessGroupID(); }
+ (id)sharedAccessGroup { return accessGroupID(); }
%end

%hook SSOFolsomKeychainUtils
- (id)sharedAccessGroup { return accessGroupID(); }
%end

%hook GULKeychainStorage
- (void)getObjectForKey:(id)key objectClass:(Class)objectClass accessGroup:(id)accessGroup completionHandler:(id)handler {
    accessGroup = accessGroupID();
    %orig(key, objectClass, accessGroup, handler);
}
- (void)setObject:(id)object forKey:(id)key accessGroup:(id)accessGroup completionHandler:(id)handler {
    accessGroup = accessGroupID();
    %orig(object, key, accessGroup, handler);
}
- (void)removeObjectForKey:(id)key accessGroup:(id)accessGroup completionHandler:(id)handler {
    accessGroup = accessGroupID();
    %orig(key, accessGroup, handler);
}
- (void)getObjectFromKeychainForKey:(id)key objectClass:(Class)objectClass accessGroup:(id)accessGroup completionHandler:(id)handler {
    accessGroup = accessGroupID();
    %orig(key, objectClass, accessGroup, handler);
}
- (id)keychainQueryWithKey:(id)key accessGroup:(id)accessGroup {
    accessGroup = accessGroupID();
    return %orig(key, accessGroup);
}
%end

%hook GNPEncryptionConfiguration
- (id)initWithKeychainAccessGroup:(id)arg {
    arg = accessGroupID();
    return %orig(arg);
}
- (id)keychainAccessGroup { return accessGroupID(); }
%end

%hook FIRInstallationsStore
- (id)initWithSecureStorage:(id)arg1 accessGroup:(id)arg2 {
    arg2 = accessGroupID();
    return %orig(arg1, arg2);
}
- (id)accessGroup { return accessGroupID(); }
%end

%hook CHMConfiguration
- (void)setKeychainAccessGroup:(id)arg {
    arg = accessGroupID();
    %orig(arg);
}
- (id)keychainAccessGroup { return accessGroupID(); }
%end

// Fix "Open in YouTube" routing to App Store instead of this app.
// When YouTube builds a youtube:// or vnd.youtube:// URL for "open in YouTube app",
// iOS looks for another installed app that handles that scheme. Since YouMod spoofs
// the bundle ID, the system finds the real YouTube on the App Store instead.
// We intercept those URLs, extract the video/playlist ID, and open the watch screen
// in-process via YTUIUtils rather than handing off to iOS at all.
%hook UIApplication
- (BOOL)openURL:(NSURL *)url {
    if (url && ([url.scheme isEqualToString:@"youtube"] || [url.scheme isEqualToString:@"vnd.youtube"])) {
        NSString *host = url.host;
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSString *videoID = nil;
        NSString *playlistID = nil;
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name isEqualToString:@"v"]) videoID = item.value;
            if ([item.name isEqualToString:@"list"]) playlistID = item.value;
        }
        if (!videoID && host.length == 11) videoID = host;
        if (videoID.length > 0) {
            NSString *watchURL = playlistID
                ? [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@&list=%@", videoID, playlistID]
                : [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@", videoID];
            [cls_YTUIUtils openURL:[NSURL URLWithString:watchURL]];
            return YES;
        }
    }
    return %orig(url);
}
- (void)openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey, id> *)options completionHandler:(void (^)(BOOL))completion {
    if (url && ([url.scheme isEqualToString:@"youtube"] || [url.scheme isEqualToString:@"vnd.youtube"])) {
        NSString *host = url.host;
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSString *videoID = nil;
        NSString *playlistID = nil;
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name isEqualToString:@"v"]) videoID = item.value;
            if ([item.name isEqualToString:@"list"]) playlistID = item.value;
        }
        if (!videoID && host.length == 11) videoID = host;
        if (videoID.length > 0) {
            NSString *watchURL = playlistID
                ? [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@&list=%@", videoID, playlistID]
                : [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@", videoID];
            [cls_YTUIUtils openURL:[NSURL URLWithString:watchURL]];
            if (completion) completion(YES);
            return;
        }
    }
    %orig(url, options, completion);
}
%end

// Fixes crash/data saving
%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    if (groupIdentifier != nil) {
        NSArray *paths = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
        NSURL *documentsURL = [paths lastObject];
        return [documentsURL URLByAppendingPathComponent:@"AppGroup"];
    }
    return %orig;
}
%end

%ctor {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls_YTUIUtils = %c(YTUIUtils);
    });
}
