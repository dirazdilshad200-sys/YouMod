#import "Headers.h"

// Hide Subbar
%hook YTHeaderContentComboView
- (void)enableSubheaderBarWithView:(id)arg1 { if (!IS_ENABLED(HideSubbar)) %orig; }
- (void)setFeedHeaderScrollMode:(int)arg1 {
    %orig(IS_ENABLED(HideSubbar) ? 0 : arg1);
}
- (id)initWithChildView:(id)arg1 headerView:(id)arg2 {
    self = %orig;
    if (self && IS_ENABLED(HideSubbar)) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(setNeedsLayout)
                                                     name:@"YouModReloadHeaderBar"
                                                   object:nil];
    }
    return self;
}
%end

// Hide voice search button
%hook YTSearchViewController
- (void)viewDidLoad {
    %orig;
    if (IS_ENABLED(HideVoiceSearch)) [self setValue:@(NO) forKey:@"_isVoiceSearchAllowed"];
}
- (void)setSuggestions:(id)arg1 { if (!IS_ENABLED(HideSearchHis)) %orig; }
%end

// Hide search history and suggestions
%hook YTPersonalizedSuggestionsCacheProvider
- (id)activeCache { return IS_ENABLED(HideSearchHis) ? nil : %orig; }
%end

// Hide related videos in the player
%hook YTWatchNextResultsViewController
- (void)setVisibleSections:(NSInteger)sections {
    if (![self.parentViewController isKindOfClass:%c(YTWatchNextResponseViewController)]) {
        %orig;
        return;
    }
    %orig(IS_ENABLED(HideRelatedVideos) ? 1 : sections);
}
%end

// ─── Channel button filter ────────────────────────────────────────────────────
// Old version called [view description] on every yoga child to match by
// accessibilityIdentifier. description serialises the entire node subtree —
// very expensive in a list with many children. Now we ask for
// accessibilityIdentifier directly and only fall back to description if the
// node doesn't respond to it (shouldn't happen but keeps parity).
static void YouModFilterChannelButtons(_ASDisplayView *self, NSString *iden) {
    UIView *sup = self.superview;
    if ([sup isKindOfClass:%c(ASScrollView)]) {
        ASScrollView *scroll = (ASScrollView *)sup;
        ASDisplayNode *node = scroll.scrollNode;
        for (id child in node.yogaChildren) {
            NSString *childIdent = nil;
            if ([child respondsToSelector:@selector(accessibilityIdentifier)]) {
                childIdent = [child accessibilityIdentifier];
            }
            // Only call description as last resort
            if (!childIdent) childIdent = [child description];
            if ([childIdent isEqualToString:iden] || [childIdent containsString:iden]) {
                [node removeYogaChild:child];
                [self removeFromSuperview];
                break;
            }
        }
    } else {
        UIViewController *con = self._viewControllerForAncestor;
        if ([con isKindOfClass:%c(YTPageHeaderViewController)]) {
            _ASDisplayView *dpv = (_ASDisplayView *)sup;
            ASDisplayNode *node = dpv.keepalive_node;
            _ASDisplayView *maindpv = (_ASDisplayView *)dpv.superview;
            ASDisplayNode *mainNode = maindpv.keepalive_node;
            [mainNode removeYogaChild:node];
            [dpv removeFromSuperview];
        } else if ([con isKindOfClass:%c(YTWatchNextResultsViewController)]) {
            _ASDisplayView *dpv = (_ASDisplayView *)sup;
            ASDisplayNode *node = dpv.keepalive_node;
            for (id child in [node.yogaChildren copy]) {
                NSString *childIdent = nil;
                if ([child respondsToSelector:@selector(accessibilityIdentifier)]) {
                    childIdent = [child accessibilityIdentifier];
                }
                if (!childIdent) childIdent = [child description];
                if ([childIdent isEqualToString:iden] || [childIdent containsString:iden]) {
                    [node removeYogaChild:child];
                    [self removeFromSuperview];
                    break;
                }
            }
        }
    }
}

// ─── _ASDisplayView -didMoveToWindow ─────────────────────────────────────────
// Only run the filter logic when at least one of the two channel-button
// features is enabled, AND the view has a non-nil identifier that matches
// one of our targets. The old code always checked both IS_ENABLED calls and
// ran on every single _ASDisplayView in the app.
%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;

    // Bail immediately when neither filter feature is on — zero cost for
    // the vast majority of users who have these disabled.
    BOOL filterCommunity = IS_ENABLED(RemoveChannelCommunityButton);
    BOOL filterSponsor   = IS_ENABLED(RemoveChannelSponsorAll);
    if (!filterCommunity && !filterSponsor) return;

    NSString *iden = self.accessibilityIdentifier;
    if (!iden || iden.length == 0) return;

    if ([iden isEqualToString:@"eml.header_community_button"] && filterCommunity) {
        YouModFilterChannelButtons(self, iden);
    } else if ([iden isEqualToString:@"id.sponsor_button"] && filterSponsor) {
        YouModFilterChannelButtons(self, iden);
    }
}
%end
