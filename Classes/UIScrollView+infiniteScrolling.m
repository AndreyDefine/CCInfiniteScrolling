//
//  UIScrollView+infiniteScrolling.m
//  Overhear
//
//  Created by ziryanov on 02/11/13.
//
//

#import "UIScrollView+infiniteScrolling.h"
#import <JRSwizzle/JRSwizzle.h>
#import <objc/runtime.h>
#import "UIView+TKGeometry.h"

@interface ISBlockObjectContainer : NSObject

@property (nonatomic, copy) void(^block)(void);
- (instancetype)initWithBlock:(void(^)(void))block;

@end

@implementation ISBlockObjectContainer

- (instancetype)initWithBlock:(void(^)(void))block
{
    self = [super init];
    if (self) {
        self.block = block;
    }
    return self;
}


@end

#define ISCATEGORY_PROPERTY_GET(type, property) - (type) property { return objc_getAssociatedObject(self, @selector(property)); }
#define ISCATEGORY_PROPERTY_SET(type, property, setter) - (void) setter (type) property { objc_setAssociatedObject(self, @selector(property), property, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
#define ISCATEGORY_PROPERTY_GET_SET(type, property, setter) ISCATEGORY_PROPERTY_GET(type, property) ISCATEGORY_PROPERTY_SET(type, property, setter)


#define ISCATEGORY_BLOCKPROPERTY_GET(type, property) - (type) property { return [objc_getAssociatedObject(self, @selector(property)) block]; }
#define ISCATEGORY_BLOCKPROPERTY_SET(type, property, setter) - (void) setter (type) property { objc_setAssociatedObject(self, @selector(property), [[ISBlockObjectContainer alloc] initWithBlock:property], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
#define ISCATEGORY_BLOCKPROPERTY_GET_SET(type, property, setter) ISCATEGORY_BLOCKPROPERTY_GET(type, property) ISCATEGORY_BLOCKPROPERTY_SET(type, property, setter)

@implementation UIView (infiniteScrollRemoveAllSubviews)

- (void)is_removeAllSubviews
{
    for (UIView *view in [self.subviews copy])
        [view removeFromSuperview];
}

@end

static UIImage *is_blockFailedImage = 0;
static CGFloat is_infinityScrollingTriggerOffset = 0;

@interface UIScrollView (infiniteScrollingPrivate)

@property (nonatomic, copy) void(^is_topBlock)(void);
@property (nonatomic, copy) void(^is_bottomBlock)(void);

@property (nonatomic) NSNumber *is_topBlockInProgress;
@property (nonatomic) NSNumber *is_topDisabled;
@property (nonatomic) NSNumber *is_topUndisablingInProgress;
@property (nonatomic) NSNumber *is_bottomBlockInProgress;
@property (nonatomic) NSNumber *is_bottomDisabled;
@property (nonatomic) NSNumber *is_bottomUndisablingInProgress;

@property (nonatomic) NSValue *is_contentSize;
@property (nonatomic) NSValue *is_contentInset;

@property (nonatomic) UIView *is_topBox;
@property (nonatomic) UIView *is_bottomBox;

@end

//--------------------------------------------------------------------------------------------------------------------------------------------

@implementation UIScrollView (infiniteScrollingPrivate)

ISCATEGORY_BLOCKPROPERTY_GET_SET(void(^)(void), is_topBlock, setIs_topBlock:)
ISCATEGORY_PROPERTY_GET_SET(NSNumber *, is_topBlockInProgress, setIs_topBlockInProgress:)

ISCATEGORY_BLOCKPROPERTY_GET_SET(void(^)(void), is_bottomBlock, setIs_bottomBlock:)
ISCATEGORY_PROPERTY_GET_SET(NSNumber *, is_bottomBlockInProgress, setIs_bottomBlockInProgress:)

ISCATEGORY_PROPERTY_GET_SET(NSNumber *, is_topDisabled, setIs_topDisabled:)
ISCATEGORY_PROPERTY_GET_SET(NSNumber *, is_topBox, setIs_topBox:)
ISCATEGORY_PROPERTY_GET_SET(NSNumber *, is_topUndisablingInProgress, setIs_topUndisablingInProgress:)

