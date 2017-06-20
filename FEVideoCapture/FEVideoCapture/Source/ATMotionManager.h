//
//  ATMotionManager.h
//  yyfe
//
//  Created by 陈智颖 on 2017/6/1.
//  Copyright © 2017年 yy.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern NSString * const ATMotionManager_OrientationChange_Notification;
extern NSString * const ATMotionManager_OrientationChange_Key;

@interface ATMotionManager : NSObject

+ (instancetype)sharedObject;
+ (UIDeviceOrientation)orientation;

@end
