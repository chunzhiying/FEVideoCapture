//
//  FEVideoCaptureView.m
//  yyfe
//
//  Created by 陈智颖 on 2017/4/19.
//  Copyright © 2017年 yy.com. All rights reserved.
//

#import "FEVideoCaptureView.h"
#import "FEVideoCaptureFocusLayer.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>

#define FocusRectSideLength 80

#define TempPath NSTemporaryDirectory()

#define TempRecordPre @"FEVideoCapture"

#define TempPathOf(atFile) \
[NSString stringWithFormat:@"%@%@", TempPath, atFile]

#define TempRecordDirectory \
[NSString stringWithFormat:@"%@%@%@%@", TempPath, TempRecordPre, @"_TempRecord_", _timeline]

#define TempRecordPath(atNum) \
[NSString stringWithFormat:@"%@/record_%lu.mp4", TempRecordDirectory, atNum]

#define TemRecordMergePath \
[NSString stringWithFormat:@"%@/record_merge.mp4", TempRecordDirectory]


#define SafetyCallblock(block, ...) if((block)) { block(__VA_ARGS__); }

#define ScreenShort MIN([UIScreen mainScreen].bounds.size.height, [UIScreen mainScreen].bounds.size.width)
#define ScreenLong  MAX([UIScreen mainScreen].bounds.size.height, [UIScreen mainScreen].bounds.size.width)


#define PerformProcessError($process, $describe) \
if (self.delegate && [self.delegate respondsToSelector:@selector(videoCaptureView:processError:)]) { \
    [self.delegate performSelector:@selector(videoCaptureView:processError:) withObject:self withObject:[FEVideoCaptureError process: $process describe:$describe]]; \
}

#define PerformCombineResult($result) \
if (self.delegate && [self.delegate respondsToSelector:@selector(videoCaptureView:combineResult:)]) { \
    [self.delegate performSelector:@selector(videoCaptureView:combineResult:) withObject:self withObject:$result]; \
}

#define PerformSaveToPhotoResult($result) \
if (self.delegate && [self.delegate respondsToSelector:@selector(videoCaptureView:didCompleteSaveToPhoto:)]) { \
    [self.delegate performSelector:@selector(videoCaptureView:didCompleteSaveToPhoto:) withObject:self withObject:$result]; \
}

#define PerformSessionFinishInit \
if (self.delegate && [self.delegate respondsToSelector:@selector(sessionFinishInitForVideoCaptureView:)]) { \
    [self.delegate performSelector:@selector(sessionFinishInitForVideoCaptureView:) withObject:self]; \
}


@implementation FEVideoCaptureInfo

@end

@implementation FEVideoCaptureError

+ (instancetype)process:(FEVideoCaptureProcess)process describe:(NSString *)desc {
    FEVideoCaptureError *error = [FEVideoCaptureError new];
    error.process = process;
    error.describe = desc;
    return error;
}

@end

@implementation AVURLAsset (FEVideoCapture_Thumbnail)

- (UIImage *)getThumbnail {
    AVAssetTrack *assetVideoTrack = [[self tracksWithMediaType:AVMediaTypeVideo] firstObject];
    CMTime thumbnailTime = CMTimeMake(10, assetVideoTrack.timeRange.duration.timescale);
    
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:self];
    gen.appliesPreferredTrackTransform = YES;
    CGImageRef thumbnailImageRef = [gen copyCGImageAtTime:thumbnailTime actualTime:NULL error:nil];
    UIImage *thumbnail = [UIImage imageWithCGImage:thumbnailImageRef];
    CGImageRelease(thumbnailImageRef);
    
    return thumbnail;
}

@end



@interface FEVideoCaptureView () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>
{
    BOOL _writing;
    BOOL _audioCanAppend;
    BOOL _changingCamera;
    
    NSString *_timeline;
    AVCaptureDevicePosition _cameraPosition;
    AVCaptureVideoOrientation _videoOrientation;
    NSMutableArray<NSString *> *_recordPathAry;
    
