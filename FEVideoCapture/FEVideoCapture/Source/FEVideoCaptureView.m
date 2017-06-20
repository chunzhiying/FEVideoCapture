//
//  FEVideoCaptureView.m
//  yyfe
//
//  Created by 陈智颖 on 2017/4/19.
//  Copyright © 2017年 yy.com. All rights reserved.
//

#import "FEVideoCaptureView.h"
#import "FEVideoCaptureFocusLayer.h"
#import "ATMotionManager.h"
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

#define TempBeginPath \
[NSString stringWithFormat:@"%@/record_begin.mp4", TempRecordDirectory]

#define TempRecordPath(atNum) \
[NSString stringWithFormat:@"%@/record_%lu.mp4", TempRecordDirectory, (unsigned long)atNum]

#define TemRecordMergePath \
[NSString stringWithFormat:@"%@/record_merge.mp4", TempRecordDirectory]


#define SafetyCallblock(block, ...) if((block)) { block(__VA_ARGS__); }

#define Delay(sec, block) \
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sec * NSEC_PER_SEC)), dispatch_get_main_queue(), block);

#define ScreenShort MIN([UIScreen mainScreen].bounds.size.height, [UIScreen mainScreen].bounds.size.width)
#define ScreenLong  MAX([UIScreen mainScreen].bounds.size.height, [UIScreen mainScreen].bounds.size.width)
#define SystemAdvanceThan8 ([[UIDevice currentDevice].systemVersion floatValue] >= 8.0)


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

#define PerformRecordFinishInit \
if (self.delegate && [self.delegate respondsToSelector:@selector(recordFinishInitForVideoCaptureView:)]) { \
    [self.delegate performSelector:@selector(recordFinishInitForVideoCaptureView:) withObject:self]; \
}

@implementation FEVideoWaterMark

@end

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
    BOOL _readyToRun;
    BOOL _writing;
    BOOL _audioCanAppend;
    BOOL _changingCamera;
    
    CGSize _videoSize;
    NSTimer *_recordInitTimer;
    
    NSString *_timeline;
    AVCaptureDevicePosition _cameraPosition;
    NSMutableArray<NSString *> *_recordPathAry;
    
    FEVideoCaptureFocusLayer *_focusLayer;
    
    dispatch_queue_t _videoQueue;
    dispatch_queue_t _audioQueue;
}

@property (nonatomic, strong) ALAssetsLibrary *library;

@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDeviceInput *videoInput;
@property (nonatomic, strong) AVCaptureDeviceInput *audioInput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

@property (nonatomic, strong) AVAssetWriter *assetWriter;
@property (nonatomic, strong) AVAssetWriterInput *videoWriter;
@property (nonatomic, strong) AVAssetWriterInput *audioWriter;

@property (nonatomic) AVCaptureVideoOrientation videoOrientation;

@end


@implementation FEVideoCaptureView (File)

