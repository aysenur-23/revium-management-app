/// Fuarlar sayfası: Google Sheet'ten liste, website linki, bildirim izni
library;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/fuar.dart';
import '../services/google_sheets_service.dart';
import '../services/firestore_service.dart';
import '../services/upload_service.dart' show getBackendBaseUrl;
import '../utils/app_logger.dart';

/// yyyy-MM-dd → gg.aa.yyyy (gün/ay/yıl)
String _formatFuarTarih(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) return '';
  final parts = isoDate.split('-');
  if (parts.length != 3) return isoDate;
  final y = parts[0];
  final m = parts[1];
  final d = parts[2];
  return '$d.$m.$y';
}

class FuarlarScreen extends StatefulWidget {
  const FuarlarScreen({super.key});

  @override
  State<FuarlarScreen> createState() => _FuarlarScreenState();
}

class _FuarlarScreenState extends State<FuarlarScreen> {
  List<Fuar> _fuarlar = [];
  bool _loading = true;
  String? _error;
  bool _permissionRequested = false;

  @override
  void initState() {
    super.initState();
    _requestNotificationPermissionAndSaveToken();
    _loadFuarlar();
  }

  /// İlk açılışta bildirim izni iste; verilirse token'ı Firestore'a yaz
  /// Android 13+ için önce sistem POST_NOTIFICATIONS izni istenir (permission_handler).
  Future<void> _requestNotificationPermissionAndSaveToken() async {
    if (_permissionRequested) return;
    if (kIsWeb) return; // Web'de FCM farklı yapılandırma gerektirir
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _permissionRequested = true;
    try {
      // Android 13+: Sistem bildirim iznini açıkça iste (FCM'nin göstermediği durumları önler)
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.notification.status;
        AppLogger.info('Bildirim izni durumu: $status');
        if (!status.isGranted) {
          final result = await Permission.notification.request();
          AppLogger.info('Bildirim izni isteği sonucu: $result');
          if (!result.isGranted && !result.isPermanentlyDenied) return;
        }
      }
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      AppLogger.info('FCM izin durumu: ${settings.authorizationStatus}');
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          await FirestoreService.updateUserFcmToken(user.uid, token);
          AppLogger.info('FCM token Firestore\'a kaydedildi');
        } else {
          AppLogger.warning('FCM token alınamadı (null veya boş)');
        }
      } else {
        AppLogger.warning('Bildirim izni verilmedi: ${settings.authorizationStatus}');
      }
    } catch (e) {
      AppLogger.warning('Bildirim izni/token hatası: $e');
    }
  }

  Future<void> _loadFuarlar() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await GoogleSheetsService.getFuarlar();
      if (!mounted) return;
      setState(() {
        _fuarlar = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is Exception ? e.toString() : e.toString();
        _loading = false;
      });
    }
  }



  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Link açılamadı: $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Fuarlar', style: TextStyle(fontWeight: FontWeight.w600)),
        elevation: 0,
        scrolledUnderElevation: 2,
        actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _loadFuarlar,
          tooltip: 'Yenile',
        ),
      ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text('Fuarlar yükleniyor...', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 56, color: colorScheme.error),
              const SizedBox(height: 20),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _loadFuarlar,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tekrar dene'),
              ),
            ],
          ),
        ),
      );
    }
    if (_fuarlar.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.event_busy_rounded, size: 56, color: colorScheme.outline),
              ),
              const SizedBox(height: 24),
              Text(
                'Henüz fuar kaydı yok',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Fuarlar Google Sheet\'inde 2. satırdan itibaren veri olduğundan ve dosyanın "Linki olan herkes görüntüleyebilir" ile paylaşıldığından emin olun.',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadFuarlar,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Yenile'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFuarlar,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '${_fuarlar.length} fuar',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '20, 10 ve 7 gün kala bildirim',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final f = _fuarlar[index];
                  return _buildFuarCard(context, f, theme, colorScheme);
                },
                childCount: _fuarlar.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFuarCard(BuildContext context, Fuar f, ThemeData theme, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: f.website != null && f.website!.isNotEmpty ? () => _openUrl(f.website!) : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.event_rounded, size: 18, color: colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.fuarAdi,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          if (f.yer.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.location_on_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  f.yer,
                                  style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ],
                          if (f.tarih != null || f.bitisTarih != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.calendar_today_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  f.bitisTarih != null && f.bitisTarih != f.tarih
                                      ? '${_formatFuarTarih(f.tarih)} – ${_formatFuarTarih(f.bitisTarih)}'
                                      : _formatFuarTarih(f.tarih ?? f.bitisTarih),
                                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (f.website != null && f.website!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.open_in_new_rounded, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Web sitesine git',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
