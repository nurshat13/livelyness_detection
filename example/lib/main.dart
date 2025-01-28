import 'package:flutter/services.dart';
import 'package:m7_livelyness_detection_example/index.dart';
import 'package:m7_livelyness_detection_example/screens/example_face_detaticon.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: FaceDetectionPage(),
      // home: M7ExpampleScreen(),
    );
  }
}
