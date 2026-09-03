#import "Headers.h"

// ─── Cached static filter tables ─────────────────────────────────────────────
// Built once; avoids allocating NSDictionary literals on every didMoveToWindow
// call, which fires for every Shorts cell during scrolling.
static NSDictionary *sShortsButtonsMap;
static NSDictionary *sShortsPausedHeaderMap;
static NSDictionary *sShortsElementsMap;

static void ymShortsInitMaps(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sShortsButtonsMap = @{
            @"id.reel_like_button":             @(RemoveShortsLikeButton),
            @"id.reel_like_toggled_button":     @(RemoveShortsLikeButton),
            @"id.reel_comment_button":          @(RemoveShortsCommentButton),
            @"id.reel_share_button":            @(RemoveShortsShareButton),
            @"id.reel_remix_button":            @(RemoveShortsRemixButton),
            @"id.reel_pivot_button":            @(RemoveShortsSoundMetadataButton),
        };
        sShortsPausedHeaderMap = @{
            @"id.ui.shorts_paused_state.subscriptions_button": @(RemoveShortsPausedSubButton),
            @"id.ui.shorts_paused_state.live_button":          @(RemoveShortsPausedLiveButton),
            @"id.ui.shorts_paused_state.lens_button":          @(RemoveShortsPausedLensButton),
            @"id.ui.shorts_paused_state.trends_button":        @(RemoveShortsPausedTrendsButton),
        };
        sShortsElementsMap = @{
            @"product_sticker.main_target":             @(HideShortsProducts),
            @"product_sticker.secondary_target":        @(HideShortsProducts),
            @"id.elements.components.suggested_action": @(HideShortsRecbar),
        };
    });
}

// Enables shorts quality - works best with YTClassicVideoQuality
%hook YTHotConfig
- (BOOL)enableOmitAdvancedMenuInShortsVideoQualityPicker { return IS_ENABLED(EnablesShortsQuality) ? YES : %orig; }
- (BOOL)enableShortsVideoQualityPicker { return IS_ENABLED(EnablesShortsQuality) ? YES : %orig; }
- (BOOL)iosEnableImmersiveLivePlayerVideoQuality { return IS_ENABLED(EnablesShortsQuality) ? YES : %orig; }
- (BOOL)iosEnableShortsPlayerVideoQuality { return IS_ENABLED(EnablesShortsQuality) ? YES : %orig; }
- (BOOL)iosEnableShortsPlayerVideoQualityRestartVideo { return IS_ENABLED(EnablesShortsQuality) ? YES : %orig; }
- (BOOL)iosEnableSimplerTitleInShortsVideoQualityPicker { return IS_ENABLED(EnablesShortsQuality) ? YES : %orig; }
- (BOOL)enablePlayerBarForVerticalVideoWhenControlsHiddenInFullscreen { return IS_ENABLED(ShowShortsSeekbar) ? YES : %orig; }
%end

// Always show Shorts seekbar
%hook YTShortsPlayerViewController
- (BOOL)shouldAlwaysEnablePlayerBar { return IS_ENABLED(ShowShortsSeekbar) ? YES : %orig; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return IS_ENABLED(ShowShortsSeekbar) ? NO : %orig; }
%end

%hook YTReelPlayerViewControllerSub
- (BOOL)shouldAlwaysEnablePlayerBar { return IS_ENABLED(ShowShortsSeekbar) ? YES : %orig; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return IS_ENABLED(ShowShortsSeekbar) ? NO : %orig; }
%end

%hook YTColdConfig
- (BOOL)iosEnableVideoPlayerScrubber { return IS_ENABLED(ShowShortsSeekbar) ? YES : %orig; }
- (BOOL)mobileShortsTablnlinedExpandWatchOnDismiss { return IS_ENABLED(ShowShortsSeekbar) ? YES : %orig; }
%end

static void YouModMakeAShortsAction(YTReelPlayerViewController *self, YTSingleVideoController *video, YTSingleVideoTime *time) {
    NSInteger action = INTFORVAL(ShortsActionIndex);
    if (action == 0) return;
    if (floor(time.time) >= floor(video.totalMediaTime)) {
        if (action == 1) {
            [self reelContentViewRequestsAdvanceToNextVideo:nil];
        } else if (action == 2) {
            [self reelContentViewRequestsPlayPauseToggle:nil];
        }
    }
}

static BOOL isShortsOnlyOn = YES;
static BOOL isFullscreenEnabled = NO;

