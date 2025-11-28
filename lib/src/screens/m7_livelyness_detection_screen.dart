import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:m7_livelyness_detection/index.dart';
import 'package:camera/camera.dart';

List<CameraDescription> availableCams = [];

class M7LivelynessDetectionScreenV1 extends StatefulWidget {
  final PreferredSizeWidget appBar;
  final M7DetectionConfig config;
  final Color primaryColor;
  final Color scaffoldColor;
  final Color backgroundColor;
  final Widget circleIndicator;
  final Widget description;
  final TextStyle styleAnimatedContainer;

  const M7LivelynessDetectionScreenV1({
    required this.config,
    required this.appBar,
    required this.primaryColor,
    required this.scaffoldColor,
    required this.backgroundColor,
    required this.circleIndicator,
    required this.description,
    required this.styleAnimatedContainer,
    super.key,
  });

  @override
  State<M7LivelynessDetectionScreenV1> createState() => _MLivelyness7DetectionScreenState();
}

class _MLivelyness7DetectionScreenState extends State<M7LivelynessDetectionScreenV1> {
  //* MARK: - Private Variables
  //? =========================================================
  late final List<M7LivelynessStepItem> steps;
  CameraController? _cameraController;
  int _cameraIndex = 0;
  bool _isBusy = false;
  final GlobalKey<M7LivelynessDetectionStepOverlayState> _stepsKey = GlobalKey<M7LivelynessDetectionStepOverlayState>();
  bool _isProcessingStep = false;
  bool _didCloseEyes = false;
  bool _isTakingPicture = false;
  Timer? _timerToDetectFace;

  late final List<M7LivelynessStepItem> _steps;

