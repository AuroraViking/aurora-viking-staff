// ============================================
// MANUAL SHIFT ASSIGNMENT DIALOG
// ============================================
// For when guides get called in and show up without applying
// Create as: lib/modules/admin/manual_shift_assignment_dialog.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/colors.dart';
import '../../core/models/shift_model.dart';

class ManualShiftAssignmentDialog extends StatefulWidget {
  final DateTime date;
  final ShiftType? preselectedType;
  final Function(bool success) onComplete;

  const ManualShiftAssignmentDialog({
    super.key,
    required this.date,
    this.preselectedType,
    required this.onComplete,
  });

  @override
  State<ManualShiftAssignmentDialog> createState() => _ManualShiftAssignmentDialogState();
}

class _ManualShiftAssignmentDialogState extends State<ManualShiftAssignmentDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Form state
  String? _selectedGuideId;
  String? _selectedGuideName;
  ShiftType _selectedType = ShiftType.northernLights;
  String? _selectedBusId;
  String? _selectedBusName;
  final TextEditingController _notesController = TextEditingController();
  
  // Data
  List<Map<String, dynamic>> _guides = [];
  List<Map<String, dynamic>> _buses = [];
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedType != null) {
      _selectedType = widget.preselectedType!;
    }
    _loadData();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // Load all guides
      final guidesSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'guide')
          .get();
      
      final guides = guidesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['fullName'] ?? data['displayName'] ?? 'Unknown',
          'email': data['email'] ?? '',
          'isActive': data['isActive'] ?? true,
        };
      }).toList();
      
      // Sort by name
      guides.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      
      // Load available buses
      final busesSnapshot = await _firestore
          .collection('buses')
          .where('isActive', isEqualTo: true)
          .get();
      
      final buses = busesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? 'Unknown',
          'licensePlate': data['licensePlate'] ?? '',
        };
      }).toList();
      
      setState(() {
        _guides = guides;
        _buses = buses;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedGuideId == null || _selectedGuideName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a guide'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final dateStr = '${widget.date.year}-${widget.date.month.toString().padLeft(2, '0')}-${widget.date.day.toString().padLeft(2, '0')}';
      final shiftId = '${dateStr}_${_selectedGuideId}_${DateTime.now().millisecondsSinceEpoch}';
      
      // Check if guide already has a shift on this date
      final existingShifts = await _firestore
          .collection('shifts')
          .where('guideId', isEqualTo: _selectedGuideId)
          .where('date', isEqualTo: widget.date.toIso8601String())
          .get();
      
      if (existingShifts.docs.isNotEmpty) {
        if (mounted) {
          final proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              title: const Text(
                'Guide Already Assigned',
                style: TextStyle(color: Colors.white),
              ),
              content: Text(
                '$_selectedGuideName already has a shift on this date. Add another shift anyway?',
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AVColors.primaryTeal),
                  child: const Text('Add Anyway'),
                ),
              ],
            ),
          );
          
          if (proceed != true) {
            setState(() => _isSubmitting = false);
            return;
          }
        }
      }
      
      // Create the shift
      await _firestore.collection('shifts').doc(shiftId).set({
        'id': shiftId,
        'type': _selectedType.name,
        'date': widget.date.toIso8601String(),
        'startTime': _selectedType == ShiftType.northernLights ? '20:00' : '09:00',
        'endTime': _selectedType == ShiftType.northernLights ? '03:00' : '17:00',
        'status': 'accepted', // Directly accepted - manual assignment
        'guideId': _selectedGuideId,
        'guideName': _selectedGuideName,
        'busId': _selectedBusId,
        'busName': _selectedBusName,
        'notes': _notesController.text.isNotEmpty ? _notesController.text : null,
        'assignedManually': true, // Flag that this was manually assigned
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ Manually assigned $_selectedGuideName to ${_selectedType.name} on $dateStr');
      
      if (mounted) {
        Navigator.pop(context);
        widget.onComplete(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $_selectedGuideName assigned to shift'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Error assigning shift: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = '${widget.date.day}/${widget.date.month}/${widget.date.year}';
    
    return Dialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: _isLoading
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AVColors.primaryTeal.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.person_add,
                            color: AVColors.primaryTeal,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Assign Guide to Shift',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                dateStr,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Shift Type Selection
                    const Text(
                      'Shift Type',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTypeChip(
                            ShiftType.northernLights,
                            'Northern Lights',
                            Icons.nightlight_round,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTypeChip(
                            ShiftType.dayTour,
                            'Day Tour',
                            Icons.wb_sunny,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Guide Selection
                    const Text(
                      'Select Guide',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[700]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedGuideId,
                          hint: const Text(
                            'Choose a guide...',
                            style: TextStyle(color: Colors.grey),
                          ),
                          dropdownColor: const Color(0xFF252540),
                          style: const TextStyle(color: Colors.white),
                          items: _guides.map((guide) {
                            return DropdownMenuItem<String>(
                              value: guide['id'] as String,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: AVColors.primaryTeal,
                                    child: Text(
                                      (guide['name'] as String)[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      guide['name'] as String,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            final guide = _guides.firstWhere((g) => g['id'] == value);
                            setState(() {
                              _selectedGuideId = value;
                              _selectedGuideName = guide['name'] as String;
                            });
                          },
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Bus Selection (Optional)
                    const Text(
                      'Assign Bus (Optional)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[700]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedBusId,
                          hint: const Text(
                            'No bus assigned',
                            style: TextStyle(color: Colors.grey),
                          ),
                          dropdownColor: const Color(0xFF252540),
                          style: const TextStyle(color: Colors.white),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('No bus assigned'),
                            ),
                            ..._buses.map((bus) {
                              return DropdownMenuItem<String>(
                                value: bus['id'] as String,
                                child: Row(
                                  children: [
                                    const Icon(Icons.directions_bus, size: 18, color: Colors.blue),
                                    const SizedBox(width: 8),
                                    Text('${bus['name']} (${bus['licensePlate']})'),
                                  ],
                                ),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              setState(() {
                                _selectedBusId = null;
                                _selectedBusName = null;
                              });
                            } else {
                              final bus = _buses.firstWhere((b) => b['id'] == value);
                              setState(() {
                                _selectedBusId = value;
                                _selectedBusName = bus['name'] as String;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Notes
                    const Text(
                      'Notes (Optional)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesController,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'e.g., Called in last minute, covering for X...',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        filled: true,
                        fillColor: Colors.grey[850],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AVColors.primaryTeal),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AVColors.primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Assign to Shift',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildTypeChip(ShiftType type, String label, IconData icon) {
    final isSelected = _selectedType == type;
    final color = type == ShiftType.northernLights ? Colors.purple : Colors.orange;
    
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.grey[850],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? color : Colors.grey,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

