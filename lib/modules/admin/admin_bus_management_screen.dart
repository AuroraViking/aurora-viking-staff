import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/services/bus_management_service.dart';
import '../../core/theme/colors.dart';

class AdminBusManagementScreen extends StatefulWidget {
  const AdminBusManagementScreen({super.key});

  @override
  State<AdminBusManagementScreen> createState() => _AdminBusManagementScreenState();
}

class _AdminBusManagementScreenState extends State<AdminBusManagementScreen> {
  final BusManagementService _busService = BusManagementService();
  List<Map<String, dynamic>> _buses = [];
  bool _isLoading = true;

  // Color options for buses
  final List<Map<String, dynamic>> _colorOptions = [
    {'name': 'Blue', 'color': Colors.blue, 'value': 'blue'},
    {'name': 'Green', 'color': Colors.green, 'value': 'green'},
    {'name': 'Red', 'color': Colors.red, 'value': 'red'},
    {'name': 'Orange', 'color': Colors.orange, 'value': 'orange'},
    {'name': 'Purple', 'color': Colors.purple, 'value': 'purple'},
    {'name': 'Teal', 'color': Colors.teal, 'value': 'teal'},
  ];

  @override
  void initState() {
    super.initState();
    _loadBuses();
  }

  void _loadBuses() {
    _busService.getAllBuses().listen((buses) {
      setState(() {
        _buses = buses;
        _isLoading = false;
      });
    });
  }

  void _showAddBusDialog() {
    final nameController = TextEditingController();
    final licensePlateController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedColor = 'blue';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Bus'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Bus Name',
                  hintText: 'e.g., Lúxusinn - AYX70',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: licensePlateController,
                decoration: const InputDecoration(
                  labelText: 'License Plate',
                  hintText: 'e.g., AYX70',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedColor,
                decoration: const InputDecoration(
                  labelText: 'Color',
                ),
                items: _colorOptions.map((color) {
                  return DropdownMenuItem<String>(
                    value: color['value'] as String,
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: color['color'] as Color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(color['name'] as String),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  selectedColor = value!;
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'Additional notes about the bus',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty ||
                  licensePlateController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill in all required fields')),
                );
                return;
              }

              final success = await _busService.addBus(
                name: nameController.text.trim(),
                licensePlate: licensePlateController.text.trim(),
                color: selectedColor,
                description: descriptionController.text.trim(),
              );

              if (success) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bus added successfully')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to add bus')),
                );
              }
            },
            child: const Text('Add Bus'),
          ),
        ],
      ),
    );
  }

  void _showEditBusDialog(Map<String, dynamic> bus) {
    final nameController = TextEditingController(text: bus['name']);
    final licensePlateController = TextEditingController(text: bus['licensePlate']);
    final descriptionController = TextEditingController(text: bus['description'] ?? '');
    String selectedColor = bus['color'] ?? 'blue';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Bus: ${bus['name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Bus Name',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: licensePlateController,
                decoration: const InputDecoration(
                  labelText: 'License Plate',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedColor,
                decoration: const InputDecoration(
                  labelText: 'Color',
                ),
                items: _colorOptions.map((color) {
                  return DropdownMenuItem<String>(
                    value: color['value'] as String,
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: color['color'] as Color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(color['name'] as String),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  selectedColor = value!;
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty ||
                  licensePlateController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill in all required fields')),
                );
                return;
              }

              final success = await _busService.updateBus(
                busId: bus['id'],
                name: nameController.text.trim(),
                licensePlate: licensePlateController.text.trim(),
                color: selectedColor,
                description: descriptionController.text.trim(),
              );

              if (success) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bus updated successfully')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to update bus')),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showDeleteBusDialog(Map<String, dynamic> bus) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bus'),
        content: Text(
          'Are you sure you want to delete "${bus['name']}"?\n\n'
          'This will also remove all location history and related data for this bus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await _busService.deleteBus(bus['id']);
              Navigator.pop(context);
              
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bus deleted successfully')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cannot delete bus that is currently being tracked'),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBusStatus(Map<String, dynamic> bus) async {
    final newStatus = !(bus['isActive'] ?? true);
    final success = await _busService.toggleBusStatus(bus['id'], newStatus);
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bus ${newStatus ? 'activated' : 'deactivated'} successfully'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update bus status')),
      );
    }
  }

  Color _getColorFromString(String colorName) {
    switch (colorName) {
      case 'blue': return Colors.blue;
      case 'green': return Colors.green;
      case 'red': return Colors.red;
      case 'orange': return Colors.orange;
      case 'purple': return Colors.purple;
      case 'teal': return Colors.teal;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bus Management'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _showAddBusDialog,
            icon: const Icon(Icons.add),
            tooltip: 'Add New Bus',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.directions_bus_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No buses found',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add your first bus to get started',
                        style: TextStyle(
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _showAddBusDialog,
                        child: const Text('Add First Bus'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _buses.length,
                  itemBuilder: (context, index) {
                    final bus = _buses[index];
                    final isActive = bus['isActive'] ?? true;
                    final color = _getColorFromString(bus['color'] ?? 'grey');

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color,
                          child: Icon(
                            Icons.directions_bus,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          bus['name'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isActive ? null : Colors.grey[600],
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('License: ${bus['licensePlate']}'),
                            if (bus['description']?.isNotEmpty == true)
                              Text(
                                bus['description'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive ? Colors.green[100] : Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isActive ? Colors.green : Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: isActive,
                              onChanged: (value) => _toggleBusStatus(bus),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                switch (value) {
                                  case 'edit':
                                    _showEditBusDialog(bus);
                                    break;
                                  case 'delete':
                                    _showDeleteBusDialog(bus);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 16),
                                      SizedBox(width: 8),
                                      Text('Edit'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, size: 16, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Delete', style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
} 