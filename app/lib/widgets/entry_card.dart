import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/expense_entry.dart';
import '../models/app_file_reference.dart';
import '../utils/app_logger.dart';
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
    // Kartta tıklayınca detayları göster/gizle
    setState(() {
      _showDetails = !_showDetails;
    });
  }

  void _showDeleteMenu(BuildContext context, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                ),
                title: const Text(
                  'Kaydı Sil',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                ),
                subtitle: Text(
                  widget.entry.description,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onDelete?.call();
                },
              ),
            ],
          ),
        ),
      ),
    );
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
        child: Material(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(20),
          elevation: 0,
          child: InkWell(
            onTap: _handleTap,
            borderRadius: BorderRadius.circular(20),
            splashColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
            highlightColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.05),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  // Üst kısım: İkon, Açıklama, Menü butonu
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
                              : Icons.description_outlined,
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
                    // Menü butonu (sadece silme yetkisi varsa) - sağ üstte
                    if (widget.onDelete != null)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _showDeleteMenu(context, theme);
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.more_horiz_rounded,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Miktar badge - tam genişlik, ortalanmış
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        NumberFormat.currency(
                          symbol: '₺',
                          decimalDigits: 0,
                          locale: 'tr_TR',
                        ).format(widget.entry.amount),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          letterSpacing: 0,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
                    // Dosya açma butonu
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _openFile(context),
                        icon: Icon(
                          widget.entry.fileType == 'pdf'
                              ? Icons.picture_as_pdf_rounded
                              : Icons.description_outlined,
                          size: 20,
                        ),
                        label: const Text('Dosyayı Aç'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
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
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Dosya yükleniyor...'),
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
          final errorStr = e.toString();
          errorMessage = 'Dosya açılamadı: ${errorStr.length > 100 ? "${errorStr.substring(0, 100)}..." : errorStr}';
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
