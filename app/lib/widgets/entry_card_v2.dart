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
  final VoidCallback? onDelete;
  final bool showOwnerIcon;
  final bool isFixedExpense;
  final bool showMonthInfo;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelect;
  final bool isSelectionMode;

  const EntryCard({
    super.key,
    required this.entry,
    this.onDelete,
    this.showOwnerIcon = true,
    this.isFixedExpense = false,
    this.showMonthInfo = false,
    this.isSelected = false,
    this.onLongPress,
    this.onSelect,
    this.isSelectionMode = false,
  });

  @override
  State<EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<EntryCard> {
  bool _showDetails = false;

  void _handleTap() {
    if (widget.isSelectionMode && widget.onSelect != null) {
      widget.onSelect!();
      return;
    }
    setState(() {
      _showDetails = !_showDetails;
    });
  }

  void _handleLongPress() {
    if (widget.isSelectionMode) {
      if (widget.onSelect != null) {
        widget.onSelect!();
      }
      return;
    }
    
    if (widget.onLongPress != null) {
      widget.onLongPress!();
    } else if (widget.onDelete != null) {
      // Eğer onLongPress özel olarak tanımlanmamışsa ve onDelete varsa silme menüsünü göster
      final theme = Theme.of(context);
      _showDeleteMenu(context, theme);
    }
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
    DateFormat dateFormat;
    try {
      dateFormat = DateFormat('dd.MM.yyyy HH:mm', kIsWeb ? null : 'tr_TR');
    } catch (e) {
      dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    }

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Material(
          color: widget.isSelected 
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(20),
          elevation: 0,
          child: InkWell(
            onTap: _handleTap,
            onLongPress: _handleLongPress,
            borderRadius: BorderRadius.circular(20),
            splashColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
            highlightColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: widget.isSelected 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.outline.withValues(alpha: 0.05),
                  width: widget.isSelected ? 2 : 0.5,
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
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Üst kısım: İkon, Açıklama, Menü butonu
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: widget.entry.entryType == 'income'
                                    ? Colors.green.withValues(alpha: 0.2)
                                    : widget.entry.entryType == 'tax_deductible'
                                        ? Colors.orange.withValues(alpha: 0.2)
                                        : theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                widget.entry.entryType == 'income'
                                    ? Icons.trending_up
                                    : widget.entry.entryType == 'tax_deductible'
                                        ? Icons.assignment_turned_in
                                        : widget.entry.fileType == 'pdf'
                                            ? Icons.picture_as_pdf_rounded
                                            : Icons.description_outlined,
                                color: widget.entry.entryType == 'income'
                                    ? Colors.green
                                    : widget.entry.entryType == 'tax_deductible'
                                        ? Colors.orange
                                        : theme.colorScheme.primary,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
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
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
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
                                          Text(
                                            widget.entry.createdAt != null
                                                ? DateFormat('dd.MM.yyyy', kIsWeb ? null : 'tr_TR').format(widget.entry.createdAt!)
                                                : 'Tarih yok',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (widget.showOwnerIcon)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.person_outline_rounded,
                                              size: 12,
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              widget.entry.ownerName,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      if (widget.isFixedExpense || (widget.entry.fixedExpenseId != null && widget.entry.fixedExpenseId!.isNotEmpty))
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: Colors.orange.withValues(alpha: 0.3),
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Text(
                                            'Sabit',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: Colors.orange.shade700,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      if (widget.showMonthInfo && widget.entry.createdAt != null)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.calendar_month_rounded,
                                              size: 12,
                                              color: theme.colorScheme.primary.withValues(alpha: 0.7),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              DateFormat('MMMM yyyy', kIsWeb ? null : 'tr_TR').format(widget.entry.createdAt!),
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.primary.withValues(alpha: 0.8),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: widget.entry.entryType == 'income'
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : widget.entry.entryType == 'tax_deductible'
                                      ? Colors.grey.withValues(alpha: 0.1)
                                      : theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.entry.entryType == 'income')
                                  const Icon(
                                    Icons.add_circle_outline,
                                    size: 18,
                                    color: Colors.green,
                                  ),
                                if (widget.entry.entryType == 'tax_deductible')
                                  Icon(
                                    Icons.receipt_long_outlined,
                                    size: 18,
                                    color: Colors.grey[600],
                                  ),
                                if (widget.entry.entryType == 'income' || widget.entry.entryType == 'tax_deductible')
                                  const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    NumberFormat.currency(
                                      symbol: '₺',
                                      decimalDigits: 0,
                                      locale: 'tr_TR',
                                    ).format(widget.entry.amount),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: widget.entry.entryType == 'income'
                                          ? Colors.green
                                          : widget.entry.entryType == 'tax_deductible'
                                              ? Colors.grey[600]
                                              : theme.colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      letterSpacing: 0,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_showDetails) ...[
                          const SizedBox(height: 12),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: theme.colorScheme.outline.withValues(alpha: 0.08),
                          ),
                          const SizedBox(height: 12),
                          if (widget.entry.createdAt != null)
                            _DetailRow(
                              icon: Icons.calendar_today_rounded,
                              label: 'Tarih/Saat',
                              value: dateFormat.format(widget.entry.createdAt!),
                              iconColor: theme.colorScheme.primary,
                            ),
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
                          if (widget.entry.fileUrl.isNotEmpty) ...[
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
                                  backgroundColor: widget.entry.entryType == 'income'
                                      ? Colors.green
                                      : widget.entry.entryType == 'tax_deductible'
                                          ? Colors.orange
                                          : theme.colorScheme.primary,
                                  foregroundColor: widget.entry.entryType == 'income' || widget.entry.entryType == 'tax_deductible'
                                      ? Colors.white
                                      : theme.colorScheme.onPrimary,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _DetailRow(
                              icon: Icons.link_rounded,
                              label: 'Drive linki',
                              value: widget.entry.fileUrl,
                              iconColor: theme.colorScheme.primary,
                              maxLines: 2,
                              selectable: true,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  if (widget.isSelected || widget.isSelectionMode)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: widget.isSelected
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: widget.isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: widget.isSelected
                            ? Icon(
                                Icons.check,
                                size: 16,
                                color: theme.colorScheme.onPrimary,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _extractFileIdFromUrl(String url) {
    if (url.isEmpty) return null;
    final fileIdMatch1 = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    if (fileIdMatch1 != null) {
      return fileIdMatch1.group(1);
    }
    final fileIdMatch2 = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(url);
    if (fileIdMatch2 != null) {
      return fileIdMatch2.group(1);
    }
    return null;
  }

  Future<void> _openFile(BuildContext context) async {
    try {
      AppLogger.info('📄 Dosya açma işlemi başlatıldı');
      if (widget.entry.fileUrl.isEmpty) {
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

      String? fileId = widget.entry.driveFileId.isNotEmpty 
          ? widget.entry.driveFileId 
          : _extractFileIdFromUrl(widget.entry.fileUrl);
      
      if (fileId == null || fileId.isEmpty) {
        try {
          final uri = Uri.parse(widget.entry.fileUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
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

      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
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

      final fileRef = AppFileReference.fromExpenseEntry(
        entryId: widget.entry.id ?? '',
        driveFileId: fileId,
        fileUrl: widget.entry.fileUrl,
        fileType: widget.entry.fileType,
        ownerId: widget.entry.ownerId,
        mimeType: widget.entry.mimeType,
        fileName: widget.entry.fileName,
      );

      await FileOpenService.openOrDownloadAndOpen(fileRef);

      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dosya açılamadı: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final int maxLines;
  final bool selectable;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    this.maxLines = 1,
    this.selectable = false,
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
              selectable
                  ? SelectableText(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        height: 1.4,
                      ),
                      maxLines: maxLines,
                    )
                  : Text(
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
