//
//  FEVideoCaptureView.h
//  yyfe
//
//  Created by 陈智颖 on 2017/4/19.
//  Copyright © 2017年 yy.com. All rights reserved.
//

#import <UIKit/UIKit.h>

@class FEVideoCaptureView;

typedef NS_ENUM(NSUInteger, FEVideoCaptureProcess) {
    FEVideoCapture_Process_CameraAuthorize, //摄像头权限
    FEVideoCapture_Process_MicroPhoneAuthorize, //麦克风权限
    FEVideoCapture_Process_PhotoAuthorize, //相册权限
    
    FEVideoCapture_Process_ChangeCamera, //切换摄像头
    FEVideoCapture_Process_CombineFragment, //视频片段合成
    FEVideoCapture_Process_ReadFragment, //读取视频片段
    FEVideoCapture_Process_CameraInit, //摄像头初始化
    FEVideoCapture_Process_AudioInit, //音频初始化
    FEVideoCapture_Process_AssetWriter, //单个视频录制写入
    FEVideoCapture_Process_SaveToPhoto, //合成视频写入相册
};



@interface FEVideoCaptureInfo : NSObject

@property (nonatomic) NSTimeInterval videoDuration; //Sec.
@property (nonatomic) CGFloat fileSize; //M
@property (nonatomic, strong) UIImage *thumbnail;
@property (nonatomic, strong) NSString *videoPath;

@end

@interface FEVideoCaptureError : NSObject

@property (nonatomic) FEVideoCaptureProcess process;
@property (nonatomic, copy) NSString *describe;

@end

@interface FEVideoWaterMark : NSObject

@property (nonatomic, strong) UIImage *image;
@property (nonatomic) UIRectCorner position;
@property (nonatomic) CGSize size;
@property (nonatomic) CGPoint padding;

@end



@protocol FEVideoCaptureDelegate <NSObject>

@required
- (void)sessionFinishInitForVideoCaptureView:(FEVideoCaptureView *)videoCapture;
- (void)videoCaptureView:(FEVideoCaptureView *)videoCapture combineResult:(FEVideoCaptureInfo *)info;
- (void)videoCaptureView:(FEVideoCaptureView *)videoCapture processError:(FEVideoCaptureError *)error;

@optional
- (void)videoCaptureView:(FEVideoCaptureView *)videoCapture didCompleteSaveToPhoto:(NSNumber *)success; //Bool

@end



@interface FEVideoCaptureView : UIView

@property (nonatomic) BOOL shouldSaveToPhoto; //default: NO

@property (nonatomic, weak) id<FEVideoCaptureDelegate> delegate;
@property (nonatomic, strong) FEVideoWaterMark *waterMark; //default: nil
@property (nonatomic, strong) UIColor *focusColor; //default: White
@property (nonatomic, copy) NSString *exportPreset; //default: AVAssetExportPresetMediumQuality

- (instancetype)initWithFrame:(CGRect)frame delegate:(id<FEVideoCaptureDelegate>)delegate;

- (void)startRuning; //should call after sessionFinishInitForVideoCaptureView:
- (void)stopRuning;

- (void)startRecord;
- (void)stopRecord;

- (void)deleteLastFragment;
- (void)loadVideoFragment:(NSString *)videoPath completion:(void(^)())complete;

- (void)changeCamera:(void(^)())complete;
- (void)combineAllVideoFragment:(void(^)())complete;

@end