ISCATEGORY_PROPERTY_GET_SET(NSNumber *, is_bottomDisabled, setIs_bottomDisabled:)
ISCATEGORY_PROPERTY_GET_SET(NSNumber *, is_bottomBox, setIs_bottomBox:)
ISCATEGORY_PROPERTY_GET_SET(NSNumber *, is_bottomUndisablingInProgress, setIs_bottomUndisablingInProgress:)

ISCATEGORY_PROPERTY_GET_SET(NSValue *, is_contentSize, setIs_contentSize:)
ISCATEGORY_PROPERTY_GET_SET(NSValue *, is_contentInset, setIs_contentInset:)

@end

//--------------------------------------------------------------------------------------------------------------------------------------------

@implementation UIScrollView (infiniteScrolling)
@dynamic infiniteScrollingDisabled, infiniteScrollingBlockFailed;


ISCATEGORY_PROPERTY_GET_SET(UIView *, infiniteScrollingCustomView, setInfiniteScrollingCustomView:)
ISCATEGORY_PROPERTY_GET_SET(UIView *, infiniteScrollingCustomFailedView, setInfiniteScrollingCustomFailedView:)
ISCATEGORY_PROPERTY_GET_SET(UIView *, topInfiniteScrollingCustomView, setTopInfiniteScrollingCustomView:)
ISCATEGORY_PROPERTY_GET_SET(UIView *, topInfiniteScrollingCustomFailedView, setTopInfiniteScrollingCustomFailedView:)

ISCATEGORY_PROPERTY_GET_SET(NSNumber *, infinityScrollingTriggerOffset, setInfinityScrollingTriggerOffset:)
ISCATEGORY_PROPERTY_GET_SET(UIView *, bottomInfiniteScrollingCustomView, setBottomInfiniteScrollingCustomView:)
ISCATEGORY_PROPERTY_GET_SET(UIView *, bottomInfiniteScrollingCustomFailedView, setBottomInfiniteScrollingCustomFailedView:)

+ (void)setInfinityScrollingCustomBlockFailedImage:(UIImage *)image
{
    is_blockFailedImage = image;
}

+ (void)setInfinityScrollingTriggerOffset:(CGFloat)triggerOffset
{
    is_infinityScrollingTriggerOffset = triggerOffset;
}

- (UIView *)is_createDefaultInfiniteScrollingView 
{
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    view.backgroundColor = [UIColor clearColor];
    UIActivityIndicatorView *activity = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    activity.center = view.center;
    [activity startAnimating];
    [view addSubview:activity];
    return view;
}

- (void)addTopInfiniteScrollingWithActionHandler:(void (^)(void))actonHandler
{
    self.is_topBlock = actonHandler;
    
    if (!self.topInfiniteScrollingCustomView)
        self.topInfiniteScrollingCustomView = self.infiniteScrollingCustomView ?: [self is_createDefaultInfiniteScrollingView];
    if (!self.infiniteScrollingCustomView)
        self.infiniteScrollingCustomView = self.topInfiniteScrollingCustomView;
    if (!self.is_topBox)
        self.is_topBox = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, self.topInfiniteScrollingCustomView.height)];
    
    [self.is_topBox is_removeAllSubviews];
    
    [self addView:self.topInfiniteScrollingCustomView toView:self.is_topBox];
}

- (void)addBottomInfiniteScrollingWithActionHandler:(void (^)(void))actonHandler
{
    self.is_bottomBlock = actonHandler;
    
    if (!self.bottomInfiniteScrollingCustomView)
        self.bottomInfiniteScrollingCustomView = self.infiniteScrollingCustomView ?: [self is_createDefaultInfiniteScrollingView];
    if (!self.infiniteScrollingCustomView)
        self.infiniteScrollingCustomView = self.bottomInfiniteScrollingCustomView;
    if (!self.is_bottomBox)
        self.is_bottomBox = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, self.bottomInfiniteScrollingCustomView.height)];
    
    [self.is_bottomBox is_removeAllSubviews];
    
    [self addView:self.bottomInfiniteScrollingCustomView toView:self.is_bottomBox];
}

//---------------------------------------------------------------------------------------------------------

