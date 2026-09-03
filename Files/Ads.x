#import "Headers.h"

// ─── Cached class references ──────────────────────────────────────────────────
// %c() calls objc_getClass() on every invocation. Cache them once.
static Class cls_YTIShelfRenderer;
static Class cls_YTIItemSectionRenderer;
static Class cls_YTReelNonVideoContentModel;
static Class cls_ASCollectionViewCell;
static Class cls_YTPageHeaderViewController;

static void initCachedClasses(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls_YTIShelfRenderer          = %c(YTIShelfRenderer);
        cls_YTIItemSectionRenderer    = %c(YTIItemSectionRenderer);
        cls_YTReelNonVideoContentModel = %c(YTReelNonVideoContentModel);
        cls_ASCollectionViewCell       = %c(_ASCollectionViewCell);
        cls_YTPageHeaderViewController = %c(YTPageHeaderViewController);
    });
}

// ─── Product list check ───────────────────────────────────────────────────────
// YouTube-X (https://github.com/PoomSmart/YouTube-X)
static BOOL isProductList(YTICommand *command) {
    if ([command respondsToSelector:@selector(yt_showEngagementPanelEndpoint)]) {
        YTIShowEngagementPanelEndpoint *endpoint = [command yt_showEngagementPanelEndpoint];
        return [endpoint.identifier.tag isEqualToString:@"PAproduct_list"];
    }
    return NO;
}

// ─── Post / ad string matching ────────────────────────────────────────────────
// Both use dispatch_once arrays. Most-commonly-hit strings first so the scan
// exits early in the typical case.
static NSString *getPostString(NSString *desc) {
    static NSArray *postStrings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        postStrings = @[
            @"text_post_root_slim.eml",          // most common
            @"text_post_responsive_root.eml",
            @"poll_post_root.eml",
            @"options_post_root.eml",
            @"options_post_responsive_root.eml",
            @"images_post_root_slim.eml",
            @"images_post_responsive_root.eml",
            @"post_base_wrapper_slim.eml",
            @"videos_post_root.eml"
        ];
    });
    for (NSString *s in postStrings) {
        if ([desc containsString:s]) return s;
    }
    return nil;
}

static NSString *getAdString(NSString *desc) {
    static NSArray *adStrings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        adStrings = @[
            // Highest hit-rate first
            @"feed_ad_metadata",
            @"text_image_button_layout",
            @"eml.expandable_metadata",
            @"carousel_headered_layout",
            @"carousel_footered_layout",
            @"product_carousel",
            @"shopping_carousel",
            @"brand_promo",
            @"brand_video_shelf",
            @"brand_video_singleton",
            @"full_width_portrait_image_layout",
            @"full_width_square_image_layout",
            @"grid_ads_image_layout",
            @"landscape_image_wide_button_layout",
            @"post_shelf",
            @"product_engagement_panel",
            @"product_item",
            @"shopping_item_card_list",
            @"statement_banner",
            @"square_image_layout",
            @"text_search_ad",
            @"video_display_full_layout",
            @"video_display_full_buttoned_layout"
        ];
    });
    for (NSString *s in adStrings) {
        if ([desc containsString:s]) return s;
    }
    return nil;
}

// ─── Ad renderer detection ────────────────────────────────────────────────────
// Fast path: check the adLoggingData flag first (no string work).
// Slow path: fall back to description-based matching only if the fast path
// doesn't fire. description() is protobuf serialisation — expensive.
static BOOL isAdRenderer(YTIElementRenderer *elementRenderer) {
    if (!elementRenderer) return NO;
    // Fast path — no description() call at all
    if ([elementRenderer respondsToSelector:@selector(hasCompatibilityOptions)]
        && elementRenderer.hasCompatibilityOptions
        && elementRenderer.compatibilityOptions.hasAdLoggingData) {
        return YES;
    }
    // Slow path — only reached when adLoggingData isn't set
    return getAdString([elementRenderer description]) != nil;
}

