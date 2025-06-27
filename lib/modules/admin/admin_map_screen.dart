// Admin map screen for viewing all guides' locations on a map 
import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

class AdminMapScreen extends StatefulWidget {
  const AdminMapScreen({super.key});

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  // Sample data for demonstration
  final List<Map<String, dynamic>> _activeTours = [
    {
      'id': '1',
      'guide': 'John Doe',
      'tourType': 'Day Tour',
      'busNumber': 'Bus 1',
      'status': 'Active',
      'location': 'Downtown Reykjavik',
      'lastUpdate': '2 min ago',
      'coordinates': {'lat': 64.1466, 'lng': -21.9426},
    },
    {
      'id': '2',
      'guide': 'Jane Smith',
      'tourType': 'Northern Lights',
      'busNumber': 'Bus 2',
      'status': 'Active',
      'location': 'Golden Circle',
      'lastUpdate': '5 min ago',
      'coordinates': {'lat': 64.2550, 'lng': -20.1215},
    },
    {
      'id': '3',
      'guide': 'Mike Johnson',
      'tourType': 'Day Tour',
      'busNumber': 'Bus 3',
      'status': 'Returning',
      'location': 'Blue Lagoon',
      'lastUpdate': '1 min ago',
      'coordinates': {'lat': 63.8804, 'lng': -22.4495},
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tracking Map'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () {
              // TODO: Refresh map data
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Refreshing map data...')),
              );
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Map placeholder
          Container(
            height: 300,
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Stack(
              children: [
                // Placeholder for actual map
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.map,
                        size: 64,
                        color: AppColors.primary.withOpacity(0.6),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Live Tracking Map',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Map integration coming soon',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                // Tour markers
                ..._activeTours.asMap().entries.map((entry) {
                  final index = entry.key;
                  final tour = entry.value;
                  return Positioned(
                    left: 50 + (index * 80.0),
                    top: 100 + (index * 40.0),
                    child: _buildMapMarker(tour),
                  );
                }).toList(),
              ],
            ),
          ),
          
          // Active tours list
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Active Tours (${_activeTours.length})',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'Last updated: ${DateTime.now().toString().substring(11, 16)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _activeTours.length,
                      itemBuilder: (context, index) {
                        final tour = _activeTours[index];
                        return _buildTourCard(tour);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapMarker(Map<String, dynamic> tour) {
    Color markerColor;
    switch (tour['status']) {
      case 'Active':
        markerColor = Colors.green;
        break;
      case 'Returning':
        markerColor = Colors.orange;
        break;
      default:
        markerColor = Colors.grey;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: markerColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.location_on,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  Widget _buildTourCard(Map<String, dynamic> tour) {
    Color statusColor;
    IconData statusIcon;
    
    switch (tour['status']) {
      case 'Active':
        statusColor = Colors.green;
        statusIcon = Icons.radio_button_checked;
        break;
      case 'Returning':
        statusColor = Colors.orange;
        statusIcon = Icons.arrow_back;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.radio_button_unchecked;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(statusIcon, color: statusColor),
        ),
        title: Text(
          tour['guide'],
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${tour['tourType']} - ${tour['busNumber']}'),
            Text(
              tour['location'],
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            Text(
              'Last update: ${tour['lastUpdate']}',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case 'contact':
                // TODO: Contact guide
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Contacting ${tour['guide']}...')),
                );
                break;
              case 'details':
                // TODO: Show tour details
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Showing details for ${tour['guide']}...')),
                );
                break;
              case 'history':
                // TODO: Show tour history
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Showing history for ${tour['guide']}...')),
                );
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'contact',
              child: Row(
                children: [
                  Icon(Icons.message, size: 16),
                  SizedBox(width: 8),
                  Text('Contact Guide'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'details',
              child: Row(
                children: [
                  Icon(Icons.info, size: 16),
                  SizedBox(width: 8),
                  Text('Tour Details'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'history',
              child: Row(
                children: [
                  Icon(Icons.history, size: 16),
                  SizedBox(width: 8),
                  Text('Tour History'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} 