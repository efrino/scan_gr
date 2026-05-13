import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/api_client.dart';
import '../../core/services/pending_scan_service.dart';
import '../../shared/widgets/app_drawer.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _nik = '';
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  DateTimeRange? _selectedDateRange;
  List<Map<String, dynamic>> _history = [];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final prefs = await SharedPreferences.getInstance();
    _nik = prefs.getString('nik') ?? prefs.getString('email') ?? '';
    // Coba kirim pending sebelum menampilkan riwayat
    await PendingScanService.syncAll();
    await _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}/scan/history',
      ).replace(queryParameters: {'nik': _nik});

      debugPrint('[HistoryPage] GET → $uri');
      debugPrint('[HistoryPage]   nik: $_nik');

      final response = await ApiClient.get(uri);
      debugPrint('[HistoryPage] GET ← ${response.statusCode}');
      debugPrint('[HistoryPage]   body: ${response.body}');

      final data = jsonDecode(response.body);
      if (data['status'] == true && data['data'] is List) {
        final apiItems = List<Map<String, dynamic>>.from(data['data']);
        debugPrint('[HistoryPage] ✓ ${apiItems.length} item dari server');

        // Merge dengan pending cache lokal
        final pending = await PendingScanService.getAll();
        final pendingBarcodes = pending
            .map((e) => e['barcode'] as String? ?? '')
            .toSet();
        final apiLabels = apiItems
            .map((e) => e['id_box_label']?.toString() ?? '')
            .toSet();

        // Tandai API items yang juga ada di cache (sedang dalam antrian)
        final merged = apiItems.map((item) {
          final label = item['id_box_label']?.toString() ?? '';
          if (pendingBarcodes.contains(label)) {
            return Map<String, dynamic>.from(item)..['is_pending'] = true;
          }
          return item;
        }).toList();

        // Tambahkan pending items yang belum muncul di API (edge case)
        for (final p in pending) {
          final barcode = p['barcode'] as String? ?? '';
          if (!apiLabels.contains(barcode)) {
            merged.add(Map<String, dynamic>.from(p));
          }
        }

        debugPrint(
          '[HistoryPage] total setelah merge: ${merged.length} item (pending cache: ${pending.length})',
        );

        setState(() {
          _history = merged;
          _isLoading = false;
        });
      } else {
        debugPrint('[HistoryPage] ✗ status bukan true atau data bukan list');
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage =
              data['message']?.toString() ?? 'Gagal memuat riwayat scan';
        });
      }
    } on UnauthorizedException {
      debugPrint('[HistoryPage] ✗ 401 Unauthorized – sudah redirect ke login');
      // Sesi tidak valid — ApiClient sudah redirect ke login
      return;
    } on ApiResponseException catch (e) {
      debugPrint('[HistoryPage] ✗ Server return non-JSON HTTP ${e.statusCode}');
      debugPrint(
        '[HistoryPage]   Kemungkinan endpoint salah atau server error',
      );
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage =
            'Endpoint tidak ditemukan di server (HTTP ${e.statusCode}).\nCek konfigurasi API.';
      });
    } catch (e) {
      debugPrint('[HistoryPage] ✗ Error: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Gagal koneksi ke server';
      });
    }
  }

  // ── Filter helpers ────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _filtered {
    var list = _history.toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((item) {
        final supplier = item['supplier_name']?.toString().toLowerCase() ?? '';
        final po = item['no_po']?.toString().toLowerCase() ?? '';
        final material = item['material']?.toString().toLowerCase() ?? '';
        final idLabel = item['id_box_label']?.toString().toLowerCase() ?? '';
        final dn = item['id_delivery']?.toString().toLowerCase() ?? '';
        
        return supplier.contains(q) ||
            po.contains(q) ||
            material.contains(q) ||
            idLabel.contains(q) ||
            dn.contains(q);
      }).toList();
    }

    if (_selectedDateRange != null) {
      list = list.where((item) {
        final raw = item['delivery_date']?.toString() ?? '';
        try {
          final d = DateTime.parse(raw);
          final date = DateTime(d.year, d.month, d.day);
          final start = DateTime(
            _selectedDateRange!.start.year,
            _selectedDateRange!.start.month,
            _selectedDateRange!.start.day,
          );
          final end = DateTime(
            _selectedDateRange!.end.year,
            _selectedDateRange!.end.month,
            _selectedDateRange!.end.day,
          );
          return !date.isBefore(start) && !date.isAfter(end);
        } catch (_) {
          return true;
        }
      }).toList();
    }

    return list;
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _selectedDateRange,
    );
    if (picked != null) setState(() => _selectedDateRange = picked);
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  String _fmtDateStr(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      final d = DateTime.parse(raw);
      return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
    } catch (_) {
      return raw;
    }
  }

  String _fmtDateTimeStr(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      final d = DateTime.parse(raw);
      return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        title: const Text(
          'Riwayat Scan',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.red, Colors.blue],
              stops: [0.33, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
          ? _buildError()
          : Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildList()),
              ],
            ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: Colors.red.shade400,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header with summary + filter ──────────────────────────────────────────

  Widget _buildHeader() {
    final data = _filtered;
    final total = data.length;
    final sudah = data.where((e) => e['is_scanned'] == 'Y').length;
    final pending = data.where((e) => e['is_pending'] == true).length;
    final belum = total - sudah;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Summary cards
          Row(
            children: [
              _SummaryCard(
                label: 'Total',
                value: total.toString(),
                color: Colors.blue,
                icon: Icons.list_alt_rounded,
              ),
              const SizedBox(width: 8),
              _SummaryCard(
                label: 'Sudah Scan',
                value: sudah.toString(),
                color: Colors.green,
                icon: Icons.check_circle_rounded,
              ),
              const SizedBox(width: 8),
              _SummaryCard(
                label: 'Belum Scan',
                value: belum.toString(),
                color: Colors.orange,
                icon: Icons.pending_actions_rounded,
              ),
              if (pending > 0) ...[
                const SizedBox(width: 8),
                _SummaryCard(
                  label: 'Pending',
                  value: pending.toString(),
                  color: Colors.blueGrey,
                  icon: Icons.cloud_off_rounded,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Search & Date filter
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Cari PO, Supplier, DN, dll...',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade400, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty 
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.blue.shade400),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: _selectedDateRange != null ? Colors.blue.shade50 : Colors.transparent,
                  border: Border.all(
                    color: _selectedDateRange != null ? Colors.blue.shade300 : Colors.grey.shade300,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  onPressed: _selectDateRange,
                  icon: Icon(
                    _selectedDateRange != null ? Icons.filter_alt_rounded : Icons.calendar_month_rounded,
                    color: _selectedDateRange != null ? Colors.blue.shade700 : Colors.grey.shade600,
                    size: 20,
                  ),
                  tooltip: 'Filter Tanggal',
                ),
              ),
              if (_selectedDateRange != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.red, size: 20),
                  onPressed: () => setState(() => _selectedDateRange = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Hapus Filter Tanggal',
                ),
              ],
            ],
          ),
          if (_selectedDateRange != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Tgl Delivery: ${_fmtDate(_selectedDateRange!.start)} – ${_fmtDate(_selectedDateRange!.end)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── List ──────────────────────────────────────────────────────────────────

  Widget _buildList() {
    final data = _filtered;

    if (data.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Belum ada riwayat scan',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: data.length,
        itemBuilder: (context, index) {
          return _HistoryCard(
            item: data[index],
            fmtDate: _fmtDateStr,
            fmtDateTime: _fmtDateTimeStr,
            onTap: () => _showDetailModal(context, data[index]),
          );
        },
      ),
    );
  }

  // ── Detail modal ──────────────────────────────────────────────────────────

  void _showDetailModal(BuildContext context, Map<String, dynamic> item) {
    final isScanned = item['is_scanned'] == 'Y';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isScanned
                              ? [Colors.green.shade400, Colors.teal.shade500]
                              : [Colors.orange.shade400, Colors.red.shade400],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isScanned
                            ? Icons.check_circle_rounded
                            : Icons.qr_code_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Detail Riwayat',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isScanned
                                  ? Colors.green.shade50
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isScanned
                                    ? Colors.green.shade200
                                    : Colors.orange.shade200,
                              ),
                            ),
                            child: Text(
                              isScanned ? 'Sudah Discan' : 'Belum Discan',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isScanned
                                    ? Colors.green.shade700
                                    : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                Divider(color: Colors.grey.shade200),
                const SizedBox(height: 8),

                // Detail rows
                _DetailSection(title: 'Informasi Label'),
                _DetailRow(
                  icon: Icons.label_rounded,
                  iconColor: Colors.blue,
                  label: 'ID Box Label',
                  value: item['id_box_label'],
                  mono: true,
                ),
                _DetailRow(
                  icon: Icons.local_shipping_rounded,
                  iconColor: Colors.indigo,
                  label: 'No. DN',
                  value: item['id_delivery'],
                  mono: true,
                ),
                _DetailRow(
                  icon: Icons.receipt_long_rounded,
                  iconColor: Colors.purple,
                  label: 'No. PO',
                  value: item['no_po'],
                ),
                _DetailRow(
                  icon: Icons.person_rounded,
                  iconColor: Colors.purple,
                  label: 'Supplier',
                  value: item['supplier_name'],
                ),

                const SizedBox(height: 12),
                _DetailSection(title: 'Informasi Material'),
                _DetailRow(
                  icon: Icons.category_rounded,
                  iconColor: Colors.teal,
                  label: 'Material / Part No.',
                  value: item['material'],
                  mono: true,
                ),
                _DetailRow(
                  icon: Icons.description_rounded,
                  iconColor: Colors.cyan,
                  label: 'Deskripsi Part',
                  value: item['part_desc'],
                ),
                _DetailRow(
                  icon: Icons.inventory_2_rounded,
                  iconColor: Colors.orange,
                  label: 'Quantity',
                  value: item['quantity'] != null
                      ? '${item['quantity']} pcs'
                      : null,
                ),
                _DetailRow(
                  icon: Icons.calendar_today_rounded,
                  iconColor: Colors.green,
                  label: 'Delivery Date',
                  value: _fmtDateStr(item['delivery_date']?.toString()),
                ),

                const SizedBox(height: 12),
                _DetailSection(title: 'Informasi Scan'),
                _DetailRow(
                  icon: Icons.qr_code_scanner_rounded,
                  iconColor: Colors.blue,
                  label: 'Status Scan',
                  value: isScanned ? 'Sudah Discan' : 'Belum Discan',
                  valueColor: isScanned
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                  valueBold: true,
                ),
                if (isScanned) ...[
                  _DetailRow(
                    icon: Icons.person_rounded,
                    iconColor: Colors.purple,
                    label: 'Discan Oleh',
                    value: item['scanned_by'],
                  ),
                  _DetailRow(
                    icon: Icons.access_time_rounded,
                    iconColor: Colors.teal,
                    label: 'Tanggal Scan',
                    value: _fmtDateTimeStr(item['date_scanned']?.toString()),
                  ),
                ],
                _DetailRow(
                  icon: Icons.add_circle_outline_rounded,
                  iconColor: Colors.grey,
                  label: 'Dibuat',
                  value: _fmtDateTimeStr(item['created_at']?.toString()),
                ),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      'Tutup',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Summary Card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── History Card ─────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String Function(String?) fmtDate;
  final String Function(String?) fmtDateTime;
  final VoidCallback onTap;

  const _HistoryCard({
    required this.item,
    required this.fmtDate,
    required this.fmtDateTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isScanned = item['is_scanned'] == 'Y';
    final isPending = item['is_pending'] == true;
    final accentColor = isPending
        ? Colors.blueGrey
        : isScanned
        ? Colors.green
        : Colors.orange;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Left accent bar
              Container(
                width: 5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isScanned
                        ? [Colors.green.shade400, Colors.teal.shade400]
                        : [Colors.orange.shade400, Colors.red.shade300],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: material + badge
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item['material']?.toString() ?? '-',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: accentColor.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isScanned
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 11,
                                  color: accentColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isScanned ? 'Scanned' : 'Pending',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      // ID box label
                      Text(
                        item['id_box_label']?.toString() ?? '-',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.grey.shade500,
                          letterSpacing: 0.3,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Info chips row
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _InfoChip(
                            icon: Icons.inventory_2_rounded,
                            text: '${item['quantity'] ?? '-'} pcs',
                            color: Colors.orange.shade700,
                          ),
                          _InfoChip(
                            icon: Icons.receipt_long_rounded,
                            text: 'PO: ${item['no_po'] ?? '-'}',
                            color: Colors.blue.shade700,
                          ),
                          _InfoChip(
                            icon: Icons.local_shipping_rounded,
                            text: 'DN: ${item['id_delivery']?.toString()}',
                            color: Colors.indigo,
                          ),
                        ],
                      ),

                      // Scanned info
                      if (isScanned) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_rounded,
                                size: 13,
                                color: Colors.green.shade600,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  item['supplier_name']?.toString() ?? '-',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.access_time_rounded,
                                size: 13,
                                color: Colors.green.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                fmtDateTime(item['date_scanned']?.toString()),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Arrow
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Info Chip ────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Detail Modal Widgets ─────────────────────────────────────────────────────

class _DetailSection extends StatelessWidget {
  final String title;
  const _DetailSection({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? value;
  final bool mono;
  final Color? valueColor;
  final bool valueBold;

  const _DetailRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.value,
    this.mono = false,
    this.valueColor,
    this.valueBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  (value == null || value!.isEmpty) ? '-' : value!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
                    color: valueColor ?? Colors.black87,
                    fontFamily: mono ? 'monospace' : null,
                    letterSpacing: mono ? 0.3 : 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