// ─── Reel model filter (shared logic) ─────────────────────────────────────────
// Extracted so the identical block doesn't live in 4 separate hook methods.
// respondsToSelector is called once per model instead of 3×.
static YTReelModel *ymFilterReelModel(YTReelModel *model) {
    if (!model) return nil;
    // Non-video content (ads injected into shorts feed)
    if ([model isKindOfClass:cls_YTReelNonVideoContentModel]) return nil;
    // Only call respondsToSelector once; reuse result for all videoType checks
    if ([model respondsToSelector:@selector(videoType)]) {
        NSInteger vt = model.videoType;
        if (vt == 3) return nil;  // ads
        if (vt == 10 && IS_ENABLED(RemoveShortsPosts)) return nil;
        if ((vt == 4 || vt == 7) && IS_ENABLED(RemoveShortsLive)) return nil;
    }
    return model;
}

// ─── Section array filter ─────────────────────────────────────────────────────
static NSMutableArray <YTIItemSectionRenderer *> *filteredArray(NSArray <YTIItemSectionRenderer *> *array) {
    // Read all prefs once — IS_ENABLED is a dict lookup but still cheaper
    // to hoist out of the block that runs N times.
    const BOOL hideShorts    = IS_ENABLED(HideShortsShelf);
    const BOOL keepShortsSub = IS_ENABLED(KeepShortsSubscript);
    const BOOL hideFeedPost  = IS_ENABLED(HideFeedPost);
    const BOOL hidePlayables = IS_ENABLED(HidePlayables);
    const BOOL hideHoriShelf = IS_ENABLED(HideHoriShelf);
    const BOOL hideCommuGuide= IS_ENABLED(HideCommuGuide);
    const BOOL hideGenMusic  = IS_ENABLED(HideGenMusicShelf);
    const BOOL hideSurveys   = IS_ENABLED(HideSurveys);
    const BOOL hideComments  = IS_ENABLED(HideCommentsSection);

    // Early exit: if every filter is off, return a mutable copy and skip all work
    if (!hideShorts && !hideFeedPost && !hidePlayables && !hideHoriShelf
        && !hideCommuGuide && !hideGenMusic && !hideSurveys && !hideComments) {
        // Still need to strip inline element-level ads
        NSMutableArray *copy = [array mutableCopy];
        for (YTIItemSectionRenderer *section in copy) {
            if ([section isKindOfClass:cls_YTIItemSectionRenderer]) {
                NSMutableArray *contents = section.contentsArray;
                if (contents.count > 1) {
                    [contents removeObjectsAtIndexes:
                        [contents indexesOfObjectsPassingTest:^BOOL(YTIItemSectionSupportedRenderers *r, NSUInteger i, BOOL *s) {
                            return isAdRenderer(r.elementRenderer);
                        }]];
                } else if (contents.count == 1) {
                    if (isAdRenderer([contents firstObject].elementRenderer)) {
                        [contents removeObjectAtIndex:0];
                    }
                }
            }
        }
        return copy;
    }

    NSMutableArray <YTIItemSectionRenderer *> *newArray = [array mutableCopy];
    NSIndexSet *removeIndexes = [newArray indexesOfObjectsPassingTest:
        ^BOOL(YTIItemSectionRenderer *sectionRenderer, NSUInteger idx, BOOL *stop) {

        if ([sectionRenderer isKindOfClass:cls_YTIShelfRenderer]) {
            NSString *desc = [sectionRenderer description];
            if ([desc containsString:@"community-tab-chip-posts-section"]) return NO;

            if (hideShorts) {
                if (keepShortsSub && [desc containsString:@"subscriptions-shorts-shelf-item"]) return NO;
                if ([desc containsString:@"shorts_video_cell.eml"]) return YES;
                if ([desc containsString:@"shelf_header.eml"] && [desc containsString:@"youtube_shorts_24_cairo"]) return YES;
            }
            if (hideFeedPost && getPostString(desc)) return YES;

            // Strip ad items from horizontal lists inside shelves
            YTIShelfSupportedRenderers *content = ((YTIShelfRenderer *)sectionRenderer).content;
            NSMutableArray *itemsArray = content.horizontalListRenderer.itemsArray;
            [itemsArray removeObjectsAtIndexes:
                [itemsArray indexesOfObjectsPassingTest:^BOOL(YTIHorizontalListSupportedRenderers *r, NSUInteger i, BOOL *s) {
                    return isAdRenderer(r.elementRenderer);
                }]];
            return NO;

        } else if ([sectionRenderer isKindOfClass:cls_YTIItemSectionRenderer]) {
            NSString *desc = [sectionRenderer description];
            if ([desc containsString:@"community-tab-chip-posts-section"]) return NO;

            // YouTube Premium upsell rows
            if ([desc containsString:@"UNLIMITED"] && [desc containsString:@"SPunlimited"]) {
                NSMutableArray *contentsArray = sectionRenderer.contentsArray;
                NSMutableIndexSet *toRemove = [NSMutableIndexSet indexSet];
                __block NSUInteger lastDivider = NSNotFound;
                [contentsArray enumerateObjectsUsingBlock:^(YTIItemSectionSupportedRenderers *item, NSUInteger i, BOOL *s) {
                    NSString *d = [item description];
                    if ([d containsString:@"cell_divider.eml"]) {
                        lastDivider = i;
                    } else if ([d containsString:@"UNLIMITED"] && [d containsString:@"SPunlimited"]) {
                        [toRemove addIndex:i];
                        if (lastDivider != NSNotFound) {
                            [toRemove addIndex:lastDivider];
                            lastDivider = NSNotFound;
                        }
                    }
                }];
                [contentsArray removeObjectsAtIndexes:toRemove];
                return NO;
            }

            if (hideShorts) {
                const BOOL isShortsShelf  = [desc containsString:@"shorts_shelf.eml"];
                const BOOL isHistory      = [desc containsString:@"history-shorts-shelf-item"];
                const BOOL isShortsOverlay= [desc containsString:@"video_lockup_overlay"];
                if (keepShortsSub) {
                    if (isShortsShelf && ![desc containsString:@"subscriptions-shorts-shelf-item"] && !isHistory) return YES;
                } else {
                    if (isShortsShelf && !isHistory) return YES;
                }
                if (isShortsOverlay) return YES;
            }

            if ([desc containsString:@"horizontal_shelf.eml"]) {
                if (hidePlayables && [desc containsString:@"FEmini_app_destination"]) return YES;
                if (hideHoriShelf
                    && ![desc containsString:@"UCYfdidRxbB8Qhf0Nx7ioOYw"]
                    && ![desc containsString:@"FElibrary"]
                    && ![desc containsString:@"mini_game_card.eml"]
                    && ![desc containsString:@"FEplaylist_aggregation"]) return YES;
            }

            if (hideCommuGuide && ([desc containsString:@"community_guidelines.eml"]
                || [desc containsString:@"channel_guidelines_entry_banner.eml"])) return YES;
            if (hideFeedPost && getPostString(desc)) return YES;
            if (hideGenMusic && [desc containsString:@"feed_nudge.eml"]) return YES;
            if (hideSurveys && [desc containsString:@"in_feed_survey.eml"]) return YES;
            if (hideComments && [desc containsString:@"comment-item-section"]
                && [desc containsString:@"comments-entry-point"]) return YES;

            // Strip inline ad elements from the section's contents
            NSMutableArray *contentsArray = sectionRenderer.contentsArray;
            if (contentsArray.count > 1) {
                [contentsArray removeObjectsAtIndexes:
                    [contentsArray indexesOfObjectsPassingTest:^BOOL(YTIItemSectionSupportedRenderers *r, NSUInteger i, BOOL *s) {
                        return isAdRenderer(r.elementRenderer);
                    }]];
            } else if (contentsArray.count == 1) {
                if (isAdRenderer([contentsArray firstObject].elementRenderer)) return YES;
            }
        }
        return NO;
    }];
    [newArray removeObjectsAtIndexes:removeIndexes];
    return newArray;
}