#pragma mark - File
- (void)createFileDirectory {
    [self removeFileDirecotry];
    _timeline = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
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
    _library = [ALAssetsLibrary new];

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
    [self invalidateTimer];
    [_session removeInput:_audioInput];
    [_session removeInput:_videoInput];
    [_session removeOutput:_audioOutput];
    [_session removeOutput:_videoOutput];
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
                dispatch_async(dispatch_get_main_queue(), ^{
                    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
                    if (!granted) {
                        PerformProcessError(FEVideoCapture_Process_CameraAuthorize,
                                            @"没有相机权限, 不能开启小视频录制功能喔")
                    }
                    if (granted && status == AVAuthorizationStatusAuthorized) {
                        [self initCaptureSession];
                    }
                });
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
                dispatch_async(dispatch_get_main_queue(), ^{
                    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
                    if (!granted && status == AVAuthorizationStatusAuthorized) {
                        PerformProcessError(FEVideoCapture_Process_MicroPhoneAuthorize,
                                            @"没有麦克风权限, 不能开启小视频录制功能喔")
                    }
                    if (granted && status == AVAuthorizationStatusAuthorized) {
                        [self initCaptureSession];
                    }
                });
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
    switch ([ATMotionManager orientation]) {
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
        connection.videoOrientation = self.videoOrientation;
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

#pragma mark - Setter
- (void)setVideoOrientation:(AVCaptureVideoOrientation)videoOrientation {
    _videoOrientation = videoOrientation;
    
    BOOL isPortrait = videoOrientation == AVCaptureVideoOrientationPortrait
                    || videoOrientation == AVCaptureVideoOrientationPortraitUpsideDown;
    
    int videoWidth = ScreenShort;
    int videoHeight = ScreenLong;
    
    videoWidth = videoWidth % 2 == 0 ? videoWidth : videoWidth + 1;
    videoHeight = videoHeight % 2 == 0 ? videoHeight : videoHeight + 1;
    
    NSInteger width = isPortrait ? videoWidth : videoHeight;
    NSInteger height = isPortrait ? videoHeight : videoWidth;

    _videoSize = CGSizeMake(width, height);
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
    _readyToRun = NO;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        _session = [AVCaptureSession new];
        _session.sessionPreset = AVCaptureSessionPresetHigh;
        
        _cameraPosition = AVCaptureDevicePositionBack;
        self.videoOrientation = AVCaptureVideoOrientationPortrait;
        
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
            
            _readyToRun = YES;
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
    
    if (_recordPathAry.count > 0 && [path isEqualToString:_recordPathAry.firstObject]) {
        self.videoOrientation = [self currentOrientation];
        [self resetOrientation];
        Delay(0.2, ^{
            [self startWriting];
        });
    } else {
        [self startWriting];
    }
}

- (void)startWriting {
    
    _videoWriter = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                                  outputSettings:@{AVVideoCodecKey : AVVideoCodecH264,
                                                                   AVVideoWidthKey : @(_videoSize.width),
                                                                   AVVideoHeightKey : @(_videoSize.height)}];
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

- (void)endWriting:(CompleteBlock)block {
    _writing = NO;
    [_videoOutput setSampleBufferDelegate:nil queue:dispatch_get_main_queue()];
    [_audioOutput setSampleBufferDelegate:nil queue:dispatch_get_main_queue()];
    
    if (!_assetWriter || _assetWriter.status != AVAssetWriterStatusWriting) {
        _assetWriter = nil;
        _audioCanAppend = NO;
        SafetyCallblock(block)
        return;
    }
    
    [_videoWriter markAsFinished];
    [_audioWriter markAsFinished];
    [_assetWriter finishWritingWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            _assetWriter = nil;
            _audioCanAppend = NO;
            SafetyCallblock(block)
        });
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
    AVAssetTrack *assetVideoTrack = nil;
    AVAssetTrack *assetAudioTrack = nil;
    UIImage *thumbnail = nil;
    
    for (NSString *videoPath in _recordPathAry) {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:videoPath]
                                                options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @(YES)}];
        NSError *videoError, *audioError;
        assetVideoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
        assetAudioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
        
        CMTime videoStartTime = CMTimeMake(0, assetVideoTrack.timeRange.duration.timescale);
        CMTime audioStartTime = CMTimeMake(0, assetAudioTrack.timeRange.duration.timescale);
        CMTimeRange videoRange = CMTimeRangeMake(videoStartTime, assetVideoTrack.timeRange.duration);
        CMTimeRange audioRange = CMTimeRangeMake(audioStartTime, assetAudioTrack.timeRange.duration);
        
        [videoTrack insertTimeRange:videoRange ofTrack:assetVideoTrack atTime:videoTotalDuration error:&videoError];
        [audioTrack insertTimeRange:audioRange ofTrack:assetAudioTrack atTime:audioTotalDuration error:&audioError];
        
        if (audioError) {
            PerformProcessError(FEVideoCapture_Process_ReadFragment, @"音轨读取出错!")
            SafetyCallblock(complete)
            return;
        }
        if (videoError) {
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
    
    
    BOOL isVideoFromPhoto = _recordPathAry.count == 1 && ![_recordPathAry.firstObject hasPrefix:TempRecordDirectory];
    CGSize renderSize = mixComposition.naturalSize;
    if (isVideoFromPhoto && [self isVideoAssetPortrait:assetVideoTrack]) {
        renderSize = CGSizeMake(mixComposition.naturalSize.height, mixComposition.naturalSize.width);
    }
    
    AVMutableVideoCompositionLayerInstruction *videolayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
    [videolayerInstruction setTransform:assetVideoTrack.preferredTransform atTime:kCMTimeZero];
    [videolayerInstruction setOpacity:0.0 atTime:videoTotalDuration];
    
    AVMutableVideoCompositionInstruction *mainInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    mainInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, videoTotalDuration);
    mainInstruction.layerInstructions = @[videolayerInstruction];
    
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
    videoComposition.renderSize = renderSize;
    videoComposition.frameDuration = CMTimeMake(1, 30);
    videoComposition.instructions = @[mainInstruction];
    [self applyVideoEffectsToComposition:videoComposition naturalSize:mixComposition.naturalSize];
    
    
    FEVideoCaptureInfo *videoData = [FEVideoCaptureInfo new];
    videoData.thumbnail = thumbnail;
    videoData.videoDuration = videoTotalDuration.value / videoTotalDuration.timescale;
    videoData.videoPath = TemRecordMergePath;
    videoData.videoSize = renderSize;
    
    
    NSArray *comptiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:mixComposition];
    
    if (![comptiblePresets containsObject:_exportPreset]) {
        _exportPreset = AVAssetExportPresetMediumQuality;
    }
    
    AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:mixComposition
                                                                    presetName:_exportPreset];
    export.outputURL = [NSURL fileURLWithPath:TemRecordMergePath];
    export.outputFileType = AVFileTypeMPEG4;
    export.shouldOptimizeForNetworkUse = YES;
    export.videoComposition = videoComposition;
    export.timeRange = CMTimeRangeMake(kCMTimeZero, videoTotalDuration);
    
    [export exportAsynchronouslyWithCompletionHandler:^{
         dispatch_async(dispatch_get_main_queue(), ^{
             switch (export.status) {
                 case AVAssetExportSessionStatusCompleted:
                 {
                     if ([_recordPathAry.firstObject hasPrefix:TempRecordDirectory] && _shouldSaveToPhoto) {
                         [self saveToPhoto];
                     }
                     videoData.fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:TemRecordMergePath error:nil] fileSize] / (1024.0 * 1024.0);
                     
                     SafetyCallblock(complete)
                     PerformCombineResult(videoData)
                     break;
                 }
                 case AVAssetExportSessionStatusFailed:
                 case AVAssetExportSessionStatusUnknown:
                 case AVAssetExportSessionStatusWaiting:
                 case AVAssetExportSessionStatusCancelled:
                 case AVAssetExportSessionStatusExporting:
                 {
                     NSString *errorReason = export.error.localizedFailureReason;
                     if (errorReason.length > 0) {
                         PerformProcessError(FEVideoCapture_Process_CombineFragment, errorReason)
                     } else {
                         PerformProcessError(FEVideoCapture_Process_CombineFragment, @"视频片段合成出错!")
                     }
                     SafetyCallblock(complete)
                     break;
                 }
             }
         });
    }];
}

