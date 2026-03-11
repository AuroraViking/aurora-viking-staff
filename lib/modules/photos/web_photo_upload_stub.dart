// Stub for non-web platforms - returns placeholder widget.
// The real implementation lives in web_photo_upload_screen.dart
// and is only imported when running on web.
import 'package:flutter/material.dart';

class WebPhotoUploadScreen extends StatelessWidget {
  const WebPhotoUploadScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Photo upload is only available on web'));
}