// ─── Player-level ad blocking ─────────────────────────────────────────────────
%hook YTPlayerResponse
%new(@@:)
- (NSMutableArray *)playerAdsArray { return [NSMutableArray array]; }
%new(@@:)
- (NSMutableArray *)adSlotsArray   { return [NSMutableArray array]; }
%end

%hook YTIClientMdxGlobalConfig
%new(B@:)
- (BOOL)enableSkippableAd { return YES; }
%end

// Kill spam-signal telemetry sent alongside ad requests
%hook YTAdShieldUtils
+ (id)spamSignalsDictionary             { return @{}; }
+ (id)spamSignalsDictionaryWithoutIDFA  { return @{}; }
%end

%hook YTDataUtils
+ (id)spamSignalsDictionary             { return @{ @"ms": @"" }; }
+ (id)spamSignalsDictionaryWithoutIDFA  { return @{}; }
%end

// Nullify the context decorators that tag requests as eligible for ads
%hook YTAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context {
    id nullCtx = nil;
    %orig(nullCtx);
}
%end

%hook YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context {
    id nullCtx = nil;
    %orig(nullCtx);
}
%end

%hook YTLocalPlaybackController
- (id)createAdsPlaybackCoordinator { return nil; }
%end

%hook MDXSession
- (void)adPlaying:(id)ad {}
%end

