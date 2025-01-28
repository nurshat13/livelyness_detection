import 'package:flutter/cupertino.dart';
import 'package:m7_livelyness_detection/index.dart';

class FaceDetectionPage extends StatefulWidget {
  const FaceDetectionPage({super.key});

  @override
  State<FaceDetectionPage> createState() => _FaceDetectionPageState();
}

class _FaceDetectionPageState extends State<FaceDetectionPage> {
  final List<M7LivelynessStepItem> _veificationSteps = [];

  void _initValues() {
    _veificationSteps.addAll(
      [
        M7LivelynessStepItem(
          step: M7LivelynessStep.smile,
          title: "Smile",
          isCompleted: false,
        ),
        M7LivelynessStepItem(
          step: M7LivelynessStep.blink,
          title: "Blink",
          isCompleted: false,
        ),
      ],
    );
    M7LivelynessDetection.instance.configure(
      lineColor: Colors.transparent,
      dotColor: Colors.transparent,
      thresholds: [
        M7SmileDetectionThreshold(probability: 0.8),
        M7BlinkDetectionThreshold(
          leftEyeProbability: 0.85,
          rightEyeProbability: 0.85,
        ),
      ],
    );
  }

  // void _onStartLivelyness(context) async {
  //   final M7CapturedImage? response =
  //       await M7LivelynessDetection.instance.detectLivelyness(
  //     context,
  //     config: M7DetectionConfig(
  //       steps: _veificationSteps,
  //       startWithInfoScreen: false,
  //       maxSecToDetect: 2500,
  //       allowAfterMaxSec: false,
  //       captureButtonColor: Colors.blue,
  //     ),
  //     text: Padding(
  //       padding: const EdgeInsets.symmetric(horizontal: 22),
  //       child: Text(
  //         'Пожалуйста, расположите свое лицо в овал',
  //         textAlign: TextAlign.center,
  //         style: Theme.of(context).textTheme.labelLarge?.copyWith(
  //               color: Colors.grey,
  //               fontWeight: FontWeight.w400,
  //             ),
  //       ),
  //     ),
  //   );
  //   if (response == null) {
  //     return;
  //   }
  // }
  // void initilizeDetection() => M7LivelynessDetection.instance.configure(
  //       lineColor: Colors.white,
  //       dotColor: Colors.purple.shade800,
  //       dotSize: 2.0,
  //       lineWidth: 2,
  //       dashValues: [2.0, 5.0],
  //       displayDots: false,
  //       displayLines: false,
  //       thresholds: [
  //         M7SmileDetectionThreshold(probability: 0.8),
  //         M7BlinkDetectionThreshold(
  //           leftEyeProbability: 0.25,
  //           rightEyeProbability: 0.25,
  //         ),
  //       ],
  //     );

  void _onStartLivelyness(context) async {
    final M7CapturedImage? response =
        await M7LivelynessDetection.instance.detectLivelyness(
      context,
      appBar: AppBar(),
      primaryColor: const Color.fromRGBO(229, 101, 83, 1),
      config: M7DetectionConfig(
        steps: _veificationSteps,
        startWithInfoScreen: false,
        maxSecToDetect: 2500,
        allowAfterMaxSec: false,
        captureButtonColor: const Color.fromRGBO(229, 101, 83, 1),
      ),
      description: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 22),
        child: Text(
          'Пожалуйста, расположите свое лицо в овал',
          textAlign: TextAlign.center,
        ),
      ),
      scaffoldColor: Colors.white,
      backgroundColor: Colors.white,
      circleIndicator: Center(child: CupertinoActivityIndicator()),
      styleAnimatedContainer: TextStyle(),
    );
    if (response == null) {
      return;
    }
    print('ALI IMAGE:' + response.imgPath);
    // model.uploadImageIdentificationSelfie(File(response.imgPath));
    // Navigator.push(
    //     context,
    //     MaterialPageRoute(
    //         builder: (context) => const DocumentPictureFrontWidget()));
  }

  @override
  void initState() {
    _initValues();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text('Видео-идентификация'),
      ),
      body: Column(
        children: [
          CupertinoButton(
            onPressed: () => _onStartLivelyness(context),
            color: const Color.fromRGBO(229, 101, 83, 1),
            padding: const EdgeInsets.all(0),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Start',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