- (BOOL)isVideoAssetPortrait:(AVAssetTrack *)videoAsset {
    BOOL  isVideoAssetPortrait_  = NO;
    CGAffineTransform videoTransform = videoAsset.preferredTransform;
    
    if (videoTransform.a == 0 && videoTransform.b == 1.0 && videoTransform.c == -1.0 && videoTransform.d == 0)
    {isVideoAssetPortrait_ = YES;}
    if (videoTransform.a == 0 && videoTransform.b == -1.0 && videoTransform.c == 1.0 && videoTransform.d == 0)
    {isVideoAssetPortrait_ = YES;}
    if (videoTransform.a == 1.0 && videoTransform.b == 0 && videoTransform.c == 0 && videoTransform.d == 1.0)
    {isVideoAssetPortrait_ = NO;}
    if (videoTransform.a == -1.0 && videoTransform.b == 0 && videoTransform.c == 0 && videoTransform.d == -1.0)
    {isVideoAssetPortrait_ = NO;}
    
    return isVideoAssetPortrait_;
}

- (void)applyVideoEffectsToComposition:(AVMutableVideoComposition *)videoComposition naturalSize:(CGSize)naturalSize {
    
    if (!_waterMark) {
        return;
    }
    
    CGPoint beginPosition;
    switch (_waterMark.position) {
        case UIRectCornerBottomLeft:
        case UIRectCornerAllCorners:
            beginPosition = CGPointMake(_waterMark.padding.x, _waterMark.padding.y);
            break;
        case UIRectCornerBottomRight:
            beginPosition = CGPointMake(naturalSize.width - _waterMark.size.width - _waterMark.padding.x,
                                        _waterMark.padding.y);
            break;
        case UIRectCornerTopLeft:
            beginPosition = CGPointMake(_waterMark.padding.x,
                                        naturalSize.height - _waterMark.size.height - _waterMark.padding.y);
            break;
        case UIRectCornerTopRight:
            beginPosition = CGPointMake(naturalSize.width - _waterMark.size.width - _waterMark.padding.x,
                                        naturalSize.height - _waterMark.size.height - _waterMark.padding.y);
            break;
    }
    
    CALayer *parentLayer = [CALayer layer];
    CALayer *videoLayer = [CALayer layer];
    CALayer *waterMarkLayer = [CALayer layer];
    
    parentLayer.frame = CGRectMake(0, 0,  naturalSize.width, naturalSize.height);
    videoLayer.frame = parentLayer.frame;
    
    waterMarkLayer.frame = CGRectMake(beginPosition.x, beginPosition.y,
                                      _waterMark.size.width, _waterMark.size.height);
    waterMarkLayer.contents = (__bridge id _Nullable)(_waterMark.image.CGImage);
    
    [parentLayer addSublayer:videoLayer];
    [parentLayer addSublayer:waterMarkLayer];
    
    videoComposition.animationTool = [AVVideoCompositionCoreAnimationTool videoCompositionCoreAnimationToolWithPostProcessingAsVideoLayer:videoLayer inLayer:parentLayer];
}