%hook MDXSessionImpl
- (void)adPlaying:(id)ad {}
%end

// ─── Shorts / Reels ad filtering ──────────────────────────────────────────────
// All four hook sites share ymFilterReelModel() — one place to maintain.
// Live video type = 4 and Live preview = 7, 9 is Playables ads, 10 is posts.
%hook YTReelDataSource
- (YTReelModel *)makeContentModelForEntry:(id)entry {
    return ymFilterReelModel(%orig);
}
%end

%hook YTReelContentModel
+ (YTReelModel *)makeContentModelForEntry:(id)entry {
    return ymFilterReelModel(%orig);
}
%end

%hook YTReelInfinitePlaybackDataSource
- (YTReelModel *)makeContentModelForEntry:(id)entry {
    return ymFilterReelModel(%orig);
}
- (void)setReels:(NSMutableOrderedSet <YTReelModel *> *)reels {
    [reels removeObjectsAtIndexes:
        [reels indexesOfObjectsPassingTest:^BOOL(YTReelModel *obj, NSUInteger idx, BOOL *stop) {
            return ymFilterReelModel(obj) == nil;
        }]];
    %orig;
}
%end

// ─── Watch-next product list removal ─────────────────────────────────────────
%hook YTWatchNextResponseViewController
- (void)loadWithModel:(YTIWatchNextResponse *)model {
    YTICommand *onUiReady = model.onUiReady;
    if ([onUiReady respondsToSelector:@selector(yt_commandExecutorCommand)]) {
        NSMutableArray *commands = [onUiReady yt_commandExecutorCommand].commandsArray;
        [commands removeObjectsAtIndexes:
            [commands indexesOfObjectsPassingTest:^BOOL(YTICommand *cmd, NSUInteger i, BOOL *s) {
                return isProductList(cmd);
            }]];
    }
    if (isProductList(onUiReady)) model.onUiReady = nil;
    %orig;
}
%end

// ─── Player overlay ad removal ────────────────────────────────────────────────
%hook YTMainAppVideoPlayerOverlayViewController
- (void)playerOverlayProvider:(YTPlayerOverlayProvider *)provider
         didInsertPlayerOverlay:(YTPlayerOverlay *)overlay {
    NSString *iden = [overlay overlayIdentifier];
    if ([iden isEqualToString:@"player_overlay_product_in_video"]) return;
    if ([iden isEqualToString:@"player_overlay_paid_content"] && IS_ENABLED(HidePaidPromoOverlay)) return;
    %orig;
}
%end