  //* MARK: - Life Cycle Methods
  //? =========================================================
  @override
  void initState() {
    _preInitCallBack();
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _postFrameCallBack(),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _timerToDetectFace?.cancel();
    _timerToDetectFace = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.appBar,
      backgroundColor: widget.scaffoldColor,
      body: _buildBody(),
    );
  }

  //* MARK: - Private Methods for Business Logic
  //? =========================================================
  void _preInitCallBack() {
    _steps = widget.config.steps;
  }

  void _postFrameCallBack() async {
    availableCams = await availableCameras();
    if (availableCams.any(
      (element) => element.lensDirection == CameraLensDirection.front && element.sensorOrientation == 90,
    )) {
      _cameraIndex = availableCams.indexOf(
        availableCams.firstWhere(
            (element) => element.lensDirection == CameraLensDirection.front && element.sensorOrientation == 90),
      );
    } else {
      _cameraIndex = availableCams.indexOf(
        availableCams.firstWhere(
          (element) => element.lensDirection == CameraLensDirection.front,
        ),
      );
    }
    if (!widget.config.startWithInfoScreen) {
      _startLiveFeed();
    }
  }

  void _startTimer() {
    _timerToDetectFace = Timer(
      Duration(seconds: widget.config.maxSecToDetect),
      () {
        _timerToDetectFace?.cancel();
        _timerToDetectFace = null;
        if (widget.config.allowAfterMaxSec) {
          setState(() {});
          return;
        }
        _onDetectionCompleted(
          imgToReturn: null,
        );
      },
    );
  }

  void _startLiveFeed() async {
    final camera = availableCams[_cameraIndex];
    _cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _cameraController?.initialize().then((_) {
      if (!mounted) {
        return;
      }
      _startTimer();
      _cameraController?.startImageStream(_processCameraImage);
      setState(() {});
    });
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in cameraImage.planes) {
      allBytes.putUint8List(plane.bytes);
    }

    final Size imageSize = Size(
      cameraImage.width.toDouble(),
      cameraImage.height.toDouble(),
    );

    final camera = availableCams[_cameraIndex];
    final imageRotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );
    if (imageRotation == null) return;

    final inputImageFormat = InputImageFormatValue.fromRawValue(
      cameraImage.format.raw,
    );
    if (inputImageFormat == null) return;

    if (Platform.isIOS && (inputImageFormat != InputImageFormat.bgra8888)) return;

    Uint8List bytes = (Platform.isAndroid && inputImageFormat != InputImageFormat.nv21)
        ? _convertYUV420ToNV21(cameraImage)
        : _convertBGRA8888(cameraImage);

    final planeData = cameraImage.planes.map(
      (Plane plane) {
        return InputImageMetadata(
          bytesPerRow: plane.bytesPerRow,
          size: Size(plane.width?.toDouble() ?? 100, plane.height?.toDouble() ?? 100),
          format: inputImageFormat!,
          rotation: imageRotation,
        );
      },
    ).toList();

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: Platform.isIOS ? InputImageFormat.bgra8888 : InputImageFormat.nv21,
        bytesPerRow: planeData.last.bytesPerRow,
      ),
    );

    _processImage(inputImage);
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (_isBusy) {
      return;
    }
    _isBusy = true;
    final faces = await M7MLHelper.instance.processInputImage(inputImage);

    if (inputImage.metadata?.size != null && inputImage.metadata?.rotation != null) {
      if (faces.isEmpty) {
        _resetSteps();
      } else {
        if (_isProcessingStep && _steps[_stepsKey.currentState?.currentIndex ?? 0].step == M7LivelynessStep.blink) {
          if (_didCloseEyes) {
            if ((faces.first.leftEyeOpenProbability ?? 1.0) < 0.75 &&
                (faces.first.rightEyeOpenProbability ?? 1.0) < 0.75) {
              await _completeStep(
                step: _steps[_stepsKey.currentState?.currentIndex ?? 0].step,
              );
            }
          }
        }
        _detect(
          face: faces.first,
          step: _steps[_stepsKey.currentState?.currentIndex ?? 0].step,
        );
      }
    } else {
      _resetSteps();
    }
    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _completeStep({
    required M7LivelynessStep step,
  }) async {
    final int indexToUpdate = _steps.indexWhere(
      (p0) => p0.step == step,
    );

    _steps[indexToUpdate] = _steps[indexToUpdate].copyWith(
      isCompleted: true,
    );
    if (mounted) {
      setState(() {});
    }
    await _stepsKey.currentState?.nextPage();
    _stopProcessing();
  }

  void _takePicture({
    required bool didCaptureAutomatically,
  }) async {
    try {
      if (_cameraController == null) return;
      if (_isTakingPicture) {
        return;
      }
      setState(
        () => _isTakingPicture = true,
      );
      await _cameraController?.stopImageStream();

      final XFile? clickedImage = await _cameraController?.takePicture();
      if (clickedImage == null) {
        _startLiveFeed();
        return;
      }
      _processCapturedImage(clickedImage, didCaptureAutomatically);
    } catch (e) {
      _startLiveFeed();
      print("Error capturing image: $e");
    }
  }

  Future<void> _processCapturedImage(XFile clickedImage, bool didCaptureAutomatically) async {
    final String imgPath = clickedImage.path;
    final inputImage = InputImage.fromFilePath(imgPath);

    // Process the captured image with ML Kit Face Detector
    final faces = await M7MLHelper.instance.processInputImage(inputImage);

    if (faces.isNotEmpty) {
      final face = faces.first;

      // Smile detection logic
      final smileProbability = face.smilingProbability ?? 0;
      if (smileProbability > 0.75) {
        _completeStep(step: M7LivelynessStep.smile);
      }
    }

    _onDetectionCompleted(
      imgToReturn: clickedImage,
      didCaptureAutomatically: didCaptureAutomatically,
    );
  }

  void _onDetectionCompleted({
    XFile? imgToReturn,
    bool? didCaptureAutomatically,
  }) {
    final String imgPath = imgToReturn?.path ?? "";
    if (imgPath.isEmpty || didCaptureAutomatically == null) {
      Navigator.of(context).pop(null);
      return;
    }
    Navigator.of(context).pop(
      M7CapturedImage(
        imgPath: imgPath,
        didCaptureAutomatically: didCaptureAutomatically,
      ),
    );
  }

  void _resetSteps() async {
    for (var p0 in _steps) {
      final int index = _steps.indexWhere(
        (p1) => p1.step == p0.step,
      );
      _steps[index] = _steps[index].copyWith(
        isCompleted: false,
      );
    }
    _didCloseEyes = false;
    if (_stepsKey.currentState?.currentIndex != 0) {
      _stepsKey.currentState?.reset();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _startProcessing() {
    if (!mounted) {
      return;
    }
    setState(
      () => _isProcessingStep = true,
    );
  }

  void _stopProcessing() {
    if (!mounted) {
      return;
    }
    setState(
      () => _isProcessingStep = false,
    );
  }

  void _detect({
    required Face face,
    required M7LivelynessStep step,
  }) async {
    if (_isProcessingStep) {
      return;
    }
    switch (step) {
      case M7LivelynessStep.blink:
        final M7BlinkDetectionThreshold? blinkThreshold =
            M7LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is M7BlinkDetectionThreshold,
        ) as M7BlinkDetectionThreshold?;
        if ((face.leftEyeOpenProbability ?? 1.0) < (blinkThreshold?.leftEyeProbability ?? 0.25) &&
            (face.rightEyeOpenProbability ?? 1.0) < (blinkThreshold?.rightEyeProbability ?? 0.25)) {
          _startProcessing();
          if (mounted) {
            setState(
              () => _didCloseEyes = true,
            );
          }
        }
        break;
      case M7LivelynessStep.turnLeft:
        final M7HeadTurnDetectionThreshold? headTurnThreshold =
            M7LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is M7HeadTurnDetectionThreshold,
        ) as M7HeadTurnDetectionThreshold?;
        if ((face.headEulerAngleY ?? 0) > (headTurnThreshold?.rotationAngle ?? 45)) {
          _startProcessing();
          await _completeStep(step: step);
        }
        break;
      case M7LivelynessStep.turnRight:
        final M7HeadTurnDetectionThreshold? headTurnThreshold =
            M7LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is M7HeadTurnDetectionThreshold,
        ) as M7HeadTurnDetectionThreshold?;
        if ((face.headEulerAngleY ?? 0) > (headTurnThreshold?.rotationAngle ?? -50)) {
          _startProcessing();
          await _completeStep(step: step);
        }
        break;
      case M7LivelynessStep.smile:
        final M7SmileDetectionThreshold? smileThreshold =
            M7LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is M7SmileDetectionThreshold,
        ) as M7SmileDetectionThreshold?;
        if ((face.smilingProbability ?? 0) > (smileThreshold?.probability ?? 0.75)) {
          _startProcessing();
          await _completeStep(step: step);
        }
        break;
      default:
        break;
    }
  }

  Uint8List _convertBGRA8888(CameraImage image) {
    final plane = image.planes[0];
    return plane.bytes;
  }

  /// Convert YUV_420_888 format to NV21
  Uint8List _convertYUV420ToNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = (width ~/ 2) * (height ~/ 2) * 2;

    Uint8List nv21 = Uint8List(ySize + uvSize);
    int uvIndex = ySize;

    // Copy Y plane
    nv21.setRange(0, ySize, image.planes[0].bytes);

    // Interleave U and V planes
    final Uint8List uPlane = image.planes[1].bytes;
    final Uint8List vPlane = image.planes[2].bytes;

    for (int i = 0; i < uvSize ~/ 2; i++) {
      nv21[uvIndex++] = uPlane[i]; // U
      nv21[uvIndex++] = vPlane[i]; // V
    }

    return nv21;
  }

  //* MARK: - Private Methods for UI Components
  //? =========================================================
  Widget _buildBody() {
    return Stack(
      children: [
        Column(children: [_buildDetectionBody()])
      ],
    );
  }

  Widget _buildDetectionBody() {
    if (_cameraController == null || _cameraController?.value.isInitialized == false) {
      return Expanded(child: widget.circleIndicator);
    }
    final Widget cameraView = Transform.rotate(
      angle: -90 * 3.14159 / 180, // Rotate camera view -90 degrees
      child: CameraPreview(_cameraController!),
    );

    // Calculate adaptive oval size based on available space
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final isLandscape = screenWidth > screenHeight;

    // Use the smaller dimension to ensure the oval fits properly
    // For landscape (iPad horizontal), use height-based calculation
    // For portrait, use width-based calculation
    final double ovalSize = isLandscape
        ? (screenHeight - 150).clamp(200.0, 500.0) // 150 for margins and description
        : (screenWidth - 200).clamp(200.0, 500.0);

    return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          //color: widget.backgroundColor,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 500,
              padding: EdgeInsets.only(top: 100),
              child: Stack(
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: 1.6,
                      child: Transform.rotate(
                        angle: 90 * 3.14159 / 180, // Rotate oval 90 degrees
                        child: ClipOval(
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: widget.primaryColor),
                            child: ClipOval(
                              child: cameraView,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  M7LivelynessDetectionStepOverlay(
                    key: _stepsKey,
                    steps: _steps,
                    circleIndicator: widget.circleIndicator,
                    styleAnimatedContainer: widget.styleAnimatedContainer,
                    onCompleted: () => Future.delayed(
                      const Duration(milliseconds: 500),
                      () => _takePicture(
                        didCaptureAutomatically: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            widget.description,
          ],
        ));
  }
}