- (void)saveToPhoto {
    
    if (SystemAdvanceThan8) {
        
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
                                        ([NSString stringWithFormat:@"存入相册出错, %@", [error localizedDescription]]))
                }
                PerformSaveToPhotoResult(@(error == nil))
            });
        }];
        
    } else {
        
        switch ([ALAssetsLibrary authorizationStatus]) {
            case ALAuthorizationStatusNotDetermined:
                NSLog(@"若无法弹出相册权限许可对话框, 请检查项目设置");
                break;
            case ALAuthorizationStatusRestricted:
            case ALAuthorizationStatusDenied:
                PerformProcessError(FEVideoCapture_Process_PhotoAuthorize, @"没有相册权限, 不能把视频写入相册")
                break;
            case ALAuthorizationStatusAuthorized:
                break;
        }
        
        [_library writeVideoAtPathToSavedPhotosAlbum:[NSURL fileURLWithPath:TemRecordMergePath] completionBlock:
         ^(NSURL *url, NSError *error)
         {
             dispatch_async(dispatch_get_main_queue(), ^{
                 if (error) {
                     PerformProcessError(FEVideoCapture_Process_SaveToPhoto,
                                         ([NSString stringWithFormat:@"存入相册出错, %@", [error localizedDescription]]))
                 }
                 PerformSaveToPhotoResult(@(error == nil))
             });
         }];
    }
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

#pragma mark - Record Init
- (void)initRecord {
    if ([[NSFileManager defaultManager] fileExistsAtPath:TempBeginPath]) {
        return;
    }
    [self createWriterToPath:TempBeginPath];
    _recordInitTimer = [NSTimer scheduledTimerWithTimeInterval:[FEVideoCaptureFocusLayer animationDuration] target:self selector:@selector(finishInitRecord) userInfo:nil repeats:NO];
}

- (void)finishInitRecord {
    [self endWriting:^{
        PerformRecordFinishInit
    }];
}

- (void)invalidateTimer {
    if (_recordInitTimer) {
        [_recordInitTimer invalidate];
        _recordInitTimer = nil;
    }
}

#pragma mark - Public Method
- (void)startRuning {
    if (!_readyToRun) {
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (_session && !_session.isRunning) {
            [_session startRunning];
            dispatch_async(dispatch_get_main_queue(), ^{
                _previewLayer.hidden = NO;
                [self setFocusAt:self.layer.position];
                [self initRecord];
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
    [self invalidateTimer];
    NSString *tempRecordPath = TempRecordPath(_recordPathAry.count);
    [_recordPathAry addObject:tempRecordPath];
    [self createWriterToPath:tempRecordPath];
}

- (void)stopRecord {
    [self endWriting:nil];
}

- (void)loadVideoFragment:(NSString *)videoPath completion:(void(^)())complete{
    [_recordPathAry insertObject:videoPath atIndex:0];
    [self combineAllVideoFragment:^{
        [_recordPathAry removeAllObjects];
        SafetyCallblock(complete)
    }];
}

- (void)deleteLastFragment {
    if (_recordPathAry.count <= 0) {
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:[_recordPathAry lastObject] error:nil];
    [_recordPathAry removeLastObject];
}

@end