%hook YTReelPlayerViewController
- (BOOL)shouldAlwaysEnablePlayerBar { return IS_ENABLED(ShowShortsSeekbar) ? YES : %orig; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return IS_ENABLED(ShowShortsSeekbar) ? NO : %orig; }
- (void)singleVideo:(YTSingleVideoController *)video currentVideoTimeDidChange:(YTSingleVideoTime *)time {
    %orig;
    YouModMakeAShortsAction(self, video, time);
}
- (void)loadPlayerBar {
    %orig;
    if ((isShortsOnlyOn && IS_ENABLED(ShortsOnly)) || (isFullscreenEnabled && IS_ENABLED(FullScreenShorts))) [[self valueForKey:@"_pivotBarProvider"] performSelector:@selector(hidePivotBar)];
    YTPlayerViewController *main = self.player;
    if (INTFORVAL(CaptionTrack) != 0) [main performSelector:@selector(YouModAutoCaptions) withObject:nil afterDelay:0.5];
    if (INTFORVAL(AutoSpeedIndex) != 0) [main performSelector:@selector(YouModSetAutoSpeed) withObject:nil afterDelay:0.5];
    if (INTFORVAL(AudioTrack) != 0) [self performSelector:@selector(YouModAutoAudioTrack:) withObject:main afterDelay:0.5];
}
%new
- (void)YouModAutoAudioTrack:(YTPlayerViewController *)pv {
    NSInteger selectedIndex = INTFORVAL(AudioTrackLangIndex);
    NSArray *langCodes = getAllSystemLanguageValues();
    NSString *userTargetLang = langCodes[selectedIndex];
    id switchcon = self.audioTrackController;
    NSArray *availableTracks = [switchcon valueForKey:@"_availableAudioTracks"];
    if (!availableTracks || availableTracks.count == 0) return;
    YTIAudioTrack *matchedTrack = nil;

    if (INTFORVAL(AudioTrack) == 1) {
        for (YTIAudioTrack *track in availableTracks) {
            if ([track.id_p hasSuffix:@".4"]) {
                matchedTrack = track;
                break;
            }
        }
    } else if (INTFORVAL(AudioTrack) == 2) {
        for (YTIAudioTrack *track in availableTracks) {
            if ([track.id_p hasPrefix:userTargetLang]) {
                matchedTrack = track;
                break;
            }
        }
        if (matchedTrack && [matchedTrack isAutoDubbed] && IS_ENABLED(NoDubbedAudioTrack)) matchedTrack = nil;
        if (!matchedTrack && IS_ENABLED(NoDubbedAudioTrack)) {
            for (YTIAudioTrack *track in availableTracks) {
                if ([track.id_p hasSuffix:@".4"]) {
                    matchedTrack = track;
                    break;
                }
            }
        }
    }

    if (matchedTrack) {
        [pv setAudioTrack:matchedTrack source:0];
    }
}
%end

%hook YTReelTopBarView
- (void)didMoveToWindow {
    %orig;
    if (IS_ENABLED(HideShortsTopbar)) {
        if (self.superview) {
            [self removeFromSuperview];
        }
    } else if (IS_ENABLED(HideShortsSubbar)) {
        UIView *subbar = [self valueForKey:@"_pausedStateCarouselView"];
        if (subbar && subbar.superview) {
            [subbar removeFromSuperview];
        }
    }
}
%end

extern void YouModConfigureDownloadButton(_ASDisplayView *view);

static void YouModFilterShortsButtons(_ASDisplayView *self, NSString *iden) {
    // Static map — no allocation per call.
    NSNumber *prefKey = sShortsButtonsMap[iden];
    if (!prefKey || ![prefKey boolValue]) return;
    // Use accessibilityIdentifier instead of [view description] (protobuf serialise).
    _ASDisplayView *mainView = (_ASDisplayView *)self.superview;
    ASDisplayNode *node = mainView.keepalive_node;
    for (_ASDisplayView *view in node.yogaChildren) {
        if ([view.accessibilityIdentifier isEqualToString:iden]) {
            [node removeYogaChild:view];
            [self removeFromSuperview];
            break;
        }
    }
}

static void YouModFilterShortsPausedHeader(_ASDisplayView *self, NSString *iden) {
    NSNumber *prefKey = sShortsPausedHeaderMap[iden];
    if (!prefKey || ![prefKey boolValue]) return;
    ASScrollView *mainView = (ASScrollView *)self.superview;
    ASDisplayNode *node = mainView.scrollNode;
    for (_ASDisplayView *view in node.yogaChildren) {
        if ([view.accessibilityIdentifier isEqualToString:iden]) {
            [node removeYogaChild:view];
            [self removeFromSuperview];
            break;
        }
    }
}

