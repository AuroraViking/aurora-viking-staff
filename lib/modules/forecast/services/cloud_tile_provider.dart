import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class CloudTileProvider extends TileProvider {
  final String urlTemplate;
  final double timeOffset;

  CloudTileProvider({
    required this.urlTemplate,
    required this.timeOffset,
  });

  @override
  Future<Tile> getTile(int x, int y, int? z) async {
    final url = urlTemplate
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString())
        .replaceAll('{z}', z.toString());
    
    try {
      // Add debug logging
      print('Loading tile: x=$x, y=$y, z=$z, url=$url');
      
      final response = await http.get(Uri.parse(url));
      print('Tile response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        // Create tile with the correct constructor
        // The Tile constructor expects: Tile(int x, int y, Uint8List? data)
        return Tile(x, y, response.bodyBytes);
      } else {
        print('Failed to load tile: HTTP ${response.statusCode}');
        // Return an empty tile if loading fails
        return Tile(x, y, null);
      }
    } catch (e) {
      print('Error loading tile: $e');
      // Return an empty tile if loading fails
      return Tile(x, y, null);
    }
  }
} 