%hook YTWatchFloatingMiniplayerBadgeView
- (void)didMoveToWindow {
    %orig;
    if (IS_ENABLED(HidePaidPromoOverlay)) {
        UIView *badge = [self valueForKey:@"_overlayBadge"];
        if (badge.superview) [badge removeFromSuperview];
    }
}
%end

// ─── Section controller (feed-level) ─────────────────────────────────────────
%hook YTInnerTubeCollectionViewController
- (void)displaySectionsWithReloadingSectionControllerByRenderer:(id)renderer {
    NSMutableArray *sections = [self valueForKey:@"_sectionRenderers"];
    [self setValue:filteredArray(sections) forKey:@"_sectionRenderers"];
    %orig;
}
- (void)addSectionsFromArray:(NSArray <YTIItemSectionRenderer *> *)array {
    %orig(filteredArray(array));
}
%end

// ─── ASDisplayView ad layout removal ─────────────────────────────────────────
// Fires on every view attach — keep it as cheap as possible.
%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    NSString *iden = self.accessibilityIdentifier;

    // Remove expandable metadata ad overlays
    if ([iden isEqualToString:@"eml.expandable_metadata.vpp"]) {
        [self removeFromSuperview];
        return;
    }

    // Remove comments preview
    if (IS_ENABLED(HideCommentsPreview)
        && [iden isEqualToString:@"id.ui.comments_entry_point_teaser"]) {
        [self removeFromSuperview];
        return;
    }

    // Remove "YouTube Premium" channel header badge.
    // Check label before walking the VC hierarchy — string check is cheap,
    // _viewControllerForAncestor is an O(depth) walk.
    NSString *label = self.accessibilityLabel;
    if (label && [label containsString:@"Premium"]) {
        if ([self._viewControllerForAncestor isKindOfClass:cls_YTPageHeaderViewController]) {
            [self removeFromSuperview];
            return;
        }
    }

    // Remove ad layout cells injected into newer YT versions via eml.ad_layout.*
    if ([iden hasPrefix:@"eml.ad_layout."]) {
        // Walk up to the collection view cell that owns this node
        UIView *cursor = self.superview;
        while (cursor && ![cursor isKindOfClass:cls_ASCollectionViewCell]) {
            cursor = cursor.superview;
        }
        if (cursor) {
            ASDisplayNode *node = ((_ASCollectionViewCell *)cursor).node;
            for (id child in [node.yogaChildren copy]) {
                [node removeYogaChild:child];
            }
        }
    }
}
%end

// ─── NoYTPremium hooks ────────────────────────────────────────────────────────
// @PoomSmart https://github.com/PoomSmart/NoYTPremium

// Alert
%hook YTCommerceEventGroupHandler
- (void)addEventHandlers {}
%end

