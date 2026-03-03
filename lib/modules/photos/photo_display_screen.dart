// Full screen display for guests to photograph the screen
// Shows email, guide name, and date on a black background
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PhotoDisplayScreen extends StatefulWidget {
  final String guideName;
  final String date;

  const PhotoDisplayScreen({
    super.key,
    required this.guideName,
    required this.date,
  });

  @override
  State<PhotoDisplayScreen> createState() => _PhotoDisplayScreenState();
}

class _PhotoDisplayScreenState extends State<PhotoDisplayScreen> {
  @override
  void initState() {
    super.initState();
    // Hide system UI for true fullscreen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Email address - large and prominent
              const Text(
                'PHOTO@AURORAVIKING.COM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // Divider line
              Container(
                width: 120,
                height: 2,
                color: Colors.white24,
              ),
              const SizedBox(height: 48),

              // Guide name
              Text(
                widget.guideName,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Date
              Text(
                widget.date,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 64),

              // Tap hint
              Text(
                'Tap anywhere to close',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.2),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
