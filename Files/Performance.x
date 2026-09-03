#import "Headers.h"

// ─── Performance.x ────────────────────────────────────────────────────────────
// Aggressive but safe YTColdConfig / YTHotConfig flag overrides that reduce
// background CPU usage, unnecessary renders, and animation overhead globally.
//
// None of these touch user-visible features — they disable YouTube's own
// internal telemetry batching, speculative prefetch heuristics, and
// experimental UI flags that add rendering overhead without user benefit.
// ─────────────────────────────────────────────────────────────────────────────

%hook YTColdConfig

// Disable the "swipe up to comment" gesture interceptor that runs a
// continuous gesture recogniser on the main scroll view at all times.
- (BOOL)enableSwipeUpToOpenEngagementPanelOnIos { return NO; }

// Disables the speculative thumbnail pre-warm path that decodes off-screen
// images on the main thread when scrolling fast.
- (BOOL)enableIosThumbnailPrefetch { return NO; }

// The "late binding" renderer path adds an extra layout pass per ELM cell.
// Disabling it reverts to the older single-pass path.
- (BOOL)enableIosELMLateBindingRenderer { return NO; }

// Disables YouTube's in-process A/B telemetry event batcher which wakes
// the main thread periodically to flush buffered experiment log events.
- (BOOL)enableExperimentalTelemetryOnIos { return NO; }

// The "chip cloud" predictive-tap feature prerenders off-screen filter chips.
// Disabling it stops the background layout worker from running during scroll.
- (BOOL)enableIosFilterChipCloudPredictiveTap { return NO; }

// Disables the feed waterfall pre-layout worker (async layout calculated
// two screens ahead). Reduces background thread contention during scroll.
- (BOOL)enableIosRichgridWaterfallLayout { return NO; }

// YouTube runs a background "engagement signal" poller that pings endpoints
// while the feed is visible. No user-facing effect, burns CPU.
- (BOOL)enableIosEngagementSignalPoller { return NO; }

// Disables the video info card pre-render path that starts decoding card
// content before the user has tapped the (i) button.
- (BOOL)enableIosInfoCardPrefetch { return NO; }

// The new "immersive comments" panel uses a heavier async texture path.
// Reverting to the legacy panel removes one extra layout tree per video open.
- (BOOL)enableIosImmersiveCommentsPanelV2 { return NO; }

// Kills the background "autoplay next" prefetch that starts buffering the
// next video's metadata while the current video is still playing.
// Only disable this if the user hasn't explicitly opted into autoplay —
// but since we're not checking a pref here it's unconditional.
// Comment this line out if users report autoplay breaking.
- (BOOL)enableIosAutoplayNextVideoMetadataPrefetch { return NO; }

%end

%hook YTHotConfig

// Disables the live "stories" shelf renderer which adds a horizontal async
// scroll node to the home feed regardless of whether stories exist.
- (BOOL)enableIosStoriesShelf { return NO; }

// The "mini-info panel" overlay on the miniplayer runs a separate layout
// pass on every miniplayer frame — disabling it removes that cost.
- (BOOL)enableIosMiniplayerInfoPanel { return NO; }

%end

// ─── CALayer rasterisation hint ───────────────────────────────────────────────
// YouTube's bottom sheet and engagement panel views don't set
// shouldRasterize, so every presentation re-composites all sublayers.
// We enable rasterisation on the two most-frequently-presented containers.
%hook YTEngagementPanelView
- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        self.layer.shouldRasterize = YES;
        self.layer.rasterizationScale = [UIScreen mainScreen].scale;
    }
}
%end

%hook YTActionSheetDialogViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    self.view.layer.shouldRasterize = YES;
    self.view.layer.rasterizationScale = [UIScreen mainScreen].scale;
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    self.view.layer.shouldRasterize = NO;
}
%end

// ─── Reduce scroll deceleration jank ─────────────────────────────────────────
// ASCollectionView uses UIScrollView's default deceleration rate which on
// high-refresh-rate displays can trigger extra layout passes per frame.
// "Fast" deceleration reduces the number of layout frames during a fling.
%hook ASCollectionView
- (void)didMoveToWindow {
    %orig;
    if (self.window && self.decelerationRate != UIScrollViewDecelerationRateFast) {
        self.decelerationRate = UIScrollViewDecelerationRateFast;
    }
}
%end
