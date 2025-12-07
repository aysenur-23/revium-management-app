/**
 * Harcama kaydı kartı widget'ı
 * Entry bilgilerini gösterir ve tıklanabilir
 */

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/expense_entry.dart';

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
    if (!_showDetails) {
      // İlk tıklama: Detayları göster
      setState(() {
        _showDetails = true;
      });
    } else {
      // İkinci tıklama: Dosyayı aç
      _openFile(context);
      // Detayları kapat
      setState(() {
        _showDetails = false;
      });
    }
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

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(
            scale: 0.95 + (value * 0.05),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _handleTap,
            borderRadius: BorderRadius.circular(20),
            splashColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            highlightColor: theme.colorScheme.primary.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Üst kısım: İkon, Açıklama, Miktar
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Dosya tipi ikonu
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          widget.entry.fileType == 'pdf'
                              ? Icons.picture_as_pdf_rounded
                              : Icons.image_rounded,
                          color: theme.colorScheme.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Açıklama ve tarih - Expanded ile overflow önleniyor
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.entry.description,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                letterSpacing: -0.4,
                                height: 1.35,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_rounded,
                                  size: 14,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    DateFormat('dd.MM.yyyy', kIsWeb ? null : 'tr_TR').format(widget.entry.createdAt ?? DateTime.now()),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.person_outline_rounded,
                                  size: 14,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    widget.entry.ownerName,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Miktar badge - sabit genişlik
                      Container(
                        constraints: const BoxConstraints(minWidth: 90),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          NumberFormat.currency(
                            symbol: '₺',
                            decimalDigits: 0,
                          ).format(widget.entry.amount),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            letterSpacing: 0.4,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Silme butonu - sadece onDelete varsa
                      if (widget.onDelete != null) ...[
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
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
                          itemBuilder: (context) => [
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  const Text('Sil'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  // Detaylı bilgiler - sadece _showDetails true ise göster
                  if (_showDetails) ...[
                    const SizedBox(height: 20),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: theme.colorScheme.outline.withValues(alpha: 0.1),
                    ),
                    const SizedBox(height: 16),
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
                    // Yükleyen - sadece showOwnerIcon true ise göster
                    if (widget.showOwnerIcon) ...[
                      const SizedBox(height: 12),
                      _DetailRow(
                        icon: Icons.person_rounded,
                        label: 'Yükleyen',
                        value: widget.entry.ownerName,
                        iconColor: theme.colorScheme.tertiary,
                      ),
                    ],
                    // Bilgilendirme mesajı
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Tekrar tıklayarak belgeyi açabilirsiniz',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontSize: 12,
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
      ),
    );
  }

  /// Dosyayı tarayıcıda açar
  Future<void> _openFile(BuildContext context) async {
    try {
      if (widget.entry.fileUrl.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Dosya URL\'i bulunamadı'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final uri = Uri.parse(widget.entry.fileUrl);
      
      // URL'in geçerli olduğunu kontrol et
      if (!uri.hasScheme || (!uri.scheme.startsWith('http'))) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Geçersiz dosya URL\'i'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // URL'i açmayı dene
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Dosya açılamadı: ${widget.entry.fileUrl}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dosya açma hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
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
