//
//  ViewController.m
//  Demo
//
//  Created by 陈智颖 on 2017/5/3.
//  Copyright © 2017年 YY. All rights reserved.
//

#import "ViewController.h"
#import <FEVideoCapture/FEVideoCaptureView.h>

@interface ViewController () <FEVideoCaptureDelegate>

@property (strong, nonatomic) FEVideoCaptureView *captureView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _captureView = [[FEVideoCaptureView alloc] initWithFrame:CGRectMake(0, 0, 200, 400) delegate:self];
    [self.view insertSubview:_captureView atIndex:0];
    
}

#pragma mark - FEVideoCaptureDelegate
- (void)sessionFinishInitForVideoCaptureView:(FEVideoCaptureView *)videoCapture {
     [_captureView startRuning];
}

- (void)videoCaptureView:(FEVideoCaptureView *)videoCapture combineResult:(FEVideoCaptureInfo *)info {
    
}

- (void)videoCaptureView:(FEVideoCaptureView *)videoCapture processError:(FEVideoCaptureError *)error {
    NSLog(@"%@", error.describe);
}


#pragma mark - IBAction
- (IBAction)changeCamera:(id)sender {
    [_captureView changeCamera:^{
    }];
}

- (IBAction)startRuning:(id)sender {
    [_captureView startRuning];
}

- (IBAction)endRuning:(id)sender {
    [_captureView stopRuning];
}

- (IBAction)startRecord:(id)sender {
    [_captureView startRecord];
}

- (IBAction)endRecord:(id)sender {
    [_captureView stopRecord];
}

- (IBAction)merge:(id)sender {
    [_captureView combineAllVideoFragment:^{
    
    }];
}

@end
