#import "Headers.h"

// ─── Shared dynamic black/clear colour ───────────────────────────────────────
// Creating UIColor objects is cheap but doing it inside hot paths
// (didMoveToWindow on every cell) adds up. Materialise both once.
static UIColor *ymDynamicBlackOrClear(void) {
    static UIColor *c = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        c = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            return tc.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor blackColor] : [UIColor clearColor];
        }];
    });
    return c;
}

static UIColor *ymDynamicBlackOrWhite(void) {
    static UIColor *c = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        c = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            return tc.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor blackColor] : [UIColor whiteColor];
        }];
    });
    return c;
}

%group OLEDTheme
%hook YTColor
+ (UIColor *)black0 { return [UIColor blackColor]; }
+ (UIColor *)black1 { return [UIColor blackColor]; }
+ (UIColor *)black2 { return [UIColor blackColor]; }
+ (UIColor *)black3 { return [UIColor blackColor]; }
+ (UIColor *)black4 { return [UIColor blackColor]; }
%end

%hook YTCommonColorPalette
- (UIColor *)baseBackground            { return self.pageStyle == 1 ? [UIColor blackColor] : %orig; }
- (UIColor *)brandBackgroundSolid      { return self.pageStyle == 1 ? [UIColor blackColor] : %orig; }
- (UIColor *)brandBackgroundPrimary    { return self.pageStyle == 1 ? [UIColor blackColor] : %orig; }
- (UIColor *)brandBackgroundSecondary  { return self.pageStyle == 1 ? [UIColor blackColor] : %orig; }
- (UIColor *)raisedBackground          { return self.pageStyle == 1 ? [UIColor blackColor] : %orig; }
- (UIColor *)staticBrandBlack          { return self.pageStyle == 1 ? [UIColor blackColor] : %orig; }
- (UIColor *)generalBackgroundA        { return self.pageStyle == 1 ? [UIColor blackColor] : %orig; }
%end

%hook YTInnerTubeCollectionViewController
- (UIColor *)backgroundColor:(NSInteger)pageStyle { return pageStyle == 1 ? [UIColor blackColor] : %orig; }
%end