+ (void)load
{
    [self jr_swizzleMethod:@selector(setContentOffset:) withMethod:@selector(is_setContentOffset:) error:nil];
    [self jr_swizzleMethod:@selector(setContentSize:) withMethod:@selector(is_setContentSize:) error:nil];
    [self jr_swizzleMethod:@selector(contentSize) withMethod:@selector(is_ContentSize) error:nil];
    [self jr_swizzleMethod:@selector(setContentInset:) withMethod:@selector(is_setContentInset:) error:nil];
    [self jr_swizzleMethod:@selector(contentInset) withMethod:@selector(is_ContentInset) error:nil];
}

- (void)infiniteScrollViewContentUpdated
{
    self.is_topBlockInProgress = @NO;
    self.is_bottomBlockInProgress = @NO;
}

- (CGFloat)is_infinityScrollingTriggerOffset
{
    return self.infinityScrollingTriggerOffset.floatValue ?: (is_infinityScrollingTriggerOffset ?: self.height);
}

- (BOOL)is_checkContentOffset:(BOOL *)top
{
    if ([self is_checkForEmptyContent])
        return NO;
    CGFloat infinityScrollingTriggerOffset = MIN(self.is_infinityScrollingTriggerOffset, self.contentHeight - self.is_infinityScrollingTriggerOffset);
    if (top)
        *top = self.is_topBlock != 0 && self.contentOffsetY < infinityScrollingTriggerOffset;
    
    return (self.is_bottomBlock != 0 && self.contentOffsetY > self.contentHeight - self.height - infinityScrollingTriggerOffset) ||
    (self.is_topBlock != 0 && self.contentOffsetY < infinityScrollingTriggerOffset);
}

- (BOOL)is_checkForEmptyContent
{
    return (self.height == 0 || self.contentHeight < 1);
}

- (void)is_setContentOffset:(CGPoint)contentOffset
{
    [self is_setContentOffset:contentOffset];
    if (!self.is_topBlock && !self.is_bottomBlock)
        return;
    BOOL blocksEnabled = (self.is_topBlock != 0 && !self.topInfiniteScrollingDisabled) ||
    (self.is_bottomBlock != 0 && !self.bottomInfiniteScrollingDisabled);
    if (!blocksEnabled)
        return;
    
    if ([self is_checkForEmptyContent])
        return;
    
    if ([self is_checkContentOffset:0])
    {
        double delayInSeconds = .05;
        if (self.is_topUndisablingInProgress.boolValue || self.is_bottomUndisablingInProgress.boolValue)
            delayInSeconds = .5;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            if (self.is_topUndisablingInProgress.boolValue || self.is_bottomUndisablingInProgress.boolValue)
                return;
            BOOL top;
            if (![self is_checkContentOffset:&top])
                return;
            if (top && !self.is_topBlockInProgress.boolValue && !self.topInfiniteScrollingBlockFailed)
            {
                self.is_topBlockInProgress = @YES;
                self.is_topBlock();
            }
            else if (!top && !self.is_bottomBlockInProgress.boolValue && !self.bottomInfiniteScrollingBlockFailed)
            {
                self.is_bottomBlockInProgress = @YES;
                self.is_bottomBlock();
            }
        });
    }
}

- (void)is_setContentInset:(UIEdgeInsets)contentInset
{
    self.is_contentInset = [NSValue valueWithUIEdgeInsets:contentInset];
    [self is_updateContent];
}

- (UIEdgeInsets)is_ContentInset
{
    return [self.is_contentInset UIEdgeInsetsValue];
}

- (void)is_setContentSize:(CGSize)contentSize
{
    self.is_contentSize = [NSValue valueWithCGSize:contentSize];
    [self is_updateContent];
}

- (CGSize)is_ContentSize
{
    return [self.is_contentSize CGSizeValue];
}