    FEVideoCaptureFocusLayer *_focusLayer;
    
    dispatch_queue_t _videoQueue;
    dispatch_queue_t _audioQueue;
}

#ifndef __IPHONE_8_0
@property (nonatomic, strong) ALAssetsLibrary *library;
#endif

@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDeviceInput *videoInput;
@property (nonatomic, strong) AVCaptureDeviceInput *audioInput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

@property (nonatomic, strong) AVAssetWriter *assetWriter;
@property (nonatomic, strong) AVAssetWriterInput *videoWriter;
@property (nonatomic, strong) AVAssetWriterInput *audioWriter;

@end


@implementation FEVideoCaptureView (File)

#pragma mark - File
- (void)createFileDirectory {
    [self removeFileDirecotry];
    _timeline = [NSDate date].description;
    [[NSFileManager defaultManager] createDirectoryAtPath:TempRecordDirectory
                              withIntermediateDirectories:NO attributes:nil error:nil];
    
    [self cleanExpiredDirectory];
}

- (void)removeFileDirecotry {
    [[NSFileManager defaultManager] removeItemAtPath:TempRecordDirectory error:nil];
}

- (void)cleanExpiredDirectory {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:TempPath error:nil];
        for (NSString *content in directoryContents) {
            NSArray *contentSection = [content componentsSeparatedByString:@"_"];
            if (contentSection.count == 3
                && [[contentSection firstObject] isEqualToString:TempRecordPre]
                && ![[contentSection lastObject] isEqualToString:_timeline])
            {
                [[NSFileManager defaultManager] removeItemAtPath:TempPathOf(content) error:nil];
            }
        }
    });
}

@end

@implementation FEVideoCaptureView

- (instancetype)initWithFrame:(CGRect)frame delegate:(id<FEVideoCaptureDelegate>)delegate {
    self = [super initWithFrame:frame];
    if (self) {
        _delegate = delegate;
        [self initSelf];
    }
    return self;
}

- (void)initSelf {
#ifndef __IPHONE_8_0
    _library = [ALAssetsLibrary new];
#endif
    _videoQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    _audioQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
    _recordPathAry = [NSMutableArray new];
    
    _focusColor = [UIColor whiteColor];
    _exportPreset = AVAssetExportPresetMediumQuality;
    
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapAction:)]];
    [self createFileDirectory];
    
    if ([self judgeAuthorization]) {
        [self initCaptureSession];
    }
}

- (void)dealloc {
    [self removeFileDirecotry];
    [_videoOutput setSampleBufferDelegate:nil queue:dispatch_get_main_queue()];
    [_audioOutput setSampleBufferDelegate:nil queue:dispatch_get_main_queue()];
}

#pragma mark - Custom
- (BOOL)judgeAuthorization {
    AVAuthorizationStatus videoStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    AVAuthorizationStatus audioStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    
    switch (videoStatus) {
        case AVAuthorizationStatusAuthorized:
            break;
        case AVAuthorizationStatusDenied:
        case AVAuthorizationStatusRestricted:
            PerformProcessError(FEVideoCapture_Process_CameraAuthorize, @"没有相机权限, 不能开启小视频录制功能喔")
            break;
        case AVAuthorizationStatusNotDetermined:
            NSLog(@"若无法弹出相机权限许可对话框, 请检查项目设置");
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
                if (!granted) {
                    PerformProcessError(FEVideoCapture_Process_CameraAuthorize, @"没有相机权限, 不能开启小视频录制功能喔")
                }
                if (granted && status == AVAuthorizationStatusAuthorized) {
                    [self initCaptureSession];
                }
            }];
            break;
    }
    
    switch (audioStatus) {
        case AVAuthorizationStatusAuthorized:
            break;
        case AVAuthorizationStatusDenied:
        case AVAuthorizationStatusRestricted:
            PerformProcessError(FEVideoCapture_Process_MicroPhoneAuthorize, @"没有麦克风权限, 不能开启小视频录制功能喔")
            break;
        case AVAuthorizationStatusNotDetermined:
            NSLog(@"若无法弹出麦克风权限许可对话框, 请检查项目设置");
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
                AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
                if (!granted) {
                    PerformProcessError(FEVideoCapture_Process_MicroPhoneAuthorize, @"没有麦克风权限, 不能开启小视频录制功能喔")
                }
                if (granted && status == AVAuthorizationStatusAuthorized) {
                    [self initCaptureSession];
                }
            }];
            break;
    }
    
    return audioStatus == AVAuthorizationStatusAuthorized && videoStatus == AVAuthorizationStatusAuthorized;
}

- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if (device.position == position) {
            return device;
        }
    }
    return nil;
}

- (AVCaptureVideoOrientation)currentOrientation {
    switch ([UIDevice currentDevice].orientation) {
        case UIDeviceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeRight;
        case UIDeviceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeLeft;
        case UIDeviceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;
        default:
            return AVCaptureVideoOrientationPortrait;
    }
}

- (void)resetOrientation {
    NSArray *connections = [_videoOutput connections];
    for (AVCaptureConnection *connection in connections) {
        connection.videoOrientation = _videoOrientation;
    }
}

- (void)runFocusAnimationAt:(CGPoint)centerPoint {
    [_focusLayer removeFromSuperlayer];
    _focusLayer = [[FEVideoCaptureFocusLayer alloc] initWithCenter:centerPoint
                                                        sideLength:FocusRectSideLength
                                                             color:_focusColor];
    [_focusLayer runAnimation];
    [self.layer addSublayer:_focusLayer];
}

#pragma mark - Action
- (void)tapAction:(UITapGestureRecognizer *)tap {
    CGPoint devicePoint = [tap locationInView:self];
    [self setFocusAt:devicePoint];
}

- (void)setFocusAt:(CGPoint)devicePoint {
    AVCaptureDevice *device = [_videoInput device];
    CGPoint layerPoint = [_previewLayer captureDevicePointOfInterestForPoint:devicePoint];
    
    if ([device isFocusPointOfInterestSupported]
        && [device isFocusModeSupported:AVCaptureFocusModeAutoFocus])
    {
        if ([device lockForConfiguration:nil]) {
            device.focusPointOfInterest = layerPoint;
            device.focusMode = AVCaptureFocusModeAutoFocus;
            [device unlockForConfiguration];
        }
    }
    if ([device isExposurePointOfInterestSupported]
        && [device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
    {
        if ([device lockForConfiguration:nil]) {
            device.exposurePointOfInterest = layerPoint;
            device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
            [device unlockForConfiguration];
        }
    }
    [self runFocusAnimationAt:devicePoint];
}

#pragma mark - Session
- (void)initCaptureSession {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        _session = [AVCaptureSession new];
        _session.sessionPreset = AVCaptureSessionPresetHigh;
        
        _cameraPosition = AVCaptureDevicePositionBack;
        _videoOrientation = AVCaptureVideoOrientationPortrait;
        
        [_session beginConfiguration];
        [self initVideo];
        [self initAudio];
        [_session commitConfiguration];
        
        [self resetOrientation];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_session];
            _previewLayer.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
            _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            [self.layer addSublayer:_previewLayer];
            PerformSessionFinishInit
        });
    });
}

- (void)initVideo {
    NSError *videoInputError;
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    _videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:videoDevice error:&videoInputError];
    if (videoInputError) {
        PerformProcessError(FEVideoCapture_Process_CameraInit, @"摄像头出错!")
        return;
    }
    
    _videoOutput = [AVCaptureVideoDataOutput new];
    _videoOutput.alwaysDiscardsLateVideoFrames = YES;
    [_videoOutput setVideoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey :
                                         @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)}];
    
    if ([_session canAddInput:_videoInput]) {
        [_session addInput:_videoInput];
    }
    if ([_session canAddOutput:_videoOutput]) {
        [_session addOutput:_videoOutput];
    }
}

