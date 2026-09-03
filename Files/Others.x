#import "Headers.h"

// Background playback
%hook MLVideo
- (BOOL)playableInBackground { return IS_ENABLED(BackgroundPlayback) ? YES : %orig; }
%end

%hook YTIPlayabilityStatus
- (BOOL)isPlayableInBackground { return IS_ENABLED(BackgroundPlayback) ? YES : %orig; }
%end

%hook YTPlaybackData
- (BOOL)isPlayableInBackground { return IS_ENABLED(BackgroundPlayback) ? YES : %orig; }
%end

%hook YTIPlayerResponse
- (BOOL)isPlayableInBackground { return IS_ENABLED(BackgroundPlayback) ? YES : %orig; }
%end

%hook YTColdConfig
// Try to disable Shorts PiP
- (BOOL)shortsPlayerGlobalConfigEnableReelsPictureInPicture { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
- (BOOL)shortsPlayerGlobalConfigEnableReelsPictureInPictureIos { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
// Hide startup animations
- (BOOL)mainAppCoreClientIosEnableStartupAnimation { return IS_ENABLED(HideStartupAni) ? NO : %orig; }
// Prevent YouTube from asking "Are you there?"
- (BOOL)enableYouthereCommandsOnIos { return IS_ENABLED(BlockUpgradeDialogs) ? NO : %orig; }
// Fixes slow miniplayer
- (BOOL)enableIosFloatingMiniplayerDoubleTapToResize { return IS_ENABLED(FixesSlowMiniPlayer) ? NO : %orig; }
// Use old miniplayer
- (BOOL)enableIosFloatingMiniplayer { return IS_ENABLED(DisablesNewMiniPlayer) ? NO : %orig; }
%end

%hook YTHotConfig
- (BOOL)shortsPlayerGlobalConfigEnableReelsPictureInPictureAllowedFromPlayer { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
%end

%hook YTReelModel
- (BOOL)isPiPSupported { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
%end

%hook YTReelPlayerViewController
- (BOOL)isPictureInPictureAllowed { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
- (void)setupPlayerForPiP { if (!IS_ENABLED(DisablesShortsPiP)) %orig; }
%end

%hook YTReelWatchRootViewController
- (void)switchToPictureInPicture { if (!IS_ENABLED(DisablesShortsPiP)) %orig; }
%end

// Disable Hints
%hook YTSettings
- (BOOL)areHintsDisabled { return IS_ENABLED(DisableHints) ? YES : %orig; }
- (void)setHintsDisabled:(BOOL)arg1 {
    BOOL temp = IS_ENABLED(DisableHints) ? YES : arg1;
    %orig(temp);
}
%end

%hook YTSettingsImpl
- (BOOL)areHintsDisabled { return IS_ENABLED(DisableHints) ? YES : %orig; }
- (void)setHintsDisabled:(BOOL)arg1 {
    BOOL temp = IS_ENABLED(DisableHints) ? YES : arg1;
    %orig(temp);
}
%end

%hook YTUserDefaults
- (BOOL)areHintsDisabled { return IS_ENABLED(DisableHints) ? YES : %orig; }
- (void)setHintsDisabled:(BOOL)arg1 {
    BOOL temp = IS_ENABLED(DisableHints) ? YES : arg1;
    %orig(temp);
}
%end

// Block upgrade dialogs
%hook YTGlobalConfig
- (BOOL)shouldBlockUpgradeDialog { return IS_ENABLED(BlockUpgradeDialogs) ? YES : %orig; }
- (BOOL)shouldShowUpgradeDialog { return IS_ENABLED(BlockUpgradeDialogs) ? NO : %orig; }
- (BOOL)shouldShowUpgrade { return IS_ENABLED(BlockUpgradeDialogs) ? NO : %orig; }
- (BOOL)shouldForceUpgrade { return IS_ENABLED(BlockUpgradeDialogs) ? NO : %orig; }
%end

%hook YTYouThereController
- (BOOL)shouldShowYouTherePrompt { return IS_ENABLED(HideAreYouThereDialog) ? NO : %orig; }
- (void)showYouTherePrompt { if (!IS_ENABLED(HideAreYouThereDialog)) %orig; }
%end

%hook YTYouThereControllerImpl
- (BOOL)shouldShowYouTherePrompt { return IS_ENABLED(HideAreYouThereDialog) ? NO : %orig; }
- (void)showYouTherePrompt { if (!IS_ENABLED(HideAreYouThereDialog)) %orig; }
%end

// Disables Snackbar
%hook GOOHUDManagerInternal
- (id)sharedInstance { return IS_ENABLED(DisablesSnackBar) ? nil : %orig; }
- (void)showMessageMainThread:(id)arg { if (!IS_ENABLED(DisablesSnackBar)) %orig; }
- (void)activateOverlay:(id)arg { if (!IS_ENABLED(DisablesSnackBar)) %orig; }
- (void)displayHUDViewForMessage:(id)arg { if (!IS_ENABLED(DisablesSnackBar)) %orig; }
%end

// Remove "Play next in queue" from the menu @PoomSmart (https://github.com/qnblackcat/uYouPlus/issues/1138#issuecomment-1606415080)
%hook YTMenuItemVisibilityHandler
- (BOOL)shouldShowServiceItemRenderer:(YTIMenuConditionalServiceItemRenderer *)renderer {
    int iconnum = renderer.icon.iconType;
    if (iconnum == 251 && IS_ENABLED(RemovePlayInNextQueueOption)) {
        return NO;
    }
    if (iconnum == 895 && IS_ENABLED(RemoveAddToLastQueueOption)) {
        return NO;
    }
    return %orig;
}
%end

%hook YTMenuItemVisibilityHandlerImpl
- (BOOL)shouldShowServiceItemRenderer:(YTIMenuConditionalServiceItemRenderer *)renderer {
    int iconnum = renderer.icon.iconType;
    if (iconnum == 251 && IS_ENABLED(RemovePlayInNextQueueOption)) {
        return NO;
    }
    if (iconnum == 895 && IS_ENABLED(RemoveAddToLastQueueOption)) {
        return NO;
    }
    return %orig;
}
%end

// Remove flyout menu options
// ─── Optimisation notes ───────────────────────────────────────────────────────
// The old implementation rebuilt two NSDictionary literals on every single
// addAction: call and called [button.currentImage description] (which
// serialises image metadata to a string) unconditionally. With 10–20 items
// per menu and menus opening frequently this was measurable.
//
// New approach:
//  • Both filter sets are NSSet singletons rebuilt from prefs only when the
//    prefs cache is invalidated (i.e. when the user changes a setting).
//    Between settings changes every menu open is pure NSSet lookups.
//  • [button.currentImage description] is deferred until after the
//    identifier check passes, so it's only called when iden didn't match.
//  • The image-name scan uses a static array of (fragment, key) pairs instead
//    of iterating an NSDictionary's unordered keys.
// ─────────────────────────────────────────────────────────────────────────────

// Rebuild both filter sets from the current prefs snapshot.
// Called once at startup and again after any settings change.
static NSSet *ymActionIdentSet    = nil;
static NSSet *ymActionImageSet    = nil; // image-name fragments to block
static dispatch_once_t ymActionSetsOnce;

static void ymRebuildActionSets(void) {
    NSMutableSet *identSet = [NSMutableSet set];
    if (IS_ENABLED(RemoveDownloadOption))          [identSet addObject:@"7"];
    if (IS_ENABLED(RemoveWatchLaterOption))        [identSet addObject:@"1"];
    if (IS_ENABLED(RemoveSaveOption))              [identSet addObject:@"3"];
    if (IS_ENABLED(RemoveRemoveFromPlaylistOption)) [identSet addObject:@"4"];
    if (IS_ENABLED(RemoveShareOption))             { [identSet addObject:@"5"]; [identSet addObject:@"6"]; }
    if (IS_ENABLED(RemoveNotInterestedOption))     [identSet addObject:@"12"];
    if (IS_ENABLED(RemoveInfoOption))              [identSet addObject:@"22"];
    if (IS_ENABLED(RemoveFilterOption))            [identSet addObject:@"36"];
    if (IS_ENABLED(RemoveNotifyOption))            [identSet addObject:@"40"];
    if (IS_ENABLED(RemoveReportOption))            [identSet addObject:@"58"];
    ymActionIdentSet = [identSet copy];

    NSMutableSet *imageSet = [NSMutableSet set];
    if (IS_ENABLED(RemoveYouTubeMusicOption))     [imageSet addObject:@"youtube_music"];
    if (IS_ENABLED(RemoveReportOption))           [imageSet addObject:@"flag"];
    if (IS_ENABLED(RemoveFeedBackOption))         [imageSet addObject:@"alert_bubble"];
    if (IS_ENABLED(RemoveSaveOption))             [imageSet addObject:@"bookmark"];
    if (IS_ENABLED(RemoveNotInterestedOption))    [imageSet addObject:@"circle_slash"];
    if (IS_ENABLED(RemoveDontRecommendOption))    [imageSet addObject:@"x_circle"];
    if (IS_ENABLED(RemoveCastOption))             [imageSet addObject:@"chromecast"];
    if (IS_ENABLED(RemoveShuffleOption))          [imageSet addObject:@"shuffle"];
    if (IS_ENABLED(RemoveUnSubOption))            [imageSet addObject:@"person_x"];
    if (IS_ENABLED(RemoveHelpOption))             [imageSet addObject:@"help_circle"];
    if (IS_ENABLED(RemoveHideFromPlaylistOption)) [imageSet addObject:@"eye_slash"];
    if (IS_ENABLED(RemoveClearScreenOption))      [imageSet addObject:@"player_full_enter_alt"];
    if (IS_ENABLED(RemoveInfoOption))             [imageSet addObject:@"info_circle"];
    ymActionImageSet = [imageSet copy];
}

%hook YTDefaultSheetController
- (void)addAction:(YTActionSheetAction *)action {
    // Lazy-init on first menu open; rebuilt on prefs change via notification.
    dispatch_once(&ymActionSetsOnce, ^{ ymRebuildActionSets(); });

    UIButton *button = action.button;
    NSString *iden = button.accessibilityIdentifier;

    // Fast path 1: identifier match (no image work needed)
    if (iden && [ymActionIdentSet containsObject:iden]) return;

    // Fast path 2: image-name fragment match — only call description here
    if (ymActionImageSet.count > 0) {
        NSString *imageName = [button.currentImage description];
        if (imageName) {
            for (NSString *fragment in ymActionImageSet) {
                if ([imageName containsString:fragment]) return;
            }
        }
    }

    %orig;
}
%end

// YTSlientVote (https://github.com/PoomSmart/YTSilentVote)
%hook YTInnerTubeResponseWrapper
- (id)initWithResponse:(id)response cacheContext:(id)arg2 requestStatistics:(id)arg3 mutableSharedData:(id)arg4 {
    if (!IS_ENABLED(HideLikeDislikeVotes)) return %orig;
    if ([response isKindOfClass:%c(YTILikeResponse)]
        || [response isKindOfClass:%c(YTIDislikeResponse)]
        || [response isKindOfClass:%c(YTIRemoveLikeResponse)]) return nil;
    return %orig;
}
%end

%hook NSParagraphStyle
+ (NSWritingDirection)defaultWritingDirectionForLanguage:(id)lang { return IS_ENABLED(DisablesRTL) ? NSWritingDirectionLeftToRight : %orig; }
+ (NSWritingDirection)_defaultWritingDirection { return IS_ENABLED(DisablesRTL) ? NSWritingDirectionLeftToRight : %orig; }
%end

%hook UIDevice
- (UIUserInterfaceIdiom)userInterfaceIdiom {
    if (INTFORVAL(DeviceUIIndex) == 1) {
        return UIUserInterfaceIdiomPad;
    }
    if (INTFORVAL(DeviceUIIndex) == 2) {
        return UIUserInterfaceIdiomPhone;
    }
    return %orig;
}
%end

%hook UIKeyboardImpl
+ (BOOL)isFloating { return IS_ENABLED(FloatingKeyboard) && isPad() ? YES : %orig; }
%end

%hook YTEngagementPanelHeaderView
- (void)setSubheader:(UIView *)view { if (!IS_ENABLED(HideEngagementSubbar)) %orig; }
%end