//
//  FEVideoCaptureFocusLayer.h
//  yyfe
//
//  Created by 陈智颖 on 2017/4/24.
//  Copyright © 2017年 yy.com. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

@interface FEVideoCaptureFocusLayer : CAShapeLayer

+ (CFTimeInterval)animationDuration;

- (instancetype)initWithCenter:(CGPoint)center sideLength:(CGFloat)side color:(UIColor *)color;
- (void)runAnimation;

@end