- (void)initAudio {
    NSError *audioInputError;
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    
    _audioInput = [[AVCaptureDeviceInput alloc] initWithDevice:audioDevice error:&audioInputError];
    if (audioInputError) {
        PerformProcessError(FEVideoCapture_Process_AudioInit, @"音频设备出错!")
        return;
    }
    
    _audioOutput = [AVCaptureAudioDataOutput new];
    
    if ([_session canAddInput:_audioInput]) {
        [_session addInput:_audioInput];
    }
    if ([_session canAddOutput:_audioOutput]) {
        [_session addOutput:_audioOutput];
    }
}

#pragma mark - Writer
- (void)createWriterToPath:(NSString *)path {
    NSError *writerError;
    NSURL *fileUrl = [NSURL fileURLWithPath:path];
    _assetWriter = [[AVAssetWriter alloc] initWithURL:fileUrl fileType:AVFileTypeMPEG4 error:&writerError];
    if (writerError) {
        PerformProcessError(FEVideoCapture_Process_AssetWriter, @"视频写入设备出错!")
        return;
    }
    
    if ([path isEqualToString:_recordPathAry.firstObject]) {
        _videoOrientation = [self currentOrientation];
        [self resetOrientation];
    }
    
    AVCaptureVideoOrientation orientation = _videoOrientation;
    BOOL isPortrait = orientation == AVCaptureVideoOrientationPortrait
    || orientation == AVCaptureVideoOrientationPortraitUpsideDown;
    
    NSInteger videoWidth = (int)ScreenShort % 2 == 0 ? ScreenShort : ScreenShort + 1;
    NSInteger videoHeight = (int)ScreenLong % 2 == 0 ? ScreenLong : ScreenLong + 1;
    
    NSInteger width = isPortrait ? videoWidth : videoHeight;
    NSInteger height = isPortrait ? videoHeight : videoWidth;
    
    _videoWriter = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                                  outputSettings:@{AVVideoCodecKey : AVVideoCodecH264,
                                                                   AVVideoWidthKey : @(width),
                                                                   AVVideoHeightKey : @(height)}];
    _videoWriter.expectsMediaDataInRealTime = YES;
    
    NSDictionary *audioSettings = [_audioOutput recommendedAudioSettingsForAssetWriterWithOutputFileType:AVFileTypeMPEG4];
    _audioWriter = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio
                                                  outputSettings:audioSettings];
    _audioWriter.expectsMediaDataInRealTime = YES;
    
    if ([_assetWriter canAddInput:_videoWriter]) {
        [_assetWriter addInput:_videoWriter];
    }
    if ([_assetWriter canAddInput:_audioWriter]) {
        [_assetWriter addInput:_audioWriter];
    }
    
    [_videoOutput setSampleBufferDelegate:self queue:_videoQueue];
    [_audioOutput setSampleBufferDelegate:self queue:_audioQueue];
    _writing = YES;
}

- (void)endWriting {
    if (!_assetWriter) {
        return;
    }
    _writing = NO;
    [_videoOutput setSampleBufferDelegate:nil queue:dispatch_get_main_queue()];
    [_audioOutput setSampleBufferDelegate:nil queue:dispatch_get_main_queue()];
    
    [_videoWriter markAsFinished];
    [_audioWriter markAsFinished];
    [_assetWriter finishWritingWithCompletionHandler:^{
        _assetWriter = nil;
        _audioCanAppend = NO;
    }];
}