static void YouModFilterShortsDisclosure(_ASDisplayView *self, NSString *iden) {
    if (![iden isEqualToString:@"eml.shorts-disclosures"] || !IS_ENABLED(RemoveShortsDisclosure)) return;
    _ASDisplayView *dpView = (_ASDisplayView *)self.superview;
    ASDisplayNode *node = dpView.keepalive_node;
    _ASDisplayView *maindpView = (_ASDisplayView *)dpView.superview;
    ASDisplayNode *mainNode = maindpView.keepalive_node;
    [mainNode removeYogaChild:node];
    [maindpView removeFromSuperview];
}

// _ASDisplayView filters
%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    YouModConfigureDownloadButton(self);
    NSString *iden = self.accessibilityIdentifier;
    if (!iden || iden.length == 0) return;
    // Static map lookup — O(1), no per-call allocation.
    if ([sShortsElementsMap[iden] boolValue]) {
        [self removeFromSuperview];
        return;
    }
    if ([iden isEqualToString:@"eml.reel_sponsor_button"] && IS_ENABLED(RemoveChannelSponsorAll)) {
        [self.superview removeFromSuperview];
        return;
    }
    YouModFilterShortsButtons(self, iden);
    YouModFilterShortsPausedHeader(self, iden);
    YouModFilterShortsDisclosure(self, iden);
}
%end

%hook YTAppDelegate
- (void)appDidBecomeActive {
    %orig;
    if ((isFullscreenEnabled && IS_ENABLED(FullScreenShorts)) || (isShortsOnlyOn && IS_ENABLED(ShortsOnly))) {
        [[self valueForKey:@"_appViewController"] performSelector:@selector(hidePivotBar)];
    }
}
%end

%hook YTReelWatchPlaybackOverlayView
%property (nonatomic, retain) UIPinchGestureRecognizer *YouModFullscreenGesture;
- (void)didMoveToWindow {
    %orig;
    if (!IS_ENABLED(FullScreenShorts)) return;
    if (!self.YouModFullscreenGesture) {
        self.YouModFullscreenGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(YouModFullscrrenGestureHandler:)];
        self.YouModFullscreenGesture.delegate = (id<UIGestureRecognizerDelegate>)self;
        [self.superview addGestureRecognizer:self.YouModFullscreenGesture];
    }
}
%new
- (void)YouModFullscrrenGestureHandler:(UIPinchGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || (isShortsOnlyOn && IS_ENABLED(ShortsOnly))) return;
    UIViewController *appVC = [self valueForKey:@"_pivotBarProvider"];
    BOOL isTabBarHidden = [appVC performSelector:@selector(isPivotBarHidden)];
    if (gesture.scale > 1.0) {
        if (!isTabBarHidden) {
            [appVC performSelector:@selector(hidePivotBar)];
            [UIView animateWithDuration:0.3 animations:^{
                self.alpha = 0;
            }];
            isFullscreenEnabled = YES;
        }
    } else if (gesture.scale < 1.0) {
        if (isTabBarHidden) {
            [appVC performSelector:@selector(showPivotBar)];
            [UIView animateWithDuration:0.3 animations:^{
                self.alpha = 1;
            }];
            isFullscreenEnabled = NO;
        }
    }
}
%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return gestureRecognizer == self.YouModFullscreenGesture;
}
%end

%hook YTReelContentView
%property (nonatomic, retain) UILongPressGestureRecognizer *YouModExitShortsOnlyGesture;
- (void)setPlaybackView:(id)arg1 {
    %orig;
    self.playbackOverlay.alpha = !isFullscreenEnabled;
    if (!IS_ENABLED(ShortsOnly)) return;
    if (isShortsOnlyOn) {
        self.YouModExitShortsOnlyGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(YouModTurnOffShortsOnly:)];
        self.YouModExitShortsOnlyGesture.numberOfTouchesRequired = 2;
        self.YouModExitShortsOnlyGesture.minimumPressDuration = 0.5;
        self.YouModExitShortsOnlyGesture.delegate = (id<UIGestureRecognizerDelegate>)self;
        [self addGestureRecognizer:self.YouModExitShortsOnlyGesture];
    }
}
%new
- (void)YouModTurnOffShortsOnly:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    isShortsOnlyOn = NO;
    UIView *parent = sbGetNotificationParent();
    [SBSkipNotificationView showSuccessInView:parent message:LOC(@"SHORTS_ONLY_DISABLED") duration:3.0];
    [[[[self valueForKey:@"_parentResponder"] valueForKey:@"_delegate"] valueForKey:@"_pivotBarProvider"] performSelector:@selector(showPivotBar)];
    [UIView animateWithDuration:0.3 animations:^{
        self.playbackOverlay.alpha = 1;
    }];
}
%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return gestureRecognizer == self.YouModExitShortsOnlyGesture
        && [otherGestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]];
}
%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return gestureRecognizer != self.YouModExitShortsOnlyGesture;
}
%end

%ctor {
    ymShortsInitMaps();
}
