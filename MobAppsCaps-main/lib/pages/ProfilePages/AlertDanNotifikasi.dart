import 'dart:async';

import 'package:flutter/material.dart';
import 'package:my_app/Services/ProfileService/NotifAlertService.dart';
import 'package:my_app/pages/ProfilePages/PopupNotif.dart';

class AlertDanNotifikasiPage extends StatefulWidget {
  const AlertDanNotifikasiPage({super.key});

  @override
  State<AlertDanNotifikasiPage> createState() => _AlertDanNotifikasiPageState();
}

class _AlertDanNotifikasiPageState extends State<AlertDanNotifikasiPage>
  with WidgetsBindingObserver {
  // ── Colour palette (same as ManajemenKolam) ──
  static const Color _textPrimary = Color(0xFF1F2937);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _muted = Color(0xFF9CA3AF);
  static const Color _primary = Color(0xFF2563EB);
  static const Color _background = Color(0xFFF9FAFB);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _danger = Color(0xFFEF4444);
  static const Color _success = Color(0xFF10B981);

  // Extra tones for this page
  static const Color _warning = Color(0xFFEA580C);
  static const Color _warningSurface = Color(0xFFFFF7ED);
  static const Color _dangerSurface = Color(0xFFFEF2F2);
  static const Color _primarySurface = Color(0xFFEFF6FF);
  static const Color _alertDescriptionText = Color(0xFF4B5563);
  static const Color _alertMetaText = Color(0xFF6B7280);

  static const String _overrideBaseUrl = NotifAlertService.baseUrl;
  static const int _maxAlertItems = 50;

  // ── Alert data ──
  List<_AlertData> _alerts = [];
  final Set<String> _resolvingAlertIds = <String>{};
  bool _isLoadingAlerts = true;
  bool _isBulkResolving = false;
  String? _alertErrorMessage;
  _AlertFeedMode _feedMode = _AlertFeedMode.active;
  Timer? _activePollingTimer;

  int get _unreadCount =>
      _alerts.where((a) => a.isUnread && a.state == _AlertState.active).length;

  int get _activeAlertCount =>
      _alerts.where((a) => a.state == _AlertState.active).length;

  String get _unreadBadgeLabel => _unreadCount > 999 ? '999+' : '$_unreadCount';

  String? get _resolvedOverrideBaseUrl =>
      _overrideBaseUrl.isEmpty ? null : _overrideBaseUrl;

  String get _feedTitle {
    switch (_feedMode) {
      case _AlertFeedMode.active:
        return 'Alert Aktif (Real-time)';
      case _AlertFeedMode.history24h:
        return 'Riwayat Alert (24 Jam)';
      case _AlertFeedMode.history7d:
        return 'Riwayat Alert (7 Hari)';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapInitialAlerts();
    });
    _startRealtimePolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activePollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_isLoadingAlerts &&
        (_alerts.isEmpty || _alertErrorMessage != null)) {
      _loadAlertsWithRetry(silent: true, maxAttempts: 3);
    }
  }

  void _startRealtimePolling() {
    _activePollingTimer?.cancel();
    _activePollingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _feedMode != _AlertFeedMode.active || _isLoadingAlerts) {
        return;
      }
      _loadAlertsWithRetry(silent: true, showError: false, maxAttempts: 2);
    });
  }

  Future<void> _bootstrapInitialAlerts() async {
    await _loadAlertsWithRetry(maxAttempts: 5);
  }

  Future<List<Map<String, dynamic>>> _fetchAlertsOnce() async {
    switch (_feedMode) {
      case _AlertFeedMode.active:
        return NotifAlertService.getActiveAlerts(
          overrideBaseUrl: _resolvedOverrideBaseUrl,
        );
      case _AlertFeedMode.history24h:
        return NotifAlertService.getAlertHistory(
          period: '24h',
          overrideBaseUrl: _resolvedOverrideBaseUrl,
        );
      case _AlertFeedMode.history7d:
        return NotifAlertService.getAlertHistory(
          period: '7d',
          overrideBaseUrl: _resolvedOverrideBaseUrl,
        );
    }
  }

  Future<bool> _loadAlertsWithRetry({
    bool silent = false,
    bool showError = true,
    int maxAttempts = 1,
    Duration retryDelay = const Duration(milliseconds: 700),
  }) async {
    if (!silent && mounted) {
      setState(() {
        _isLoadingAlerts = true;
        _alertErrorMessage = null;
      });
    }

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final rawAlerts = await _fetchAlertsOnce();

        final parsedAlerts = rawAlerts
            .map(
              (item) => _AlertData.fromApi(
                item,
                forceState: _feedMode == _AlertFeedMode.active
                    ? _AlertState.active
                    : null,
              ),
            )
            .toList()
          ..sort((a, b) => b.sortTime.compareTo(a.sortTime));

        final limitedAlerts = parsedAlerts.length > _maxAlertItems
            ? parsedAlerts.take(_maxAlertItems).toList()
            : parsedAlerts;

        if (!mounted) return false;

        setState(() {
          _alerts = limitedAlerts;
          _isLoadingAlerts = false;
          _alertErrorMessage = null;
        });

        return true;
      } catch (_) {
        if (attempt < maxAttempts) {
          await Future<void>.delayed(retryDelay);
          if (!mounted) return false;
          continue;
        }

        if (!mounted) return false;

        setState(() {
          _isLoadingAlerts = false;
          if (_alerts.isEmpty || !silent) {
            if (showError) {
              _alertErrorMessage =
                  'Gagal memuat alert. Tarik ke bawah untuk mencoba lagi.';
            }
          }
        });

        return false;
      }
    }

    return false;
  }

  Future<void> _changeFeedMode(_AlertFeedMode mode) async {
    if (_feedMode == mode) return;

    setState(() {
      _feedMode = mode;
      _alertErrorMessage = null;
    });

    await _loadAlertsWithRetry(maxAttempts: 2);
  }

  void _markAllRead() {
    setState(() {
      for (final a in _alerts) {
        a.isUnread = false;
      }
    });
  }

  Future<void> _clearAll() async {
    if (_isBulkResolving) return;

    setState(() => _isBulkResolving = true);

    try {
      await NotifAlertService.resolveAllAlerts(
        overrideBaseUrl: _resolvedOverrideBaseUrl,
      );

      if (!mounted) return;
      _showSnackBar('Semua alert aktif berhasil diselesaikan.');
      await _loadAlertsWithRetry(silent: true, showError: false, maxAttempts: 2);
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('Gagal menghapus semua alert aktif.');
    } finally {
      if (mounted) {
        setState(() => _isBulkResolving = false);
      }
    }
  }

  Future<void> _removeAlert(_AlertData alert) async {
    if (alert.state != _AlertState.active) {
      setState(() {
        _alerts.removeWhere((item) => item.id == alert.id);
      });
      return;
    }

    if (_resolvingAlertIds.contains(alert.id)) return;

    setState(() => _resolvingAlertIds.add(alert.id));

    try {
      await NotifAlertService.resolveAlert(
        alertId: alert.id,
        overrideBaseUrl: _resolvedOverrideBaseUrl,
      );

      if (!mounted) return;

      setState(() {
        _alerts.removeWhere((item) => item.id == alert.id);
        _resolvingAlertIds.remove(alert.id);
      });

      _showSnackBar('Alert berhasil diselesaikan.');
    } catch (_) {
      if (!mounted) return;

      setState(() => _resolvingAlertIds.remove(alert.id));
      _showSnackBar('Gagal menyelesaikan alert.');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _loadAlertsWithRetry(
                    silent: true,
                    showError: false,
                    maxAttempts: 3,
                  ),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 4),

                      // ── Riwayat Alert ──
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _feedTitle,
                                        style: const TextStyle(
                                          color: _textPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (_unreadCount > 0) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _danger,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          _unreadBadgeLabel,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  height: 34,
                                  child: OutlinedButton.icon(
                                    onPressed:
                                        _unreadCount > 0 ? _markAllRead : null,
                                    icon: const Icon(
                                      Icons.mark_email_read_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Tandai Dibaca'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _primary,
                                      textStyle: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      side: BorderSide(
                                        color: _primary.withOpacity(0.35),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: 34,
                                  child: FilledButton.icon(
                                    onPressed: _activeAlertCount > 0 &&
                                            !_isBulkResolving
                                        ? _clearAll
                                        : null,
                                    icon: _isBulkResolving
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.delete_sweep_outlined,
                                            size: 16,
                                          ),
                                    label: Text(
                                      _isBulkResolving
                                          ? 'Memproses...'
                                          : 'Hapus Semua',
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _danger,
                                      foregroundColor: Colors.white,
                                      textStyle: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildModeChip(
                            label: 'Aktif',
                            mode: _AlertFeedMode.active,
                          ),
                          _buildModeChip(
                            label: '24 Jam',
                            mode: _AlertFeedMode.history24h,
                          ),
                          _buildModeChip(
                            label: '7 Hari',
                            mode: _AlertFeedMode.history7d,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      if (_isLoadingAlerts)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        ),

                      if (!_isLoadingAlerts &&
                          _alertErrorMessage != null &&
                          _alerts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _border),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: _danger,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _alertErrorMessage!,
                                    style: const TextStyle(
                                      color: _textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _loadAlertsWithRetry(),
                                  child: const Text('Coba lagi'),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Alert cards
                      if (!_isLoadingAlerts)
                        ..._alerts.map((alert) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildAlertCard(alert),
                          );
                        }),

                      if (!_isLoadingAlerts &&
                          _alerts.isEmpty &&
                          _alertErrorMessage == null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              _feedMode == _AlertFeedMode.active
                                  ? 'Tidak ada alert aktif'
                                  : 'Tidak ada data histori alert',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──
  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new,
              size: 18,
              color: _textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notifikasi & Alert',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Peringatan Sistem',
                style: TextStyle(color: _textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PopupNotifPage()),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: const Icon(
              Icons.notifications,
              size: 20,
              color: _primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeChip({required String label, required _AlertFeedMode mode}) {
    final bool selected = _feedMode == mode;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: _primary.withOpacity(0.16),
      side: BorderSide(color: selected ? _primary : _border),
      labelStyle: TextStyle(
        color: selected ? _primary : _textSecondary,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) => _changeFeedMode(mode),
    );
  }

  // ── Alert card ──
  Widget _buildAlertCard(_AlertData alert) {
    final bool isActive = alert.state == _AlertState.active;
    final bool isResolving = _resolvingAlertIds.contains(alert.id);
    final bool isCritical = alert.severity == _AlertSeverity.critical;
    final Color accentColor =
        isActive ? _danger : (isCritical ? _warning : _primary);
    final Color cardBg = isActive
        ? _dangerSurface
        : (alert.severity == _AlertSeverity.warning
            ? _warningSurface
            : _primarySurface);
    final Color iconBg =
        isActive ? _danger.withOpacity(0.15) : accentColor.withOpacity(0.15);
    final IconData iconData = isActive
        ? Icons.warning_amber_rounded
        : (alert.severity == _AlertSeverity.warning
            ? Icons.info_outline_rounded
            : Icons.check_circle_outline_rounded);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: iconBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(iconData, size: 18, color: accentColor),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  alert.title,
                                  style: const TextStyle(
                                    color: _textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (alert.isUnread && isActive)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: _danger,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (isActive)
                          GestureDetector(
                            onTap: () => _removeAlert(alert),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: isResolving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.close,
                                      size: 18,
                                      color: _danger,
                                    ),
                            ),
                          ),
                        if (!isActive)
                          const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.check_circle,
                              size: 18,
                              color: _success,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 42),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? _danger.withOpacity(0.12)
                                : _success.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isActive ? 'Aktif' : 'Resolved',
                            style: TextStyle(
                              color: isActive ? _danger : _success,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 42),
                      child: Text(
                        alert.description,
                        style: const TextStyle(
                          color: _alertDescriptionText,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 42),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? _danger.withOpacity(0.12)
                                  : _primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              alert.tag,
                              style: TextStyle(
                                color: isActive ? _danger : _primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.circle,
                            size: 4,
                            color: _alertMetaText,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            alert.timeAgo,
                            style: const TextStyle(
                              color: _alertMetaText,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Models ──
enum _AlertSeverity { critical, warning, info }

enum _AlertState { active, resolved }

enum _AlertFeedMode { active, history24h, history7d }

class _AlertData {
  _AlertData({
    required this.id,
    required this.title,
    required this.description,
    required this.tag,
    required this.timeAgo,
    required this.sortTime,
    required this.state,
    required this.isUnread,
    required this.severity,
  });

  factory _AlertData.fromApi(
    Map<String, dynamic> raw, {
    _AlertState? forceState,
  }) {
    final normalized = raw.map((key, value) => MapEntry(key.toString(), value));

    final state = forceState ?? _resolveState(normalized);
    final title = _readString(
      normalized,
      ['title', 'alert_title', 'name', 'type', 'category'],
      fallback: 'Alert Sistem',
    );
    final description = _readString(
      normalized,
      ['description', 'detail', 'message', 'body', 'reason'],
      fallback: 'Detail alert tidak tersedia',
    );
    final tag = _readString(
      normalized,
      ['tag', 'pond_name', 'pond_id', 'source', 'device_id'],
      fallback: 'Sistem',
    );
    final occurredAt = _readDate(
      normalized,
      ['occurred_at', 'created_at', 'timestamp', 'time', 'updated_at'],
    );
    final resolvedAt = _readDate(normalized, ['resolved_at']);
    final eventTime = resolvedAt ?? occurredAt;
    final sortTime = eventTime ?? DateTime.now();
    final timeAgo = eventTime == null ? 'Baru saja' : _formatTimeAgo(eventTime);
    final id = _readString(
      normalized,
      ['id', 'alert_id', 'uuid'],
      fallback: '${title}_${description}_${sortTime.millisecondsSinceEpoch}',
    );

    return _AlertData(
      id: id,
      title: title,
      description: description,
      tag: tag,
      timeAgo: timeAgo,
      sortTime: sortTime,
      state: state,
      isUnread: state == _AlertState.active,
      severity: _resolveSeverity(normalized, title, description, state),
    );
  }

  static _AlertState _resolveState(Map<String, dynamic> source) {
    final value = _readString(source, ['state', 'status'], fallback: '');
    final normalizedValue = value.toLowerCase();

    if (normalizedValue == 'resolved' || normalizedValue == 'dismissed') {
      return _AlertState.resolved;
    }

    if (normalizedValue == 'active') {
      return _AlertState.active;
    }

    if (source['resolved_at'] != null ||
        source['is_resolved'] == true ||
        source['is_active'] == false) {
      return _AlertState.resolved;
    }

    return _AlertState.active;
  }

  static _AlertSeverity _resolveSeverity(
    Map<String, dynamic> source,
    String title,
    String description,
    _AlertState state,
  ) {
    final level = _readString(
      source,
      ['severity', 'level', 'priority'],
      fallback: '',
    ).toLowerCase();

    if (level.contains('critical') ||
        level.contains('high') ||
        level.contains('danger')) {
      return _AlertSeverity.critical;
    }

    if (level.contains('warning') ||
        level.contains('warn') ||
        level.contains('medium')) {
      return _AlertSeverity.warning;
    }

    if (state == _AlertState.active) {
      return _AlertSeverity.critical;
    }

    final text = '$title $description'.toLowerCase();
    if (text.contains('stok') ||
        text.contains('jadwal') ||
        text.contains('pakan')) {
      return _AlertSeverity.warning;
    }

    return _AlertSeverity.info;
  }

  static String _readString(
    Map<String, dynamic> source,
    List<String> keys, {
    required String fallback,
  }) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') {
        continue;
      }
      return text;
    }

    return fallback;
  }

  static DateTime? _readDate(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') {
        continue;
      }

      final parsed = DateTime.tryParse(text);
      if (parsed != null) {
        return parsed.toLocal();
      }
    }

    return null;
  }

  static String _formatTimeAgo(DateTime value) {
    final now = DateTime.now();
    final difference = now.difference(value);

    if (difference.isNegative || difference.inMinutes < 1) {
      return 'Baru saja';
    }

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} Menit Lalu';
    }

    if (difference.inHours < 24) {
      return '${difference.inHours} Jam Lalu';
    }

    if (difference.inDays < 7) {
      return '${difference.inDays} Hari Lalu';
    }

    if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()} Minggu Lalu';
    }

    return '${(difference.inDays / 30).floor()} Bulan Lalu';
  }

  final String id;
  final String title;
  final String description;
  final String tag;
  final String timeAgo;
  final DateTime sortTime;
  final _AlertState state;
  bool isUnread;
  final _AlertSeverity severity;
}
