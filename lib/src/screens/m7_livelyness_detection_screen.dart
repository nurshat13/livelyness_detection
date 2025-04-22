import 'dart:async';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:m7_livelyness_detection/index.dart';

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
  State<M7LivelynessDetectionScreenV1> createState() =>
      _MLivelyness7DetectionScreenState();
}

class _MLivelyness7DetectionScreenState
    extends State<M7LivelynessDetectionScreenV1> {
  //* MARK: - Private Variables
  //? =========================================================
  late final List<M7LivelynessStepItem> steps;
  CameraController? _cameraController;
  int _cameraIndex = 0;
  bool _isBusy = false;
  final GlobalKey<M7LivelynessDetectionStepOverlayState> _stepsKey =
      GlobalKey<M7LivelynessDetectionStepOverlayState>();
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
      (element) =>
          element.lensDirection == CameraLensDirection.front &&
          element.sensorOrientation == 90,
    )) {
      _cameraIndex = availableCams.indexOf(
        availableCams.firstWhere((element) =>
            element.lensDirection == CameraLensDirection.front &&
            element.sensorOrientation == 90),
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
    final bytes = allBytes.done().buffer.asUint8List();

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

    final inputImageMetadata = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow:planeData.single.bytesPerRow,
    );

    final inputImage = InputImage.fromBytes(
    bytes: bytes,
    metadata: InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: planeData.single.bytesPerRow,
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

    if (inputImage.metadata?.size != null &&
        inputImage.metadata?.rotation != null) {
      if (faces.isEmpty) {
        _resetSteps();
      } else {
        final firstFace = faces.first;
        final painter = M7FaceDetectorPainter(
          firstFace,
          inputImage.metadata!.size,
          inputImage.metadata!.rotation,
        );
        if (_isProcessingStep &&
            _steps[_stepsKey.currentState?.currentIndex ?? 0].step ==
                M7LivelynessStep.blink) {
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
      // if (face == null) return;
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
      _onDetectionCompleted(
        imgToReturn: clickedImage,
        didCaptureAutomatically: didCaptureAutomatically,
      );
    } catch (e) {
      _startLiveFeed();
    }
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
        if ((face.leftEyeOpenProbability ?? 1.0) <
                (blinkThreshold?.leftEyeProbability ?? 0.25) &&
            (face.rightEyeOpenProbability ?? 1.0) <
                (blinkThreshold?.rightEyeProbability ?? 0.25)) {
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
        if ((face.headEulerAngleY ?? 0) >
            (headTurnThreshold?.rotationAngle ?? 45)) {
          _startProcessing();
          await _completeStep(step: step);
        }
        break;
      case M7LivelynessStep.turnRight:
        final M7HeadTurnDetectionThreshold? headTurnThreshold =
            M7LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is M7HeadTurnDetectionThreshold,
        ) as M7HeadTurnDetectionThreshold?;
        if ((face.headEulerAngleY ?? 0) >
            (headTurnThreshold?.rotationAngle ?? -50)) {
          _startProcessing();
          await _completeStep(step: step);
        }
        break;
      case M7LivelynessStep.smile:
        final M7SmileDetectionThreshold? smileThreshold =
            M7LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is M7SmileDetectionThreshold,
        ) as M7SmileDetectionThreshold?;
        if ((face.smilingProbability ?? 0) >
            (smileThreshold?.probability ?? 0.75)) {
          _startProcessing();
          await _completeStep(step: step);
        }
        break;
    }
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
    if (_cameraController == null ||
        _cameraController?.value.isInitialized == false) {
      return Expanded(child: widget.circleIndicator);
    }
    final Widget cameraView = CameraPreview(_cameraController!);
    return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.width - 50,
              child: Stack(
                children: [
                  Center(
                    child: ClipOval(
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: widget.primaryColor),
                        child: ClipOval(child: cameraView),
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
