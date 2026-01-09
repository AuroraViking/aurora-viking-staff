import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

class EndOfShiftDialog extends StatefulWidget {
  final String guideName;
  final String? busName;
  final Function(String auroraRating, bool shouldRequestReviews, String? notes) onSubmit;

  const EndOfShiftDialog({
    super.key,
    required this.guideName,
    this.busName,
    required this.onSubmit,
  });

  @override
  State<EndOfShiftDialog> createState() => _EndOfShiftDialogState();
}

class _EndOfShiftDialogState extends State<EndOfShiftDialog> {
  String _selectedAuroraRating = '';
  bool _shouldRequestReviews = true;
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;

  final List<_AuroraOption> _auroraOptions = [
    _AuroraOption('not_seen', 'Not seen', '😔', Colors.grey),
    _AuroraOption('camera_only', 'Only through camera', '📷', Colors.blueGrey),
    _AuroraOption('a_little', 'A little bit', '✨', Colors.amber),
    _AuroraOption('good', 'Good', '🌟', Colors.lightGreen),
    _AuroraOption('great', 'Great', '⭐', Colors.green),
    _AuroraOption('exceptional', 'Exceptional', '🤩', Colors.purple),
  ];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (_selectedAuroraRating.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please rate the aurora visibility'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await widget.onSubmit(
        _selectedAuroraRating,
        _shouldRequestReviews,
        _notesController.text.isNotEmpty ? _notesController.text : null,
      );
      
      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting report: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
                      color: AppColors.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.nightlight_round,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'End of Shift Report',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.guideName,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                        if (widget.busName != null)
                          Text(
                            'Bus: ${widget.busName}',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Aurora Rating Section
              const Text(
                'How were the Northern Lights tonight?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              
              // Aurora rating grid
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _auroraOptions.map((option) {
                  final isSelected = _selectedAuroraRating == option.value;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedAuroraRating = option.value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? option.color.withOpacity(0.3)
                            : Colors.grey[800],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? option.color : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            option.emoji,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            option.label,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.grey[400],
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              
              const SizedBox(height: 24),
              
              // Request Reviews Toggle
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.rate_review,
                      color: _shouldRequestReviews ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Request reviews from guests?',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            _shouldRequestReviews 
                                ? 'Yes, send review requests'
                                : 'No, skip reviews for this tour',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _shouldRequestReviews,
                      onChanged: (value) => setState(() => _shouldRequestReviews = value),
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Notes Section
              const Text(
                'Notes (optional)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Any incidents, memorable moments, or things to remember?',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              
              TextField(
                controller: _notesController,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'E.g., "Bus had minor heating issue", "Guest proposed at viewing spot!", etc.',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Colors.grey[850],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary),
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
                    backgroundColor: AppColors.primary,
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
                          'Submit Report',
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
}

class _AuroraOption {
  final String value;
  final String label;
  final String emoji;
  final Color color;

  const _AuroraOption(this.value, this.label, this.emoji, this.color);
}

