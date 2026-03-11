// Full screen display for guests — landscape optimized for bus tablets
// Shows QR code linking to Drive photos (when available) + website/email info
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

class PhotoDisplayScreen extends StatefulWidget {
  final String guideName;
  final String date;
  final String? driveUrl; // Google Drive folder URL (if photos uploaded)

  const PhotoDisplayScreen({
    super.key,
    required this.guideName,
    required this.date,
    this.driveUrl,
  });

  @override
  State<PhotoDisplayScreen> createState() => _PhotoDisplayScreenState();
}

class _PhotoDisplayScreenState extends State<PhotoDisplayScreen> {
  @override
  void initState() {
    super.initState();
    // Force landscape + hide system UI for true fullscreen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Restore orientation + system UI
    SystemChrome.setPreferredOrientations([]);
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
          child: widget.driveUrl != null
              ? _buildLandscapeWithQR()
              : _buildFallbackView(),
        ),
      ),
    );
  }

  /// Landscape layout: QR code on left, info on right
  Widget _buildLandscapeWithQR() {
    return Row(
      children: [
        // Left side — QR code
        Expanded(
          flex: 4,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // QR code with white background
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD4AF37).withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: widget.driveUrl!,
                    version: QrVersions.auto,
                    size: 240,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '📸 Scan for your photos',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Right side — info
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Website URL
                const Text(
                  'AURORAVIKING.COM/PHOTOS',
                  style: TextStyle(
                    color: Color(0xFFD4AF37),
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Or visit our website to access your photos',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // Divider
                Container(
                  width: 100,
                  height: 1,
                  color: Colors.white12,
                ),
                const SizedBox(height: 32),

                // Email
                const Text(
                  'PHOTO@AURORAVIKING.COM',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Email us with your date & guide name',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // Divider
                Container(
                  width: 60,
                  height: 1,
                  color: Colors.white12,
                ),
                const SizedBox(height: 32),

                // Guide name and date
                Text(
                  widget.guideName,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.date,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                // Tap hint
                Text(
                  'Tap anywhere to close',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.15),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Fallback view when no Drive URL is available (pre-upload)
  Widget _buildFallbackView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
        Container(width: 120, height: 2, color: Colors.white24),
        const SizedBox(height: 40),
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
        Container(width: 80, height: 1, color: Colors.white12),
        const SizedBox(height: 40),
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
        Text(
          widget.date,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 22,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 64),
        Text(
          'Tap anywhere to close',
          style: TextStyle(
            color: Colors.white.withOpacity(0.2),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