#pragma mark - Merge
- (void)combineAllVideoFragment:(void (^)())complete {
    
    if (_recordPathAry.count <= 0) {
        PerformProcessError(FEVideoCapture_Process_ReadFragment, @"请先录制视频~")
        SafetyCallblock(complete)
        return;
    }
    
    AVMutableComposition *mixComposition = [AVMutableComposition new];
    AVMutableCompositionTrack *videoTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *audioTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    
    CMTime videoTotalDuration = kCMTimeZero;
    CMTime audioTotalDuration = kCMTimeZero;
    UIImage *thumbnail = nil;
    
    for (NSString *videoPath in _recordPathAry) {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:videoPath]
                                                options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @(YES)}];
        NSError *videoError, *audioError;
        AVAssetTrack *assetVideoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
        AVAssetTrack *assetAudioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
        
        CMTime videoStartTime = CMTimeMake(0, assetVideoTrack.timeRange.duration.timescale);
        CMTime audioStartTime = CMTimeMake(0, assetAudioTrack.timeRange.duration.timescale);
        CMTimeRange videoRange = CMTimeRangeMake(videoStartTime, assetVideoTrack.timeRange.duration);
        CMTimeRange audioRange = CMTimeRangeMake(audioStartTime, assetAudioTrack.timeRange.duration);
        
        [videoTrack insertTimeRange:videoRange ofTrack:assetVideoTrack atTime:videoTotalDuration error:&videoError];
        [audioTrack insertTimeRange:audioRange ofTrack:assetAudioTrack atTime:audioTotalDuration error:&audioError];
        
        if (videoError || audioError) {
            PerformProcessError(FEVideoCapture_Process_ReadFragment, @"视频片段读取出错!")
            SafetyCallblock(complete)
            return;
        }
        if ([videoPath isEqualToString:_recordPathAry.firstObject]) {
            thumbnail = [asset getThumbnail];
        }
        
        videoTotalDuration = CMTimeAdd(videoTotalDuration, videoRange.duration);
        audioTotalDuration = CMTimeAdd(audioTotalDuration, audioRange.duration);
    }
    
    FEVideoCaptureInfo *videoData = [FEVideoCaptureInfo new];
    videoData.thumbnail = thumbnail;
    videoData.videoDuration = videoTotalDuration.value / videoTotalDuration.timescale;
    videoData.videoUrl = [NSURL fileURLWithPath:TemRecordMergePath];
    
    AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:mixComposition
                                                                    presetName:_exportPreset];
    
    export.outputURL = [NSURL fileURLWithPath:TemRecordMergePath];
    export.outputFileType = AVFileTypeMPEG4;
    export.shouldOptimizeForNetworkUse = YES;
    [export exportAsynchronouslyWithCompletionHandler:^{
        switch (export.status) {
            case AVAssetExportSessionStatusCompleted: {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self saveToPhoto];
                    PerformCombineResult(videoData)
                    SafetyCallblock(complete)
                });
                break;
            }
            default: {
                dispatch_async(dispatch_get_main_queue(), ^{
                    PerformProcessError(FEVideoCapture_Process_CombineFragment, @"视频片段合成出错!")
                    SafetyCallblock(complete)
                });
                break;
            }
        }
    }];
}

- (void)saveToPhoto {
#ifdef __IPHONE_8_0
    switch ([PHPhotoLibrary authorizationStatus]) {
        case PHAuthorizationStatusNotDetermined: {
            NSLog(@"若无法弹出相册权限许可对话框, 请检查项目设置");
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                if (status == PHAuthorizationStatusAuthorized) {
                    [self saveToPhoto];
                } else {
                    PerformProcessError(FEVideoCapture_Process_PhotoAuthorize, @"没有相册权限, 不能把视频写入相册")
                }
            }];
            return;
        }
        case PHAuthorizationStatusRestricted:
        case PHAuthorizationStatusDenied:
            PerformProcessError(FEVideoCapture_Process_PhotoAuthorize, @"没有相册权限, 不能把视频写入相册")
            return;
        default:
            break;
    }
    
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:TemRecordMergePath]];
    } completionHandler:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                PerformProcessError(FEVideoCapture_Process_SaveToPhoto,
                                    [error localizedDescription])
            }
            PerformSaveToPhotoResult(@(error == nil))
        });
    }];
    