// Full-screen interstitial
%hook YTInterstitialPromoEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTPromosheetEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTPromoThrottleController
- (BOOL)canShowThrottledPromo                                     { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCap:(id)arg1            { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCaps:(id)arg1           { return NO; }
%end

%hook YTPromoThrottleControllerImpl
- (BOOL)canShowThrottledPromo                                     { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCap:(id)arg1            { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCaps:(id)arg1           { return NO; }
%end

%hook YTIShowFullscreenInterstitialCommand
- (BOOL)shouldThrottleInterstitial {
    if (self.hasModalClientThrottlingRules)
        self.modalClientThrottlingRules.oncePerTimeWindow = YES;
    return %orig;
}
%end

// Settings
%hook YTSettingsSectionItemManager
- (void)updateUnlimitedSectionWithEntry:(id)arg {}
%end

// Survey
%hook YTSurveyController
- (void)showSurveyWithRenderer:(id)arg1 surveyParentResponder:(id)arg2 {}
%end

// ─── Ad Pipeline (binary-confirmed hooks from 21.35.3) ───────────────────────
// These target the orchestration layer — one level above the renderer filtering
// above. They disarm the event wiring that arms ad breaks, pings, and promos
// before any content is even requested.

// Ad control flow / scheduling
%hook YTAdsControlFlowManager
- (void)addEventHandlers {}
%end

%hook YTAdBreakService
- (id)createAds { return nil; }
%end

%hook YTAdsPlaybackCoordinator
- (void)addEventHandlers {}
%end

%hook YTAdLoggingAPI
- (void)addEventHandlers {}
%end

// Tracking pings (impression, quartile, completion, click, skip beacons)
%hook YTAdsPingService
- (void)addEventHandlers {}
%end

%hook YTAdsEventLoggingController
- (void)addEventHandlers {}
%end

%hook YTVideoAdsService
- (void)addEventHandlers {}
%end

%hook YTAdTrackingController
- (void)addEventHandlers {}
%end

// Shorts / Reels ad infrastructure
%hook YTShortsAdsContentPresenter
- (void)addEventHandlers {}
%end

%hook YTReelAdsPresenterManager
- (void)addEventHandlers {}
%end

%hook YTAdsOrganicReelLifecycleObserver
- (void)addEventHandlers {}
%end

// Frequency cap API — deny insertion and kill IPC round-trips
%hook YTAdsFcapAPI
- (void)addEventHandlers {}
- (BOOL)canInsertAd:(id)ad fcapThreshold:(NSInteger)threshold { return NO; }
%end

// ─── Promo / Upsell System ────────────────────────────────────────────────────
%hook YTMealbarPromoController
- (void)addEventHandlers {}
- (void)displayMealbarAfterAd {}
%end

%hook YTPlaybackUpsellController
- (void)addEventHandlers {}
%end

%hook YTUpsellAlertController
- (void)addEventHandlers {}
%end

%hook YTWatchNextUpsellController
- (void)addEventHandlers {}
%end

%hook YTPlayerPromoController
- (void)addEventHandlers {}
%end

%hook YTPromosheetController
- (void)addEventHandlers {}
%end

// Full-screen promo overlay — viewDidAppear so the VC still inits cleanly
%hook YTInterstitialPromoViewController
- (void)viewDidAppear:(BOOL)animated {}
%end

%hook YTShowPromoCommandHandler
- (void)handleCommand:(id)command {}
%end

// ─── Extended Survey Blocking ─────────────────────────────────────────────────
// YTSurveyController already hooked above; these cover the concrete impl,
// the underlying service, server command handler, and UI entry points.
%hook YTSSurveyController
- (void)addEventHandlers {}
%end

%hook YTSurveyService
- (void)addEventHandlers {}
%end

%hook YTSurveyEndpointCommandHandler
- (void)handleCommand:(id)command {}
%end

%hook YTInlineSurveyCell
- (void)addSurveyView {}
%end

%hook YTReelWatchSurveyViewController
- (void)viewDidAppear:(BOOL)animated {}
%end

%hook YTSubmitReelsAdSurveyCommandHandler
- (void)handleCommand:(id)command {}
%end

// ─── Interstitial / Impression Commands ──────────────────────────────────────
%hook YTShowInterstitialCommandHandler
- (void)handleCommand:(id)command {}
%end

// Impression-capped commands trigger upsell/promo after N video views
%hook YTImpressionCappedCommandHandler
- (void)handleCommand:(id)command {}
%end

// ─── Ad Signal / Device Tracking Infrastructure ───────────────────────────────
%hook YTWebViewAdSignalsController
- (void)addEventHandlers {}
- (id)collectSignals { return nil; }
%end

// Server-triggered device fingerprint / IDFA collection
%hook YTCollectMobileDeviceSignalsCommandHandler
- (void)handleCommand:(id)command {}
%end

// ATT permission prompt + IDFA provisioning for ad targeting
%hook YTAppTrackingProvisioner
- (void)addEventHandlers {}
- (void)provisionTracking {}
%end

// ─── Class cache initialisation ───────────────────────────────────────────────
%ctor {
    initCachedClasses();
}
