// Full screen display for guests to photograph the screen
// Shows website, email, guide name, and date on a black background
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
              // Website URL - top priority
              const Text(
                'AURORAVIKING.COM/PHOTOS',
                style: TextStyle(
                  color: Color(0xFFD4AF37),
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Subtitle
              Text(
                'Get your photos on our website',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Divider line
              Container(
                width: 120,
                height: 2,
                color: Colors.white24,
              ),
              const SizedBox(height: 40),

              // Email address
              const Text(
                'PHOTO@AURORAVIKING.COM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Or email us with your date & guide name',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Divider line
              Container(
                width: 80,
                height: 1,
                color: Colors.white12,
              ),
              const SizedBox(height: 40),

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
