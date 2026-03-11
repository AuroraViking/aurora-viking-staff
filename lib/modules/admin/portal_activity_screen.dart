// Portal Activity Screen — View booking manifest with customer status flags
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

const String _apiBase = 'https://us-central1-aurora-viking-staff.cloudfunctions.net';

class PortalActivityScreen extends StatefulWidget {
  const PortalActivityScreen({super.key});

  @override
  State<PortalActivityScreen> createState() => _PortalActivityScreenState();
}

class _PortalActivityScreenState extends State<PortalActivityScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  String? _error;

  String _tourStatus = 'UNKNOWN';
  List<Map<String, dynamic>> _manifest = [];
  Map<String, int> _summary = {};

  @override
  void initState() {
    super.initState();
    _loadManifest();
  }

  String _dateStr(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Future<void> _loadManifest() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getBookingManifest');
      final result = await callable.call({'date': _dateStr(_selectedDate)});
      final data = Map<String, dynamic>.from(result.data as Map);

      setState(() {
        _tourStatus = data['tourStatus'] ?? 'UNKNOWN';
        _manifest = List<Map<String, dynamic>>.from(
          (data['manifest'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        _summary = Map<String, int>.from(data['summary'] as Map);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadManifest();
    }
  }

  Future<void> _markRefundStatus(String docId, String status) async {
    final user = FirebaseAuth.instance.currentUser;
    final adminName = user?.displayName ?? user?.email ?? 'Unknown Admin';
    final adminUid = user?.uid ?? 'unknown';

    try {
      await FirebaseFirestore.instance
          .collection('portal_cancellations')
          .doc(docId)
          .update({
        'status': status,
        'reviewedBy': adminUid,
        'reviewedByName': adminName,
        'reviewedAt': FieldValue.serverTimestamp(),
      });

      // Audit log
      await FirebaseFirestore.instance.collection('portal_activity_log').add({
        'action': 'refund_review',
        'cancellationDocId': docId,
        'status': status,
        'adminUid': adminUid,
        'adminName': adminName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _loadManifest();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'refunded'
                ? 'Marked as refunded by $adminName'
                : 'Marked as no refund by $adminName'),
            backgroundColor: status == 'refunded' ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Portal Activity'),
        backgroundColor: Colors.cyan[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadManifest),
        ],
      ),
      body: Column(
        children: [
          // Date picker + tour status
          _buildDateBar(),
          // Summary cards
          if (!_isLoading && _error == null) _buildSummaryRow(),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorState()
                    : _manifest.isEmpty
                        ? _buildEmptyState()
                        : _buildManifestList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDateBar() {
    Color statusColor;
    String statusText;
    switch (_tourStatus) {
      case 'ON':
        statusColor = Colors.green;
        statusText = '🟢 TOUR ON';
        break;
      case 'OFF':
        statusColor = Colors.red;
        statusText = '🔴 TOUR OFF';
        break;
      default:
        statusColor = Colors.grey;
        statusText = '⚪ NOT SET';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.cyan[700]!.withOpacity(0.08),
        border: Border(bottom: BorderSide(color: Colors.cyan.withOpacity(0.2))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.cyan.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.cyan),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('EEE, d MMM yyyy').format(_selectedDate),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              _buildDateChip('Today', DateTime.now()),
              const SizedBox(width: 4),
              _buildDateChip('Yest.', DateTime.now().subtract(const Duration(days: 1))),
            ],
          ),
          const SizedBox(height: 8),
          // Tour status banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: statusColor,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip(String label, DateTime date) {
    final isSelected = _dateStr(_selectedDate) == _dateStr(date);
    return GestureDetector(
      onTap: () {
        setState(() => _selectedDate = date);
        _loadManifest();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyan : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.cyan : Colors.cyan.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.cyan,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          _buildStat('Total', _manifest.length, Colors.cyan),
          const SizedBox(width: 6),
          _buildStat('Scheduled', _summary['asScheduled'] ?? 0, Colors.green),
          const SizedBox(width: 6),
          if ((_summary['disrupted'] ?? 0) > 0) ...[
            _buildStat('Disrupted', _summary['disrupted'] ?? 0, Colors.orange),
            const SizedBox(width: 6),
          ],
          _buildStat('Rescheduled', _summary['rescheduled'] ?? 0, Colors.blue),
          const SizedBox(width: 6),
          _buildStat('Cancelled', _summary['cancelled'] ?? 0, Colors.red),
        ],
      ),
    );
  }

  Widget _buildStat(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
            Text(label, style: TextStyle(fontSize: 9, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No bookings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey[600]),
          ),
          Text(
            'No bookings found for ${DateFormat('d MMM').format(_selectedDate)}',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text('Failed to load manifest', style: TextStyle(color: Colors.red[400], fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_error ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[600]), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadManifest, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildManifestList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      itemCount: _manifest.length,
      itemBuilder: (context, index) => _buildBookingCard(_manifest[index]),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> item) {
    final status = item['status'] as String? ?? 'as_scheduled';
    final statusLabel = item['statusLabel'] as String? ?? 'As Scheduled';
    final name = item['customerName'] ?? 'Unknown';
    final code = item['confirmationCode'] ?? '';
    final guests = item['guests'] ?? 1;
    final refundStatus = item['refundStatus'] as String?;
    final refundDocId = item['refundDocId'] as String?;
    final reviewedBy = item['reviewedBy'] as String?;
    final newDate = item['newDate'] as String?;
    final cancelReason = item['cancelReason'] as String?;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'as_scheduled':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'disrupted':
        statusColor = Colors.orange;
        statusIcon = Icons.warning_amber;
        break;
      case 'rescheduled':
        statusColor = Colors.blue;
        statusIcon = Icons.swap_horiz;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: statusColor.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Name + status badge
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      Row(
                        children: [
                          Text(
                            code,
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$guests ${guests == 1 ? "guest" : "guests"}',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),

            // Extra details for actions
            if (status == 'rescheduled' && newDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 28),
                child: Text(
                  '→ New date: $newDate',
                  style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                ),
              ),

            if (status == 'cancelled') ...[
              if (cancelReason != null && cancelReason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 28),
                  child: Text(
                    'Reason: $cancelReason',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              // Refund status
              _buildRefundBadge(refundStatus, reviewedBy),
              // Refund actions
              if (refundStatus == 'pending_review' && refundDocId != null)
                _buildRefundActions(refundDocId),
            ],

            // Admin action buttons for active bookings
            if (status == 'as_scheduled' || status == 'disrupted')
              _buildAdminActions(code, name),
          ],
        ),
      ),
    );
  }

  Widget _buildRefundBadge(String? refundStatus, String? reviewedBy) {
    if (refundStatus == null) return const SizedBox.shrink();

    Color color;
    String label;
    IconData icon;

    switch (refundStatus) {
      case 'refunded':
        color = Colors.green;
        label = reviewedBy != null ? 'Refunded by $reviewedBy' : 'Refunded';
        icon = Icons.check_circle;
        break;
      case 'no_refund':
        color = Colors.red;
        label = reviewedBy != null ? 'No refund — $reviewedBy' : 'No refund';
        icon = Icons.block;
        break;
      default:
        color = Colors.amber[700]!;
        label = 'Pending refund review';
        icon = Icons.hourglass_empty;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 28),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRefundActions(String docId) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 28),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: OutlinedButton.icon(
                onPressed: () => _confirmRefundAction(docId, 'refunded'),
                icon: const Icon(Icons.check_circle, size: 14),
                label: const Text('Refund', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                  side: const BorderSide(color: Colors.green),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 32,
              child: OutlinedButton.icon(
                onPressed: () => _confirmRefundAction(docId, 'no_refund'),
                icon: const Icon(Icons.block, size: 14),
                label: const Text('No Refund', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRefundAction(String docId, String status) {
    final actionLabel = status == 'refunded' ? 'refund' : 'mark as no refund';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm ${status == 'refunded' ? 'Refund' : 'No Refund'}'),
        content: Text('Are you sure you want to $actionLabel this booking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _markRefundStatus(docId, status);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: status == 'refunded' ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(status == 'refunded' ? 'Refund' : 'No Refund'),
          ),
        ],
      ),
    );
  }

  // ─── Admin action buttons for active bookings ─────────────────────
  Widget _buildAdminActions(String confirmationCode, String customerName) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 28),
      child: Row(
        children: [
          _buildSmallActionButton(
            icon: Icons.swap_horiz,
            label: 'Reschedule',
            color: Colors.blue,
            onTap: () => _adminReschedule(confirmationCode, customerName),
          ),
          const SizedBox(width: 6),
          _buildSmallActionButton(
            icon: Icons.cancel_outlined,
            label: 'Cancel',
            color: Colors.red,
            onTap: () => _adminCancel(confirmationCode, customerName),
          ),
          const SizedBox(width: 6),
          _buildSmallActionButton(
            icon: Icons.location_on_outlined,
            label: 'Pickup',
            color: Colors.teal,
            onTap: () => _adminChangePickup(confirmationCode, customerName),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: SizedBox(
        height: 30,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 13),
          label: Text(label, style: const TextStyle(fontSize: 10)),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withOpacity(0.5)),
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }

  // ─── Admin Reschedule ──────────────────────────────────────────────
  Future<void> _adminReschedule(String code, String name) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked == null || !mounted) return;

    final newDate = DateFormat('yyyy-MM-dd').format(picked);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Reschedule'),
        content: Text('Reschedule $name ($code) to $newDate?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            child: const Text('Reschedule'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final res = await http.post(
        Uri.parse('$_apiBase/portalRescheduleBooking'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'confirmationCode': code, 'newDate': newDate}),
      );
      final data = jsonDecode(res.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['success'] == true ? 'Rescheduled to $newDate' : (data['error'] ?? 'Failed')),
          backgroundColor: data['success'] == true ? Colors.green : Colors.red,
        ));
        _loadManifest();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ─── Admin Cancel ──────────────────────────────────────────────────
  Future<void> _adminCancel(String code, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Cancellation'),
        content: Text('Cancel booking for $name ($code)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final res = await http.post(
        Uri.parse('$_apiBase/portalCancelBooking'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'confirmationCode': code, 'reason': 'Admin cancellation'}),
      );
      final data = jsonDecode(res.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['success'] == true ? 'Booking cancelled' : (data['error'] ?? 'Failed')),
          backgroundColor: data['success'] == true ? Colors.green : Colors.red,
        ));
        _loadManifest();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ─── Admin Change Pickup ───────────────────────────────────────────
  Future<void> _adminChangePickup(String code, String name) async {
    // First, lookup the booking to get productId
    try {
      final lookupRes = await http.post(
        Uri.parse('$_apiBase/portalLookupBooking'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'confirmationCode': code}),
      );
      final lookupData = jsonDecode(lookupRes.body);
      if (lookupData['success'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(lookupData['error'] ?? 'Could not look up booking'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }

      final productId = lookupData['booking']?['productId'];
      if (productId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not determine product for pickup change'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }

      // Get pickup places
      final placesRes = await http.post(
        Uri.parse('$_apiBase/portalGetPickupPlaces'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'confirmationCode': code, 'productId': '$productId'}),
      );
      final placesData = jsonDecode(placesRes.body);
      if (placesData['success'] != true || !mounted) return;

      final places = (placesData['pickupPlaces'] as List).cast<Map<String, dynamic>>();
      if (places.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No pickup places available'),
            backgroundColor: Colors.orange,
          ));
        }
        return;
      }

      // Show picker
      if (!mounted) return;
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Change Pickup — $name'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: places.length,
              itemBuilder: (_, i) {
                final p = places[i];
                return ListTile(
                  title: Text(p['title'] ?? ''),
                  subtitle: p['address'] != null && (p['address'] as String).isNotEmpty
                      ? Text(p['address'] as String, style: const TextStyle(fontSize: 12))
                      : null,
                  onTap: () => Navigator.pop(ctx, p),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ],
        ),
      );
      if (selected == null || !mounted) return;

      final res = await http.post(
        Uri.parse('$_apiBase/portalUpdatePickup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'confirmationCode': code,
          'pickupPlaceId': '${selected['id']}',
          'pickupPlaceName': selected['title'] ?? '',
        }),
      );
      final data = jsonDecode(res.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['success'] == true ? 'Pickup updated' : (data['error'] ?? 'Failed')),
          backgroundColor: data['success'] == true ? Colors.green : Colors.red,
        ));
        _loadManifest();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }
}
