//
//  FEVideoCaptureFocusLayer.m
//  yyfe
//
//  Created by 陈智颖 on 2017/4/24.
//  Copyright © 2017年 yy.com. All rights reserved.
//

#import "FEVideoCaptureFocusLayer.h"

@interface FEVideoCaptureFocusLayer () <CAAnimationDelegate> {
    CGFloat _side;
    UIColor *_focusColor;
}

@end

@implementation FEVideoCaptureFocusLayer

+ (CFTimeInterval)animationDuration {
    return 1.8;
}

- (instancetype)initWithCenter:(CGPoint)center sideLength:(CGFloat)side color:(UIColor *)color {
    self = [[super class] layer];
    if (self) {
        _side = side;
        _focusColor = color;
        self.frame = CGRectMake(center.x - side / 2, center.y - side / 2, side, side);
        [self initSelf];
    }
    return self;
}

- (void)initSelf {
    
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat side = _side / 2;
    CGFloat dot = side / 4;
    CGPoint centerPoint = CGPointMake(side, side);
    [path moveToPoint:CGPointMake(centerPoint.x - side, centerPoint.y - side)];
    [path addLineToPoint:CGPointMake(centerPoint.x, centerPoint.y - side)];
    [path addLineToPoint:CGPointMake(centerPoint.x, centerPoint.y - side + dot)];
    [path addLineToPoint:CGPointMake(centerPoint.x, centerPoint.y - side)];
    [path addLineToPoint:CGPointMake(centerPoint.x + side, centerPoint.y - side)];
    
    [path addLineToPoint:CGPointMake(centerPoint.x + side, centerPoint.y)];
    [path addLineToPoint:CGPointMake(centerPoint.x + side - dot, centerPoint.y)];
    [path addLineToPoint:CGPointMake(centerPoint.x + side, centerPoint.y)];
    [path addLineToPoint:CGPointMake(centerPoint.x + side, centerPoint.y + side)];
    
    [path addLineToPoint:CGPointMake(centerPoint.x, centerPoint.y + side)];
    [path addLineToPoint:CGPointMake(centerPoint.x, centerPoint.y + side - dot)];
    [path addLineToPoint:CGPointMake(centerPoint.x, centerPoint.y + side)];
    [path addLineToPoint:CGPointMake(centerPoint.x - side, centerPoint.y + side)];
    
    [path addLineToPoint:CGPointMake(centerPoint.x - side, centerPoint.y)];
    [path addLineToPoint:CGPointMake(centerPoint.x - side + dot, centerPoint.y)];
    [path addLineToPoint:CGPointMake(centerPoint.x - side, centerPoint.y)];
    [path addLineToPoint:CGPointMake(centerPoint.x - side, centerPoint.y - side)];
    
    self.path = path.CGPath;
    self.lineWidth = 1;
    self.strokeColor = _focusColor.CGColor;
    self.fillColor = [UIColor clearColor].CGColor;
    
    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"opacity"];
    anim.fromValue = @1;
    anim.toValue = @0.2;
    anim.repeatCount = 3;
    anim.duration = 0.2;
    [self addAnimation:anim forKey:nil];
}

- (void)runAnimation {
    CABasicAnimation *scale1 = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scale1.fromValue = @1.5;
    scale1.toValue = @1;
    scale1.duration = 0.3;
    
    CABasicAnimation *scale2 = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scale2.fromValue = @1;
    scale2.toValue = @1;
    scale2.beginTime = 0.3;
    scale2.duration = 1.5;
    
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = @[scale1, scale2];
    group.duration = [FEVideoCaptureFocusLayer animationDuration];
    group.delegate = self;
    
    [self addAnimation:group forKey:nil];
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag {
     [self removeFromSuperlayer];
}


@end