- (void)is_updateContent
{
    CGSize contentSize = [self.is_contentSize CGSizeValue];
    UIEdgeInsets contentInset = [self.is_contentInset UIEdgeInsetsValue];
    
    BOOL topISViewVisible = self.is_topBlock != 0 && !self.topInfiniteScrollingDisabled && contentSize.height > self.height;
    BOOL bottomISViewVisible = self.is_bottomBlock != 0 && !self.bottomInfiniteScrollingDisabled && contentSize.height > self.height;
    
    if (topISViewVisible)
    {
        contentInset.top += self.is_topBox.height;
        
        if (!self.is_topBox.superview)
            [self addSubview:self.is_topBox];
        self.is_topBox.maxY = 0;
    }
    else
    {
        if (self.is_topBox.superview)
            [self.is_topBox removeFromSuperview];
    }
    
    if (bottomISViewVisible)
    {
        contentSize.height += self.is_bottomBox.height;
        
        if (!self.is_bottomBox.superview)
            [self addSubview:self.is_bottomBox];
        self.is_bottomBox.maxY = contentSize.height;
    }
    else
    {
        if (self.is_bottomBox.superview)
            [self.is_bottomBox removeFromSuperview];
    }
    
    [self is_setContentSize:contentSize];
    [self is_setContentInset:contentInset];
}

//--------------------------------------------------------------------------------------------------------------------------------------------

- (void)setInfiniteScrollingDisabled:(BOOL)infiniteScrollingDisabled
{
    if (self.is_topBlock != 0)
        self.topInfiniteScrollingDisabled = infiniteScrollingDisabled;
    else if (self.is_bottomBlock != 0)
        self.bottomInfiniteScrollingDisabled = infiniteScrollingDisabled;
}

- (BOOL)infiniteScrollingDisabled
{
    if (self.is_topBlock != 0)
        return self.topInfiniteScrollingDisabled;
    else if (self.is_bottomBlock != 0)
        return self.bottomInfiniteScrollingDisabled;
    return NO;
}

- (void)setInfiniteScrollingBlockFailed:(BOOL)infiniteScrollingBlockFailed
{
    if (self.is_topBlock != 0)
        self.topInfiniteScrollingBlockFailed = infiniteScrollingBlockFailed;
    else if (self.is_bottomBlock != 0)
        self.bottomInfiniteScrollingBlockFailed = infiniteScrollingBlockFailed;
}

- (BOOL)infiniteScrollingBlockFailed
{
    if (self.is_topBlock != 0)
        return self.topInfiniteScrollingBlockFailed;
    else if (self.is_bottomBlock != 0)
        return self.bottomInfiniteScrollingBlockFailed;
    return NO;
}

//--------------------------------------------------------------------------------------------------------------------------------------------

- (void)setTopInfiniteScrollingDisabled:(BOOL)topInfiniteScrollingDisabled
{
    if (self.is_topDisabled.boolValue && !topInfiniteScrollingDisabled)
    {
        self.is_topUndisablingInProgress = @YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.is_topUndisablingInProgress = @NO;
        });
    }
    CGFloat contentOffsetY = self.contentOffsetY;
    CGFloat contentHeight = self.contentHeight;
    self.is_topDisabled = @(topInfiniteScrollingDisabled);
    [self is_updateContent];
    self.contentOffsetY = contentOffsetY + (self.contentHeight - contentHeight);
}

- (BOOL)topInfiniteScrollingDisabled
{
    return self.is_topDisabled.boolValue;
}

- (void)setBottomInfiniteScrollingDisabled:(BOOL)bottomInfiniteScrollingDisabled
{
    if (self.is_bottomDisabled.boolValue && !bottomInfiniteScrollingDisabled)
    {
        self.is_bottomUndisablingInProgress = @YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.is_bottomUndisablingInProgress = @NO;
        });
    }
    self.is_bottomDisabled = @(bottomInfiniteScrollingDisabled);
    [self is_updateContent];
}

- (BOOL)bottomInfiniteScrollingDisabled
{
    return self.is_bottomDisabled.boolValue;
}

//--------------------------------------------------------------------------------------------------------------------------------------------

- (UIView *)is_createDefaultInfiniteScrollingBlockFailedView:(BOOL)top
{
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    view.backgroundColor = [UIColor clearColor];
    UIButton *button = [[UIButton alloc] initWithFrame:view.bounds];
    static UIImage *podImage;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *podBundle = [NSBundle bundleForClass:ISBlockObjectContainer.class];
        podImage = [UIImage imageNamed:@"CCInfiniteScrolling.bundle/infinite_scrolling_reload" inBundle:podBundle compatibleWithTraitCollection:nil];
    });
    [button setImage:is_blockFailedImage ?: podImage forState:UIControlStateNormal];
    [button addTarget:self action:(top ? @selector(topAction) : @selector(bottomAction)) forControlEvents:UIControlEventTouchUpInside];
    [self addView:button toView:view];
    return view;
}

