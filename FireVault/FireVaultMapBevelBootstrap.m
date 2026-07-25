//
//  FireVaultMapBevelBootstrap.m
//  FireVault
//
//  Automatically applies a recessed 3D bezel to every MKMapView.
//

#import <MapKit/MapKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static NSString * const FVMapBevelContainerName = @"FireVault.Map.RecessedBevel";
static NSString * const FVMapOuterStrokeName = @"FireVault.Map.OuterStroke";
static NSString * const FVMapInnerShadowName = @"FireVault.Map.InnerShadow";
static NSString * const FVMapTopLeftShadeName = @"FireVault.Map.TopLeftShade";
static NSString * const FVMapBottomRightHighlightName = @"FireVault.Map.BottomRightHighlight";
static const CGFloat FVMapCornerRadius = 24.0;

@interface MKMapView (FireVaultMapBevel)
- (void)fv_layoutSubviews;
- (void)fv_applyRecessedBevel;
@end

@implementation MKMapView (FireVaultMapBevel)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method original = class_getInstanceMethod(self, @selector(layoutSubviews));
        Method replacement = class_getInstanceMethod(self, @selector(fv_layoutSubviews));
        method_exchangeImplementations(original, replacement);
    });
}

- (void)fv_layoutSubviews {
    [self fv_layoutSubviews];
    [self fv_applyRecessedBevel];
}

- (void)fv_applyRecessedBevel {
    if (CGRectGetWidth(self.bounds) <= 20.0 || CGRectGetHeight(self.bounds) <= 20.0) {
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    self.layer.cornerRadius = FVMapCornerRadius;
    if (@available(iOS 13.0, *)) {
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 1.5;
    self.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.82].CGColor;

    CALayer *container = [self fv_layerNamed:FVMapBevelContainerName inLayer:self.layer];
    if (container == nil) {
        container = [CALayer layer];
        container.name = FVMapBevelContainerName;
        container.zPosition = 10000;
        container.masksToBounds = YES;
        [self.layer addSublayer:container];
    }

    container.frame = self.bounds;
    container.cornerRadius = FVMapCornerRadius;
    if (@available(iOS 13.0, *)) {
        container.cornerCurve = kCACornerCurveContinuous;
    }

    CAShapeLayer *outerStroke = [self fv_shapeLayerNamed:FVMapOuterStrokeName inLayer:container];
    outerStroke.frame = container.bounds;
    outerStroke.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(container.bounds, 1.5, 1.5)
                                                   cornerRadius:FVMapCornerRadius - 1.5].CGPath;
    outerStroke.fillColor = UIColor.clearColor.CGColor;
    outerStroke.strokeColor = [UIColor colorWithWhite:0 alpha:0.78].CGColor;
    outerStroke.lineWidth = 3.0;

    CAShapeLayer *innerShadow = [self fv_shapeLayerNamed:FVMapInnerShadowName inLayer:container];
    innerShadow.frame = container.bounds;
    innerShadow.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(container.bounds, 4.0, 4.0)
                                                  cornerRadius:FVMapCornerRadius - 4.0].CGPath;
    innerShadow.fillColor = UIColor.clearColor.CGColor;
    innerShadow.strokeColor = [UIColor colorWithWhite:0 alpha:0.48].CGColor;
    innerShadow.lineWidth = 5.0;

    CAShapeLayer *topLeftShade = [self fv_shapeLayerNamed:FVMapTopLeftShadeName inLayer:container];
    topLeftShade.frame = container.bounds;
    topLeftShade.path = [self fv_topLeftPathForBounds:container.bounds].CGPath;
    topLeftShade.fillColor = UIColor.clearColor.CGColor;
    topLeftShade.strokeColor = [UIColor colorWithWhite:0 alpha:0.88].CGColor;
    topLeftShade.lineWidth = 3.2;
    topLeftShade.lineCap = kCALineCapRound;
    topLeftShade.lineJoin = kCALineJoinRound;

    CAShapeLayer *bottomRightHighlight = [self fv_shapeLayerNamed:FVMapBottomRightHighlightName inLayer:container];
    bottomRightHighlight.frame = container.bounds;
    bottomRightHighlight.path = [self fv_bottomRightPathForBounds:container.bounds].CGPath;
    bottomRightHighlight.fillColor = UIColor.clearColor.CGColor;
    bottomRightHighlight.strokeColor = [UIColor colorWithWhite:1 alpha:0.27].CGColor;
    bottomRightHighlight.lineWidth = 1.4;
    bottomRightHighlight.lineCap = kCALineCapRound;
    bottomRightHighlight.lineJoin = kCALineJoinRound;

    [CATransaction commit];
}

- (CALayer *)fv_layerNamed:(NSString *)name inLayer:(CALayer *)parent {
    for (CALayer *layer in parent.sublayers) {
        if ([layer.name isEqualToString:name]) {
            return layer;
        }
    }
    return nil;
}

- (CAShapeLayer *)fv_shapeLayerNamed:(NSString *)name inLayer:(CALayer *)parent {
    CALayer *existing = [self fv_layerNamed:name inLayer:parent];
    if ([existing isKindOfClass:CAShapeLayer.class]) {
        return (CAShapeLayer *)existing;
    }

    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.name = name;
    [parent addSublayer:layer];
    return layer;
}

- (UIBezierPath *)fv_topLeftPathForBounds:(CGRect)bounds {
    CGRect rect = CGRectInset(bounds, 3.0, 3.0);
    CGFloat radius = FVMapCornerRadius;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(CGRectGetMaxX(rect) - radius, CGRectGetMinY(rect))];
    [path addLineToPoint:CGPointMake(CGRectGetMinX(rect) + radius, CGRectGetMinY(rect))];
    [path addQuadCurveToPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect) + radius)
                 controlPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect))];
    [path addLineToPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect) - radius)];
    return path;
}

- (UIBezierPath *)fv_bottomRightPathForBounds:(CGRect)bounds {
    CGRect rect = CGRectInset(bounds, 3.0, 3.0);
    CGFloat radius = FVMapCornerRadius;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(CGRectGetMinX(rect) + radius, CGRectGetMaxY(rect))];
    [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect) - radius, CGRectGetMaxY(rect))];
    [path addQuadCurveToPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect) - radius)
                 controlPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect))];
    [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect) + radius)];
    return path;
}

@end
