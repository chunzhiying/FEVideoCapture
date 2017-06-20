//
//  ATMotionManager.m
//  yyfe
//
//  Created by 陈智颖 on 2017/6/1.
//  Copyright © 2017年 yy.com. All rights reserved.
//

#import "ATMotionManager.h"
#import <CoreMotion/CoreMotion.h>

#define UpdateInterval 0.5

NSString * const ATMotionManager_OrientationChange_Notification = @"ATMotionManager_OrientationChange_Notification";
NSString * const ATMotionManager_OrientationChange_Key = @"ATMotionManager_OrientationChange_Key";

@interface ATMotionManager ()

@property (nonatomic) UIDeviceOrientation orientation;
@property (nonatomic, strong) CMMotionManager *motionManager;
@property (nonatomic, strong) NSOperationQueue *queue;

@end

@implementation ATMotionManager

+ (instancetype)sharedObject {
    static dispatch_once_t __once;
    static ATMotionManager *__instance = nil;
    dispatch_once(&__once, ^{
        __instance = [[ATMotionManager alloc] init];
    });
    return __instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self startMotionManager];
    }
    return self;
}

+ (UIDeviceOrientation)orientation {
    return [ATMotionManager sharedObject].orientation;
}

- (void)startMotionManager{
    
    _orientation = UIDeviceOrientationPortrait;
    _queue = [NSOperationQueue new];
    _motionManager = [[CMMotionManager alloc] init];
    _motionManager.deviceMotionUpdateInterval = UpdateInterval;
    
    if (_motionManager.deviceMotionAvailable) {
        NSLog(@"Device Motion Available");
        [_motionManager startDeviceMotionUpdatesToQueue:_queue
                                            withHandler: ^(CMDeviceMotion *motion, NSError *error){
                                                [self performSelectorOnMainThread:@selector(handleDeviceMotion:) withObject:motion waitUntilDone:YES];
                                            }];
    } else {
        NSLog(@"No device motion on device.");
        _motionManager = nil;
    }
}

- (void)handleDeviceMotion:(CMDeviceMotion *)deviceMotion{
    double x = deviceMotion.gravity.x;
    double y = deviceMotion.gravity.y;
    UIDeviceOrientation newOrientation;
    if (fabs(y) >= fabs(x))
    {
        if (y >= 0) {
            newOrientation = UIDeviceOrientationPortraitUpsideDown;
        }
        else {
            newOrientation = UIDeviceOrientationPortrait;
        }
    }
    else
    {
        if (x >= 0) {
            newOrientation = UIDeviceOrientationLandscapeRight;
        }
        else {
            newOrientation = UIDeviceOrientationLandscapeLeft;
        }
    }
    
    if (newOrientation != _orientation) {
        _orientation = newOrientation;
        [[NSNotificationCenter defaultCenter] postNotificationName:ATMotionManager_OrientationChange_Notification object:nil
                                                          userInfo: @{ATMotionManager_OrientationChange_Key : @(newOrientation)}];
        NSLog(@"orientation: %ld", (long)newOrientation);
    }
}


@end