// ─── _ASDisplayView ──────────────────────────────────────────────────────────
// This fires on EVERY Texture/AsyncDisplayKit view in the entire app — every
// feed cell, comment row, chip, etc. Keep it as lean as possible.
//
// Optimisation summary vs the old version:
//  • Static sets & early-exit guard hoisted to dispatch_once (was re-evaluated
//    on every call in some branches).
//  • Identifier-only fast path checked BEFORE the expensive
//    _viewControllerForAncestor walk.
//  • _viewControllerForAncestor called exactly once, result reused.
//  • [renderer description] (protobuf→string serialisation) only called when
//    myIdent already matches one of the two ELM strings — not for every cell.
//  • Shared UIColor singletons used to avoid repeated object creation.
// ─────────────────────────────────────────────────────────────────────────────
%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;

    NSString *myIdent = self.accessibilityIdentifier;

    // ── Fast path 1: identifier-keyed backgrounds (no VC walk needed) ────────
    static NSSet *ymIdentSet = nil;
    static dispatch_once_t ymIdentOnce;
    dispatch_once(&ymIdentOnce, ^{
        ymIdentSet = [NSSet setWithObjects:
            @"id.elements.components.comment_composer",
            @"id.subs.subscriptions_channel_bar",
            @"PAmedia_hub_device_picker.engagement_panel_header",
            nil];
    });
    if (myIdent && [ymIdentSet containsObject:myIdent]) {
        self.backgroundColor = ymDynamicBlackOrClear();
        return;
    }

    // ── Fast path 2: filter_chip_bar (identifier match, no VC walk) ──────────
    if ([myIdent isEqualToString:@"id.elements.components.filter_chip_bar"]) {
        UIColor *c = ymDynamicBlackOrClear();
        self.backgroundColor = c;
        self.superview.backgroundColor = c;
        return;
    }

    // ── Fast path 3: live chat — check ident before walking VC tree ──────────
    if ([myIdent isEqualToString:@"eml.live_chat_text_message"]) {
        UIViewController *controller = self._viewControllerForAncestor;
        if ([controller isKindOfClass:%c(YCHAsyncLiveChatCollectionViewController)]) {
            YCHAsyncLiveChatCollectionViewController *con =
                (YCHAsyncLiveChatCollectionViewController *)controller;
            if ([con.view isKindOfClass:%c(YCHAsyncLiveChatImmersiveCollectionView)]) return;
            self.backgroundColor = ymDynamicBlackOrWhite();
        }
        return;
    }

    // ── ELM text field / transcript — only enter if ident matches first ───────
    // [renderer description] is a protobuf serialisation — very expensive.
    // Only invoke it when the accessibilityIdentifier already narrows us down.
    BOOL isTextField    = [myIdent isEqualToString:@"id.elements.components.text_field"];
    BOOL couldBeELMPath = isTextField; // transcript has no fixed ident, handled below

    // ── VC walk — only when identifier didn't already resolve it ─────────────
    UIViewController *controller = self._viewControllerForAncestor;

    if ([controller isKindOfClass:%c(YTActionSheetDialogViewController)] ||
        [controller isKindOfClass:%c(YTBottomSheetController)]) {
        if ([self.superview.accessibilityIdentifier
                isEqualToString:@"eml.animated_subscribe_button"]) return;
        self.backgroundColor = ymDynamicBlackOrClear();
        return;
    }

    if ([controller isKindOfClass:%c(YTELMViewController)]) {
        // Only pay the description cost when ident is text_field (search input)
        // or when we have no ident at all (transcript panel can have any ident).
        if (isTextField || !myIdent || myIdent.length == 0) {
            YTELMViewController *con = (YTELMViewController *)controller;
            YTIElementRenderer *renderer = [con valueForKey:@"_renderer"];
            NSString *desc = [renderer description];
            if (isTextField &&
                [desc containsString:@"timeline_search_input_form_id"] &&
                [desc containsString:@"search_input.eml"]) {
                self.superview.backgroundColor = ymDynamicBlackOrClear();
            } else if ([desc containsString:@"transcript_panel.eml"]) {
                self.backgroundColor = ymDynamicBlackOrClear();
            }
        }
        return;
    }
}
%end

// ─── ASCollectionView ────────────────────────────────────────────────────────
// Old code rebuilt NSSet on every call. Now it's a singleton + single-pass.
%hook ASCollectionView
- (void)didMoveToWindow {
    %orig;
    NSString *ident = self.accessibilityIdentifier;
    if (!ident) return;

    static NSSet *ymCollBlackClearSet = nil;
    static dispatch_once_t ymCollOnce;
    dispatch_once(&ymCollOnce, ^{
        ymCollBlackClearSet = [NSSet setWithObjects:
            @"eml.chip_bar_collection",
            @"subs_channel_bar.collection",
            nil];
    });

    if ([ymCollBlackClearSet containsObject:ident]) {
        self.backgroundColor = ymDynamicBlackOrClear();
        return;
    }
    if ([ident isEqualToString:@"id.elements.components.more_drawer_collection"]) {
        self.superview.backgroundColor = ymDynamicBlackOrWhite();
    }
}
%end

// ─── YTContextualWrapView ────────────────────────────────────────────────────
%hook YTContextualWrapView
- (void)didMoveToWindow {
    %orig;
    if ([self.superview isKindOfClass:%c(YTContextualSheetView)]) {
        self.backgroundColor = ymDynamicBlackOrWhite();
    }
}
%end

