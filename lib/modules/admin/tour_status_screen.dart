import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import '../../core/theme/colors.dart';
import '../../theme/colors.dart';

class TourStatusScreen extends StatefulWidget {
  const TourStatusScreen({super.key});

  @override
  State<TourStatusScreen> createState() => _TourStatusScreenState();
}

class _TourStatusScreenState extends State<TourStatusScreen> {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  
  bool _isLoading = true;
  String? _currentStatus;
  String? _lastUpdatedBy;
  DateTime? _lastUpdatedAt;
  List<Map<String, dynamic>> _history = [];
  bool _isSaving = false;
  bool _isSendingEmails = false;
  bool _isSendingSms = false;
  int? _lastEmailCount;
  bool _isDisruptingDeparture = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    
    try {
      // Use HTTP endpoint which we know works
      final uri = Uri.parse('https://us-central1-aurora-viking-staff.cloudfunctions.net/getTourStatus');
      final response = await _functions.httpsCallable('getTourStatusHistory').call({'limit': 14});
      
      // Also fetch from public endpoint for current status
      final httpResponse = await Uri.parse('https://us-central1-aurora-viking-staff.cloudfunctions.net/getTourStatus')
          .toString();
      
      // Parse history from callable
      final historyData = response.data;
      final history = (historyData['history'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      
      // Get current status from the first item in history or use today's
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      Map<String, dynamic>? todayStatus;
      
      for (final h in history) {
        if (h['date'] == today) {
          todayStatus = h;
          break;
        }
      }
      
      setState(() {
        _currentStatus = todayStatus?['status'] as String?;
        _lastUpdatedBy = todayStatus?['updatedByName'] as String?;
        if (todayStatus?['updatedAt'] != null) {
          final ts = todayStatus!['updatedAt'];
          if (ts is String) {
            _lastUpdatedAt = DateTime.tryParse(ts);
          }
        }
        _history = history;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading tour status: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load status: $e')),
        );
      }
    }
  }

  Future<void> _setStatus(String status) async {
    if (status == 'OFF') {
      // Show the new checkbox action sheet for cancellations
      _showCancellationActionsSheet();
      return;
    }

    // For ON status, keep the existing simple flow
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Confirm Tour ON',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Set the tour status to ON for today?',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('Set ON'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      final result = await _functions.httpsCallable('setTourStatus').call({
        'status': 'ON',
        'message': 'Tour is running',
        'sendEmail': false,
      });

      if (result.data['success'] == true) {
        setState(() {
          _currentStatus = result.data['status'] as String?;
          _lastUpdatedBy = result.data['updatedByName'] as String?;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tour status set to ON ✅'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Ask about sending confirmation emails
        if (mounted) {
          final sendEmails = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Row(
                children: [
                  Icon(Icons.email_outlined, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Send Emails?', style: TextStyle(color: Colors.white)),
                ],
              ),
              content: Text(
                'Send personalized pickup info emails to all customers booked for today?',
                style: TextStyle(color: Colors.grey[300]),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Not Now'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Send Emails'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
              ],
            ),
          );

          if (sendEmails == true) {
            _sendEmails();
          }
        }

        _loadStatus();
      }
    } catch (e) {
      print('Error setting tour status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to set status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final displayDate = DateFormat('EEEE, MMMM d').format(today);
    final shortDate = DateFormat('d.MMM').format(today).toUpperCase();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tour Status'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadStatus,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Today's Date
                  Text(
                    displayDate,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Current Status Display
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _getStatusColor().withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _getStatusColor().withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Northern Lights Tour',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              shortDate,
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _getStatusColor(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'is',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: _getStatusColor(),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _currentStatus ?? 'NOT SET',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 24,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _getStatusEmoji(),
                              style: const TextStyle(fontSize: 32),
                            ),
                          ],
                        ),
                        if (_lastUpdatedBy != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Updated by $_lastUpdatedBy',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Toggle Buttons
                  Text(
                    'Set Today\'s Status:',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatusButton(
                          'ON',
                          '✅',
                          Colors.green,
                          _currentStatus == 'ON',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatusButton(
                          'OFF',
                          '😞',
                          Colors.red,
                          _currentStatus == 'OFF',
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Send Emails Button
                  if (_currentStatus != null)
                    _buildSendEmailsButton(),
                  
                  const SizedBox(height: 32),
                  
                  // History Section
                  if (_history.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Recent History',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._history.take(7).map((h) => _buildHistoryItem(h)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStatusButton(String status, String emoji, Color color, bool isSelected) {
    return GestureDetector(
      onTap: _isSaving ? null : () => _setStatus(status),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color,
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 48),
            ),
            const SizedBox(height: 8),
            Text(
              status,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : color,
              ),
            ),
            if (_isSaving && !isSelected)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final date = item['displayDate'] ?? item['date'] ?? 'Unknown';
    final status = item['status'] ?? 'UNKNOWN';
    final updatedBy = item['updatedByName'] ?? '';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            date,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: status == 'ON' ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              status,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (updatedBy.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              updatedBy,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor() {
    if (_currentStatus == 'ON') return Colors.green;
    if (_currentStatus == 'OFF') return Colors.red;
    return Colors.grey;
  }

  String _getStatusEmoji() {
    if (_currentStatus == 'ON') return '✅';
    if (_currentStatus == 'OFF') return '😞';
    return '❓';
  }

  Future<void> _sendEmails() async {
    if (_currentStatus == null) return;
    
    setState(() => _isSendingEmails = true);
    
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final result = await _functions.httpsCallable('sendTourStatusEmails').call({
        'status': _currentStatus,
        'date': today,
      });
      
      final emailsSent = result.data['emailsSent'] as int? ?? 0;
      final uniqueCustomers = result.data['uniqueCustomers'] as int? ?? 0;
      
      setState(() {
        _lastEmailCount = emailsSent;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Sent $emailsSent emails to $uniqueCustomers customers'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      print('Error sending emails: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send emails: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSendingEmails = false);
    }
  }

  Widget _buildSendEmailsButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AVColors.slateElev,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AVColors.outline),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.email_outlined, color: AVColors.primaryTeal),
              const SizedBox(width: 8),
              Text(
                'Email Customers',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AVColors.textHigh,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Send a ${_currentStatus == "ON" ? "confirmation" : "cancellation"} email to all customers with bookings today.',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSendingEmails ? null : _sendEmails,
              icon: _isSendingEmails
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(_isSendingEmails ? 'Sending...' : 'Send Emails Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _currentStatus == 'ON' ? Colors.green : Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_lastEmailCount != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last sent: $_lastEmailCount emails',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Cancellation Actions Bottom Sheet ───────────────────

  void _showCancellationActionsSheet() {
    // Local state for checkboxes (all checked by default)
    bool doSetStatus = true;
    bool doSendEmails = true;
    bool doSendSms = true;
    bool doDisruptDeparture = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Header
                  const Row(
                    children: [
                      Text('🚫', style: TextStyle(fontSize: 28)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cancel Tonight\'s Tour',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Select the actions to perform',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Checkbox 1: Set Status OFF
                  _buildActionCheckbox(
                    value: doSetStatus,
                    onChanged: (v) => setSheetState(() => doSetStatus = v ?? true),
                    icon: Icons.cancel_outlined,
                    iconColor: Colors.orange,
                    title: 'Set tour status to OFF',
                    subtitle: 'Updates the status in the system',
                  ),

                  const SizedBox(height: 12),

                  // Checkbox 2: Send Emails
                  _buildActionCheckbox(
                    value: doSendEmails,
                    onChanged: (v) => setSheetState(() => doSendEmails = v ?? true),
                    icon: Icons.email_outlined,
                    iconColor: Colors.blue,
                    title: 'Send cancellation emails',
                    subtitle: 'Email all customers with portal link',
                  ),

                  const SizedBox(height: 12),

                  // Checkbox 3: Send SMS
                  _buildActionCheckbox(
                    value: doSendSms,
                    onChanged: (v) => setSheetState(() => doSendSms = v ?? true),
                    icon: Icons.sms_outlined,
                    iconColor: Colors.purple,
                    title: 'Send cancellation SMS',
                    subtitle: 'Text all customers with portal link',
                  ),

                  const SizedBox(height: 12),

                  // Checkbox 4: Disrupt Departure
                  _buildActionCheckbox(
                    value: doDisruptDeparture,
                    onChanged: (v) => setSheetState(() => doDisruptDeparture = v ?? true),
                    icon: Icons.block_outlined,
                    iconColor: Colors.red,
                    title: 'Disrupt departure on Bokun',
                    subtitle: 'Close the departure so no new bookings come in',
                  ),

                  const SizedBox(height: 28),

                  // Execute Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: (!doSetStatus && !doSendEmails && !doSendSms && !doDisruptDeparture)
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              _executeCancellationActions(
                                setStatus: doSetStatus,
                                sendEmails: doSendEmails,
                                sendSms: doSendSms,
                                disruptDeparture: doDisruptDeparture,
                              );
                            },
                      icon: const Icon(Icons.rocket_launch, size: 20),
                      label: Text(
                        _getExecuteButtonLabel(doSetStatus, doSendEmails, doSendSms, doDisruptDeparture),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        disabledBackgroundColor: Colors.grey[800],
                      ),
                    ),
                  ),

                  // Safety spacer for bottom
                  SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActionCheckbox({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value ? iconColor.withOpacity(0.08) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? iconColor.withOpacity(0.3) : Colors.grey.withOpacity(0.15),
            width: value ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: value ? Colors.white : Colors.grey[400],
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: iconColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getExecuteButtonLabel(bool status, bool emails, bool sms, bool disrupt) {
    final count = [status, emails, sms, disrupt].where((v) => v).length;
    if (count == 0) return 'Select at least one action';
    if (count == 4) return 'Execute All Actions';
    return 'Execute $count Action${count > 1 ? 's' : ''}';
  }

  Future<void> _executeCancellationActions({
    required bool setStatus,
    required bool sendEmails,
    required bool sendSms,
    required bool disruptDeparture,
  }) async {
    setState(() => _isSaving = true);

    // Track progress for snackbar updates
    final actions = <String>[];
    final errors = <String>[];

    try {
      // Step 1: Set tour status to OFF
      if (setStatus) {
        try {
          final result = await _functions.httpsCallable('setTourStatus').call({
            'status': 'OFF',
            'message': 'Tour canceled',
            'sendEmail': false, // We handle emails separately
          });

          if (result.data['success'] == true) {
            setState(() {
              _currentStatus = result.data['status'] as String?;
              _lastUpdatedBy = result.data['updatedByName'] as String?;
            });
            actions.add('Status → OFF');
          }
        } catch (e) {
          print('Error setting tour status: $e');
          errors.add('Status: $e');
        }
      }

      // Step 2: Send cancellation emails (and SMS if checked)
      if (sendEmails || sendSms) {
        try {
          setState(() {
            if (sendEmails) _isSendingEmails = true;
            if (sendSms) _isSendingSms = true;
          });

          final result = await _functions.httpsCallable('sendTourStatusEmails').call({
            'status': 'OFF',
            'sendSms': sendSms,
          });

          final emailsSent = result.data['emailsSent'] as int? ?? 0;
          final smsSent = result.data['smsSent'] as int? ?? 0;

          setState(() {
            _lastEmailCount = emailsSent;
            _isSendingEmails = false;
            _isSendingSms = false;
          });
          if (sendEmails) actions.add('$emailsSent emails sent');
          if (sendSms) actions.add('$smsSent SMS sent');
        } catch (e) {
          print('Error sending emails/SMS: $e');
          setState(() {
            _isSendingEmails = false;
            _isSendingSms = false;
          });
          errors.add('Emails/SMS: $e');
        }
      }

      // Step 3: Disrupt departure on Bokun
      if (disruptDeparture) {
        try {
          setState(() => _isDisruptingDeparture = true);
          await _disruptDeparture();
          setState(() => _isDisruptingDeparture = false);
          actions.add('Departure disrupted');
        } catch (e) {
          print('Error disrupting departure: $e');
          setState(() => _isDisruptingDeparture = false);
          errors.add('Disrupt: $e');
        }
      }

      // Show final result
      if (mounted) {
        if (errors.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ All done! ${actions.join(' • ')}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ Partial: ${actions.join(' • ')}${errors.isNotEmpty ? '\nErrors: ${errors.join(', ')}' : ''}',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }

      // Reload history
      _loadStatus();
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _disruptDeparture() async {
    // Call the Cloud Function that disrupts the departure on Bokun
    final result = await _functions.httpsCallable('disruptDeparture').call({});

    if (result.data['success'] != true) {
      throw Exception(result.data['error'] ?? 'Failed to disrupt departure');
    }

    print('✅ Departure disrupted on Bokun: ${result.data}');
  }
}