#else
    switch ([ALAssetsLibrary authorizationStatus]) {
        case ALAuthorizationStatusNotDetermined:
             NSLog(@"若无法弹出相册权限许可对话框, 请检查项目设置");
        case ALAuthorizationStatusRestricted:
        case ALAuthorizationStatusDenied:
            PerformProcessError(FEVideoCapture_Process_PhotoAuthorize, @"没有相册权限, 不能把视频写入相册")
            return;
        case ALAuthorizationStatusAuthorized:
            break;
    }
    
    [_library writeVideoAtPathToSavedPhotosAlbum:[NSURL fileURLWithPath:TemRecordMergePath] completionBlock:
     ^(NSURL *url, NSError *error)
     {
         dispatch_async(dispatch_get_main_queue(), ^{
             if (error) {
                 PerformProcessError(FEVideoCapture_Process_SaveToPhoto,
                                     [error localizedDescription])
             }
             PerformSaveToPhotoResult(@(error == nil))
         });
     }];
#endif
}

#pragma mark - AVCaptureAudioDataOutputSampleBufferDelegate & AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    @synchronized(self) {
        
        if (!(_writing && !_changingCamera
              && (_assetWriter.status == AVAssetWriterStatusWriting
                  || _assetWriter.status == AVAssetWriterStatusUnknown))) {
                  return;
              }
        
        if (!_audioCanAppend && captureOutput == _audioOutput) {
            return;
        }
        
        if (_assetWriter.status == AVAssetWriterStatusUnknown) {
            [_assetWriter startWriting];
            [_assetWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
        }
        
        if (captureOutput == _videoOutput) {
            if ([_videoWriter isReadyForMoreMediaData] && _writing) {
                [_videoWriter appendSampleBuffer:sampleBuffer];
                _audioCanAppend = YES;
            }
        } else {
            if ([_audioWriter isReadyForMoreMediaData] && _writing) {
                [_audioWriter appendSampleBuffer:sampleBuffer];
            }
        }
    }
}

#pragma mark - Public Method
- (void)startRuning {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (_session && !_session.isRunning) {
            [_session startRunning];
            dispatch_async(dispatch_get_main_queue(), ^{
                _previewLayer.hidden = NO;
                [self setFocusAt:self.layer.position];
            });
        }
    });
}

- (void)stopRuning {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (_session && _session.isRunning) {
            [_session stopRunning];
            dispatch_async(dispatch_get_main_queue(), ^{
                _previewLayer.hidden = YES;
            });
        }
    });
}

- (void)changeCamera:(void (^)())complete {
    
    _cameraPosition = _cameraPosition == AVCaptureDevicePositionBack
    ? AVCaptureDevicePositionFront
    : AVCaptureDevicePositionBack;
    
    AVCaptureDevice *device = [self cameraWithPosition:_cameraPosition];
    if (!device) {
        PerformProcessError(FEVideoCapture_Process_ChangeCamera, @"无法切换摄像头")
        SafetyCallblock(complete)
        return;
    }
    
    _changingCamera = YES;
    _previewLayer.hidden = YES;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        [_session beginConfiguration];
        [_session removeInput:_videoInput];
        _videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:device error:nil];
        [_session addInput:_videoInput];
        [_session commitConfiguration];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self resetOrientation];
            [self setFocusAt:self.layer.position];
            
            _changingCamera = NO;
            _previewLayer.hidden = NO;
            SafetyCallblock(complete)
        });
        
    });
}

- (void)startRecord {
    NSString *tempRecordPath = TempRecordPath(_recordPathAry.count);
    [_recordPathAry addObject:tempRecordPath];
    [self createWriterToPath:tempRecordPath];
}

- (void)stopRecord {
    [self endWriting];
}

- (void)loadVideoFragment:(NSString *)videoPath {
    [_recordPathAry insertObject:videoPath atIndex:0];
}

- (void)deleteLastFragment {
    if (_recordPathAry.count <= 0) {
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:[_recordPathAry lastObject] error:nil];
    [_recordPathAry removeLastObject];
}

@end