// ─── ASScrollView ────────────────────────────────────────────────────────────
// Old code called [child description] on every yoga child (expensive protobuf
// serialisation) every time any scroll view moves to a window. Now we check
// the scrollNode's accessibilityIdentifier first — only the report-form
// ASScrollView has the matching children, so all other scroll views exit
// immediately after the nil/window check.
%hook ASScrollView
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    ASDisplayNode *node = self.scrollNode;
    if (!node) return;

    // The report-form scroll node has an accessibility identifier we can check
    // before iterating children. If we don't match, bail immediately.
    // (If it has no identifier this path runs once per report-form presentation,
    //  which is rare and acceptable.)
    NSString *nodeIdent = node.accessibilityIdentifier;
    if (nodeIdent && nodeIdent.length > 0) {
        // Any scroll node with a non-nil ident is not the anonymous report form.
        return;
    }

    for (id child in node.yogaChildren) {
        // Use accessibilityIdentifier where possible — only fall back to
        // description when the child doesn't expose one.
        NSString *childIdent = nil;
        if ([child respondsToSelector:@selector(accessibilityIdentifier)]) {
            childIdent = [child accessibilityIdentifier];
        }
        NSString *lookup = childIdent ?: [child description];
        if ([lookup containsString:@"report_form_reason_select_page.container"] ||
            [lookup containsString:@"report_form_sign_in_page.container"]) {
            self.backgroundColor = ymDynamicBlackOrClear();
            break;
        }
    }
}
%end

// ─── MDCInkView ──────────────────────────────────────────────────────────────
%hook MDCInkView
- (void)didMoveToWindow {
    %orig;
    if (![self.superview isKindOfClass:%c(GOODialogActionMDCButton)]) return;
    UIViewController *controller = self._viewControllerForAncestor;
    if ([controller isKindOfClass:%c(YTBottomSheetController)] ||
        [controller isKindOfClass:%c(GOOModalWindowViewController)]) return;
    self.backgroundColor = ymDynamicBlackOrClear();
}
%end

%hook YTStartupAnimationViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    self.view.backgroundColor = ymDynamicBlackOrWhite();
}
%end

%hook YTEngagementPanelView
- (void)setFooterView:(UIView *)view {
    %orig;
    if (view) {
        view.subviews.firstObject.backgroundColor = ymDynamicBlackOrClear();
    }
}
%end
%end // OLEDTheme

%group OLEDKeyboard
%hook UIKeyboard
- (void)displayLayer:(id)arg1 {
    %orig;
    self.backgroundColor = ymDynamicBlackOrClear();
}
%end

%hook UIPredictionViewController
- (id)_currentTextSuggestions {
    UIKeyboard *keyboard = [%c(UIKeyboard) activeKeyboard];
    self.view.backgroundColor = ymDynamicBlackOrClear();
    keyboard.backgroundColor = ymDynamicBlackOrClear();
    return %orig;
}
%end

%hook UIKeyboardDockView
- (void)layoutSubviews {
    %orig;
    self.backgroundColor = ymDynamicBlackOrClear();
}
%end

%hook UIInputView
- (void)layoutSubviews {
    %orig;
    static Class emojiClass = nil;
    static Class autofillClass = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        emojiClass    = NSClassFromString(@"TUIEmojiSearchInputView");
        autofillClass = NSClassFromString(@"_SFAutoFillInputView");
    });
    if ([self isKindOfClass:emojiClass] || [self isKindOfClass:autofillClass]) {
        self.backgroundColor = ymDynamicBlackOrClear();
    }
}
%end

%hook UIKBVisualEffectView
- (void)layoutSubviews {
    %orig;
    if (isDarkMode(self)) self.backgroundEffects = nil;
    self.backgroundColor = ymDynamicBlackOrClear();
}
%end
%end // OLEDKeyboard

%ctor {
    if (IS_ENABLED(OLEDTheme))    %init(OLEDTheme);
    if (IS_ENABLED(OLEDKeyboard)) %init(OLEDKeyboard);
}