- (void)topAction
{
    self.topInfiniteScrollingBlockFailed = NO;
    self.is_topBlock();
}

- (void)bottomAction
{
    self.bottomInfiniteScrollingBlockFailed = NO;
    self.is_bottomBlock();
}

- (void)addView:(UIView *)viewToAdd toView:(UIView *)superview
{
    [superview is_removeAllSubviews];
    viewToAdd.translatesAutoresizingMaskIntoConstraints = YES;
    viewToAdd.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    viewToAdd.xCenter = superview.width / 2;
    [superview addSubview:viewToAdd];
}

- (void)setTopInfiniteScrollingBlockFailed:(BOOL)topInfiniteScrollingBlockFailed
{
    if (!self.topInfiniteScrollingCustomFailedView)
        self.topInfiniteScrollingCustomFailedView = (self.infiniteScrollingCustomFailedView && self.infiniteScrollingCustomFailedView != self.bottomInfiniteScrollingCustomFailedView) ? self.infiniteScrollingCustomFailedView : [self is_createDefaultInfiniteScrollingBlockFailedView:YES];
    if (!self.infiniteScrollingCustomFailedView)
        self.infiniteScrollingCustomFailedView = self.topInfiniteScrollingCustomFailedView;
    [self addView:topInfiniteScrollingBlockFailed ? self.topInfiniteScrollingCustomFailedView : self.topInfiniteScrollingCustomView toView:self.is_topBox];
}

- (BOOL)topInfiniteScrollingBlockFailed
{
    return [self.is_topBox subviews].count && [self.is_topBox subviews][0] == self.topInfiniteScrollingCustomFailedView;
}

- (void)setBottomInfiniteScrollingBlockFailed:(BOOL)bottomInfiniteScrollingBlockFailed
{
    if (!self.bottomInfiniteScrollingCustomFailedView)
        self.bottomInfiniteScrollingCustomFailedView = (self.infiniteScrollingCustomFailedView && self.infiniteScrollingCustomFailedView != self.topInfiniteScrollingCustomFailedView) ? self.infiniteScrollingCustomFailedView : [self is_createDefaultInfiniteScrollingBlockFailedView:NO];
    if (!self.infiniteScrollingCustomFailedView)
        self.infiniteScrollingCustomFailedView = self.bottomInfiniteScrollingCustomFailedView;
    [self addView:bottomInfiniteScrollingBlockFailed ? self.bottomInfiniteScrollingCustomFailedView : self.bottomInfiniteScrollingCustomView toView:self.is_bottomBox];
}

- (BOOL)bottomInfiniteScrollingBlockFailed
{
    return [self.is_bottomBox subviews].count && [self.is_bottomBox subviews][0] == self.bottomInfiniteScrollingCustomFailedView;
}

//--------------------------------------------------------------------------------------------------------------------------------------------

- (void)scrollToBottom
{
    self.contentOffsetY = MAX(-self.contentInsetTop, self.contentInsetBottom + self.contentHeight - self.height);
}

@end

@implementation UITableView (infiniteScrollingHelper)

+ (void)load
{
    [self jr_swizzleMethod:@selector(reloadData) withMethod:@selector(is_reloadData) error:nil];
}

- (void)is_reloadData
{
    [self is_reloadData];
    [self infiniteScrollViewContentUpdated];
}

- (void)reloadDataKeepBottomOffset
{
    CGFloat contentOffsetY = self.contentOffsetY;
    CGFloat contentHeight = self.contentHeight;
    [self reloadData];
    self.contentOffsetY = contentOffsetY + (self.contentHeight - contentHeight);
}

@end

@implementation UICollectionView (infiniteScrollingHelper)

+ (void)load
{
    [self jr_swizzleMethod:@selector(reloadData) withMethod:@selector(is_reloadData) error:nil];
}

- (void)is_reloadData
{
    [self is_reloadData];
    [self infiniteScrollViewContentUpdated];
}

- (void)reloadDataKeepBottomOffset
{
    CGFloat contentOffsetY = self.contentOffsetY;
    CGFloat contentHeight = self.contentHeight;
    [self reloadData];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.contentOffsetY = contentOffsetY + (self.contentHeight - contentHeight);
    });
}

@end
