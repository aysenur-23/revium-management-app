import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import '../models/expense_entry.dart';
import '../models/app_file_reference.dart';
import '../utils/app_logger.dart';
import '../services/upload_service.dart';
import '../services/file_opener/file_open_service.dart';

class EntryCard extends StatefulWidget {
  final ExpenseEntry entry;
  final VoidCallback? onDelete; // Silme callback'i (opsiyonel)
  final bool showOwnerIcon; // Kişi ikonunu göster/gizle

  const EntryCard({
    super.key,
    required this.entry,
    this.onDelete,
    this.showOwnerIcon = true, // Varsayılan olarak göster
  });

  @override
  State<EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<EntryCard> {
  bool _showDetails = false; // Detaylar gösteriliyor mu?

  void _handleTap() {
    // Kartta tıklayınca direkt dosyayı aç
    _openFile(context);
  }
  
  void _handleLongPress() {
    // Uzun basınca detayları göster/gizle
    setState(() {
      _showDetails = !_showDetails;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Web'de locale data yüklenmemiş olabilir, güvenli formatlama
    DateFormat dateFormat;
    try {
      dateFormat = DateFormat('dd.MM.yyyy HH:mm', kIsWeb ? null : 'tr_TR');
    } catch (e) {
      // Locale data yüklenmemişse varsayılan format kullan
      dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    }

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 1),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Stack(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _handleTap,
                onLongPress: _handleLongPress,
                borderRadius: BorderRadius.circular(16),
                splashColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                highlightColor: theme.colorScheme.primary.withValues(alpha: 0.05),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Üst kısım: İkon, Açıklama, Miktar
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Dosya tipi ikonu - kompakt boyut
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          widget.entry.fileType == 'pdf'
                              ? Icons.picture_as_pdf_rounded
                              : Icons.image_rounded,
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                    // Açıklama ve tarih - Expanded ile overflow önleniyor
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.entry.description,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              letterSpacing: -0.2,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          // Tarih ve kişi - tek satırda, daha kompakt
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    size: 12,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      widget.entry.createdAt != null
                                          ? DateFormat('dd.MM.yyyy', kIsWeb ? null : 'tr_TR').format(widget.entry.createdAt!)
                                          : 'Tarih yok',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.person_outline_rounded,
                                    size: 12,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      widget.entry.ownerName,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Miktar badge - kompakt
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          NumberFormat.currency(
                            symbol: '₺',
                            decimalDigits: 0,
                            locale: 'tr_TR',
                          ).format(widget.entry.amount),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 0,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    ],
                  ),
                  // Detaylı bilgiler - sadece _showDetails true ise göster
                  if (_showDetails) ...[
                    const SizedBox(height: 12),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: theme.colorScheme.outline.withValues(alpha: 0.08),
                    ),
                    const SizedBox(height: 12),
                    // Tarih/Saat detayı
                    if (widget.entry.createdAt != null)
                      _DetailRow(
                        icon: Icons.calendar_today_rounded,
                        label: 'Tarih/Saat',
                        value: dateFormat.format(widget.entry.createdAt!),
                        iconColor: theme.colorScheme.primary,
                      ),
                    // Notlar - varsa göster
                    if (widget.entry.notes != null && widget.entry.notes!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _DetailRow(
                        icon: Icons.note_rounded,
                        label: 'Notlar',
                        value: widget.entry.notes!,
                        iconColor: theme.colorScheme.secondary,
                        maxLines: 3,
                      ),
                    ],
                    // Bilgilendirme mesajı
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Karta tıklayarak belgeyi açabilirsiniz',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
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
            ),
            // Silme butonu - Stack'in üstünde, sağ üst köşede
            if (widget.onDelete != null)
              Positioned(
                top: 8,
                right: 8,
                child: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    size: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (value) {
                    if (value == 'delete' && widget.onDelete != null) {
                      widget.onDelete!();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                          SizedBox(width: 12),
                          Text('Sil'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Google Drive URL'den File ID çıkarır
  String? _extractFileIdFromUrl(String url) {
    if (url.isEmpty) return null;
    
    // Format 1: /file/d/FILE_ID/view veya /file/d/FILE_ID
    final fileIdMatch1 = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    if (fileIdMatch1 != null) {
      return fileIdMatch1.group(1);
    }
    
    // Format 2: id=FILE_ID
    final fileIdMatch2 = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(url);
    if (fileIdMatch2 != null) {
      return fileIdMatch2.group(1);
    }
    
    return null;
  }

  /// Dosyayı açar (yeni modüler servis kullanarak)
  Future<void> _openFile(BuildContext context) async {
    try {
      AppLogger.info('📄 Dosya açma işlemi başlatıldı');
      AppLogger.debug('Dosya tipi: ${widget.entry.fileType}');
      AppLogger.debug('Dosya URL: ${widget.entry.fileUrl}');
      AppLogger.debug('Drive File ID: ${widget.entry.driveFileId}');
      
      if (widget.entry.fileUrl.isEmpty) {
        AppLogger.warning('Dosya URL\'i boş');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Dosya bilgisi bulunamadı'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // File ID'yi belirle (driveFileId varsa onu kullan, yoksa URL'den çıkar)
      String? fileId = widget.entry.driveFileId.isNotEmpty 
          ? widget.entry.driveFileId 
          : _extractFileIdFromUrl(widget.entry.fileUrl);
      
      if (fileId == null || fileId.isEmpty) {
        AppLogger.warning('File ID bulunamadı (URL: ${widget.entry.fileUrl})');
        // Son çare: URL'i direkt aç
        try {
          final uri = Uri.parse(widget.entry.fileUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            AppLogger.info('Dosya URL direkt açıldı');
            return;
          }
        } catch (e) {
          AppLogger.error('URL açma hatası', e);
        }
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Dosya bilgisi bulunamadı'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      AppLogger.debug('Kullanılacak File ID: $fileId');
      AppLogger.info('📎 Entry ID: ${widget.entry.id}');
      AppLogger.info('📎 Entry Açıklama: ${widget.entry.description}');
      AppLogger.info('📎 Entry Tutar: ${widget.entry.amount}');

      // Loading göster
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('Dosya yükleniyor...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // AppFileReference oluştur (fileId'yi kullan)
      final fileRef = AppFileReference.fromExpenseEntry(
        entryId: widget.entry.id ?? '',
        driveFileId: fileId, // Çıkarılan veya mevcut fileId
        fileUrl: widget.entry.fileUrl,
        fileType: widget.entry.fileType,
        ownerId: widget.entry.ownerId,
        mimeType: widget.entry.mimeType, // Yeni alan
        fileName: widget.entry.fileName, // Yeni alan
      );

      AppLogger.info('📎 Oluşturulan FileRef:');
      AppLogger.info('   - ID: ${fileRef.id}');
      AppLogger.info('   - Drive File ID: ${fileRef.driveFileId}');
      AppLogger.info('   - Name: ${fileRef.name}');
      AppLogger.info('   - MIME Type: ${fileRef.mimeType}');
      AppLogger.info('   - File Type Category: ${fileRef.fileTypeCategory}');

      // Yeni modüler servis ile aç
      await FileOpenService.openOrDownloadAndOpen(fileRef);

      // Loading'i kapat
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      AppLogger.error('Dosya açma hatası', e);
      // Loading'i kapat
      if (context.mounted) {
        Navigator.of(context).pop();
        
        // Kullanıcıya açıklayıcı hata mesajı göster
        String errorMessage = 'Dosya açılamadı';
        final errorString = e.toString().toLowerCase();
        
        if (errorString.contains('timeout') || errorString.contains('zaman aşımı')) {
          errorMessage = 'Dosya yüklenirken zaman aşımı oluştu. İnternet bağlantınızı kontrol edip tekrar deneyin.';
        } else if (errorString.contains('connection') || errorString.contains('bağlanılamadı')) {
          errorMessage = 'Backend sunucusuna bağlanılamıyor. İnternet bağlantınızı kontrol edin.';
        } else if (errorString.contains('404') || errorString.contains('not found')) {
          errorMessage = 'Dosya bulunamadı. Dosya silinmiş olabilir.';
        } else if (errorString.contains('401') || errorString.contains('403') || errorString.contains('unauthorized')) {
          errorMessage = 'Yetkilendirme hatası. Lütfen tekrar giriş yapın.';
        } else {
          errorMessage = 'Dosya açılamadı: ${e.toString().length > 100 ? e.toString().substring(0, 100) + "..." : e.toString()}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }



}

/// Detay satırı widget'ı
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final int maxLines;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: iconColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  height: 1.4,
                ),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
