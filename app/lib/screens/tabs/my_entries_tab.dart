/// Eklediklerim sekmesi
/// Kullanıcının kendi eklediği kayıtları gösterir
library;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/firestore_service.dart';
import '../../services/upload_service.dart';
import '../../widgets/entry_card_v2.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/error_retry_widget.dart';
import '../../widgets/loading_widget.dart';
import '../../config/app_config.dart';
import 'package:intl/intl.dart';
import '../../utils/app_logger.dart';
import '../home_screen.dart';
import 'dart:async';

enum MySortOption {
  dateDesc,
  dateAsc,
  amountDesc,
  amountAsc,
}

enum DateFilterType {
  all,      // Tüm zamanlar
  month,    // Aylık
  year,     // Yıllık
  day,      // Günlük
  custom,   // Özel tarih aralığı
}

class MyEntriesTab extends StatefulWidget {
  final UserProfile currentUser;

  const MyEntriesTab({
    super.key,
    required this.currentUser,
  });

  @override
  State<MyEntriesTab> createState() => _MyEntriesTabState();
}

class _MyEntriesTabState extends State<MyEntriesTab> with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  MySortOption _sortOption = MySortOption.dateDesc;
  bool _hasReceivedData = false; // İlk veri geldi mi kontrolü
  
  // Gelişmiş tarih filtresi
  DateFilterType _dateFilterType = DateFilterType.all;
  DateTime? _selectedMonth;
  int? _selectedYear;
  DateTime? _selectedDay;
  DateTimeRange? _selectedDateRange;
  String? _selectedEntryTypeFilter; // 'expense', 'income', null (hepsi)

  // Çoklu seçim durumu
  final Set<String> _selectedEntryIds = {};
  bool _isSelectionMode = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ExpenseEntry> _filterAndSort(List<ExpenseEntry> entries) {
    var filtered = entries;

    // Kayıt Türü filtresi
    if (_selectedEntryTypeFilter != null && _selectedEntryTypeFilter != 'Hepsi') {
      filtered = filtered
          .where((entry) => entry.entryType == _selectedEntryTypeFilter)
          .toList();
    }

    // Gelişmiş tarih filtresi
    filtered = filtered.where((entry) {
      if (entry.createdAt == null) return false;
      
      final entryDate = entry.createdAt!;
      
      switch (_dateFilterType) {
        case DateFilterType.all:
          // Tüm Zamanlar: Kasım 2024'ten itibaren
          return (entryDate.year == 2024 && entryDate.month >= 11) || entryDate.year > 2024;
        case DateFilterType.month:
          if (_selectedMonth == null) return true;
          return entryDate.year == _selectedMonth!.year &&
                 entryDate.month == _selectedMonth!.month;
        case DateFilterType.year:
          if (_selectedYear == null) return true;
          return entryDate.year == _selectedYear;
        case DateFilterType.day:
          if (_selectedDay == null) return true;
          return entryDate.year == _selectedDay!.year &&
                 entryDate.month == _selectedDay!.month &&
                 entryDate.day == _selectedDay!.day;
        case DateFilterType.custom:
          if (_selectedDateRange == null) return true;
          final startDate = DateTime(
            _selectedDateRange!.start.year,
            _selectedDateRange!.start.month,
            _selectedDateRange!.start.day,
          );
          final endDate = DateTime(
            _selectedDateRange!.end.year,
            _selectedDateRange!.end.month,
            _selectedDateRange!.end.day,
            23, 59, 59, 999,
          );
          final normalizedEntry = DateTime(entryDate.year, entryDate.month, entryDate.day);
          return normalizedEntry.compareTo(startDate) >= 0 &&
                 normalizedEntry.compareTo(endDate) <= 0;
      }
    }).toList();

    // Arama filtresi
    final searchQuery = _searchController.text.trim().toLowerCase();
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((entry) {
        return entry.description.toLowerCase().contains(searchQuery) ||
            entry.amount.toString().contains(searchQuery);
      }).toList();
    }

    // Sıralama
    filtered.sort((a, b) {
      switch (_sortOption) {
        case MySortOption.dateDesc:
          if (a.createdAt == null && b.createdAt == null) return 0;
          if (a.createdAt == null) return 1;
          if (b.createdAt == null) return -1;
          return b.createdAt!.compareTo(a.createdAt!);
        case MySortOption.dateAsc:
          if (a.createdAt == null && b.createdAt == null) return 0;
          if (a.createdAt == null) return 1;
          if (b.createdAt == null) return -1;
          return a.createdAt!.compareTo(b.createdAt!);
        case MySortOption.amountDesc:
          return b.amount.compareTo(a.amount);
        case MySortOption.amountAsc:
          return a.amount.compareTo(b.amount);
      }
    });

    return filtered;
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      locale: const Locale('tr', 'TR'),
      helpText: 'Tarih Aralığı Seçin',
      cancelText: 'İptal',
      confirmText: 'Seç',
    );
    if (picked != null) {
      setState(() {
        _dateFilterType = DateFilterType.custom;
        _selectedDateRange = picked;
      });
    }
  }

  /// Ay seçimi
  Future<void> _selectMonth(BuildContext context, ThemeData theme) async {
    final now = DateTime.now();
    int selectedYear = _selectedMonth?.year ?? now.year;
    int selectedMonthIndex = (_selectedMonth?.month ?? now.month) - 1;
    
    final months = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
    ];
    
    final result = await showModalBottomSheet<DateTime?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Filtre Seç',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: Radio<DateTime?>(
                  value: null,
                  groupValue: _selectedMonth,
                  onChanged: (value) => Navigator.of(ctx).pop(null),
                ),
                title: const Text('Tüm Zamanlar'),
                onTap: () => Navigator.of(ctx).pop(null),
              ),
              const Divider(height: 1),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: selectedYear > 2024
                          ? () => setModalState(() => selectedYear--)
                          : null,
                    ),
                    Text(
                      '$selectedYear',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: selectedYear < now.year
                          ? () => setModalState(() => selectedYear++)
                          : null,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    final isSelected = selectedMonthIndex == index && 
                                     _selectedMonth != null &&
                                     _selectedMonth!.year == selectedYear;
                    final isFuture = selectedYear == now.year && index > now.month - 1;
                    final isPast = selectedYear < 2024 || 
                                  (selectedYear == 2024 && index < 10);
                    
                    return Material(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: (isFuture || isPast) ? null : () {
                          Navigator.of(ctx).pop(DateTime(selectedYear, index + 1, 1));
                        },
                        child: Center(
                          child: Text(
                            months[index],
                            style: TextStyle(
                              color: (isFuture || isPast)
                                  ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                                  : isSelected
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurface,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;

    if (result == null) {
      setState(() {
        _dateFilterType = DateFilterType.all;
        _selectedMonth = null;
        _selectedYear = null;
        _selectedDay = null;
        _selectedDateRange = null;
      });
    } else {
      setState(() {
        _dateFilterType = DateFilterType.month;
        _selectedMonth = result;
        _selectedYear = null;
        _selectedDay = null;
        _selectedDateRange = null;
      });
    }
  }

  /// Yıl seçimi
  Future<void> _selectYear(BuildContext context, ThemeData theme) async {
    final now = DateTime.now();
    final years = List.generate(now.year - 2019, (i) => now.year - i);
    
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.4,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text('Yıl Seçin', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                   IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: years.length,
                itemBuilder: (context, index) {
                  final year = years[index];
                  final isSelected = _selectedYear == year;
                  
                  return ListTile(
                    title: Text(
                      '$year',
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? theme.colorScheme.primary : null,
                      ),
                    ),
                    trailing: isSelected ? Icon(Icons.check_rounded, color: theme.colorScheme.primary) : null,
                    onTap: () {
                      setState(() {
                        _dateFilterType = DateFilterType.year;
                        _selectedYear = year;
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Gün seçimi
  Future<void> _selectDay(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('tr', 'TR'),
      helpText: 'Gün Seçin',
      cancelText: 'İptal',
      confirmText: 'Seç',
    );
    if (picked != null) {
      setState(() {
        _dateFilterType = DateFilterType.day;
        _selectedDay = picked;
      });
    }
  }

  void _showDateFilterOptions(BuildContext context, ThemeData theme) {
    _selectMonth(context, theme);
  }

  Widget _buildDateFilterOption({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    bool isRecommended = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: isSelected ? Border.all(color: theme.colorScheme.primary, width: 2) : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.primary, size: 22),
        ),
        title: Row(
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? theme.colorScheme.onPrimaryContainer : null)),
            if (isRecommended) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Önerilen', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: theme.colorScheme.onTertiary)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: isSelected
                ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                : theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        trailing: isSelected ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary) : const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }

  IconData _getDateFilterIcon() {
    if (_dateFilterType == DateFilterType.all) {
      return Icons.all_inclusive_rounded;
    }
    return Icons.calendar_month_rounded;
  }

  String _getDateFilterText() {
    if (_dateFilterType == DateFilterType.all) {
      return 'Tüm Zamanlar';
    }
    if (_selectedMonth != null) {
      return DateFormat('MMMM yyyy', 'tr_TR').format(_selectedMonth!);
    }
    return 'Ay Seç';
  }

  void _showFilterDialog(BuildContext context, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filtrele',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Kayıt Türü',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedEntryTypeFilter ?? 'Hepsi',
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              items: ['Hepsi', 'expense', 'income', 'tax_deductible']
                  .map((type) => DropdownMenuItem(
                        value: type,
                        child: Text(
                          type == 'Hepsi' 
                            ? 'Hepsi' 
                            : type == 'expense' 
                              ? 'Gider' 
                              : type == 'income' 
                                ? 'Gelir' 
                                : 'Vergi',
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedEntryTypeFilter = value;
                });
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Tarih',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _buildDateFilterOption(
              context: context,
              theme: theme,
              icon: Icons.all_inclusive_rounded,
              title: 'Tüm Zamanlar',
              subtitle: 'Tüm kayıtları gösterir',
              isSelected: _dateFilterType == DateFilterType.all,
              onTap: () {
                setState(() {
                  _dateFilterType = DateFilterType.all;
                  _selectedMonth = null;
                });
                Navigator.of(context).pop();
              },
            ),
            _buildDateFilterOption(
              context: context,
              theme: theme,
              icon: Icons.calendar_month_rounded,
              title: 'Ay Seçer',
              isRecommended: true,
              subtitle: _selectedMonth != null 
                ? DateFormat('MMMM yyyy', 'tr_TR').format(_selectedMonth!)
                : 'Belirli bir ayı seçin',
              isSelected: _dateFilterType == DateFilterType.month,
              onTap: () {
                Navigator.of(context).pop();
                _selectMonth(context, theme);
              },
            ),
            _buildDateFilterOption(
              context: context,
              theme: theme,
              icon: Icons.date_range_rounded,
              title: 'Özel Arallık',
              subtitle: _selectedDateRange != null
                ? '${DateFormat('d MMM', 'tr_TR').format(_selectedDateRange!.start)} - ${DateFormat('d MMM', 'tr_TR').format(_selectedDateRange!.end)}'
                : 'Tarih aralığı seçin',
              isSelected: _dateFilterType == DateFilterType.custom,
              onTap: () {
                Navigator.of(context).pop();
                _selectDateRange(context);
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _selectedEntryTypeFilter = 'Hepsi';
                    _dateFilterType = DateFilterType.all;
                    _selectedMonth = null;
                    _selectedDateRange = null;
                    _searchController.clear();
                  });
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Filtreleri Temizle'),
              ),
            ),
          ],
        ),
      ),
     ),
    );
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedEntryTypeFilter != null && _selectedEntryTypeFilter != 'Hepsi') count++;
    if (_dateFilterType != DateFilterType.all) count++;
    return count;
  }

  Future<void> _deleteEntry(BuildContext context, ExpenseEntry entry) async {
    // Silme onay dialog'u
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kayıt Sil'),
        content: Text('Bu kaydı silmek istediğinizden emin misiniz?\n\n${entry.description} - ₺${entry.amount.toStringAsFixed(2)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true || entry.id == null) {
      return;
    }

    try {
      // Firestore'dan sil (Google Drive dosyası kalıyor - arşiv amaçlı)
      await FirestoreService.deleteEntry(entry.id!, widget.currentUser.userId);

      // Excel dosyalarını güncelle (arka planda)
      _updateExcelFilesInBackground();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kayıt başarıyla silindi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Silme hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Seçili kayıtları toplu sil
  Future<void> _deleteSelectedEntries(BuildContext context) async {
    final count = _selectedEntryIds.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Toplu Sil'),
        content: Text('$count kaydı silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Loading göster
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );
      }

      final selectedIds = _selectedEntryIds.toList();
      await FirestoreService.deleteEntriesBatch(selectedIds, widget.currentUser.userId);

      if (context.mounted) {
        Navigator.of(context).pop(); // Loading kapat
        setState(() {
          _isSelectionMode = false;
          _selectedEntryIds.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count kayıt başarıyla silindi'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Excel dosyalarını güncelle
      _updateExcelFilesInBackground();
    } catch (e) {
      if (context.mounted) {
        try { Navigator.of(context).pop(); } catch (_) {} // Loading kapat
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Toplu silme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Excel dosyalarını arka planda güncelle (entry silindikten sonra)
  Future<void> _updateExcelFilesInBackground() async {
    try {
      // 1. Aktif ve Silinmiş Kayıtları Çek
      final activeEntries = await FirestoreService.getActiveEntries();
      final deletedEntries = await FirestoreService.getDeletedEntries();

      // Formatlayıcı yardımcı fonksiyon
      List<Map<String, dynamic>> format(List<ExpenseEntry> list) {
        return list.map((entry) {
          return {
            'createdAt': entry.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
            'notes': entry.notes ?? '',
            'ownerName': entry.ownerName,
            'amount': entry.amount,
            'description': entry.description,
            'fileUrl': entry.fileUrl,
            'entryType': entry.entryType,
          };
        }).toList();
      }

      final formattedActiveEntries = format(activeEntries);
      final formattedDeletedEntries = format(deletedEntries);

      // Kullanıcının kendi aktif/silinmiş kayıtlarını filtrele
      final myActiveEntries = activeEntries.where((e) => e.ownerId == widget.currentUser.userId).toList();
      final myDeletedEntries = deletedEntries.where((e) => e.ownerId == widget.currentUser.userId).toList();
      
      final formattedMyActiveEntries = format(myActiveEntries);
      final formattedMyDeletedEntries = format(myDeletedEntries);

      // 3. Tüm sabit giderleri çek
      final fixedExpenses = await FirestoreService.getAllFixedExpenses();
      final formattedFixedExpenses = fixedExpenses.map((expense) {
        return {
          'createdAt': expense.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
          'startDate': expense.startDate?.toIso8601String(),
          'notes': expense.notes ?? '',
          'ownerName': expense.ownerName,
          'amount': expense.amount,
          'description': expense.description,
          'category': expense.category ?? '',
          'recurrence': expense.recurrence ?? '',
          'isActive': expense.isActive,
        };
      }).toList();

      // 4. Tüm Excel dosyalarını SIRALI olarak güncelle (API Rate Limit önlemi)
      
      // Tüm entry'ler Excel'i
      try {
        await UploadService.createExcelFile(
          entries: formattedActiveEntries,
          fileName: 'Tum Eklenenler.csv'
        );
      } catch (e) {
        AppLogger.warning('Tüm entry\'ler Excel güncellenirken hata: $e');
      }
      await Future.delayed(const Duration(milliseconds: 500));

      // Kullanıcının entry'leri Excel'i
      try {
        await UploadService.createExcelFile(
          entries: formattedMyActiveEntries,
          fileName: '${widget.currentUser.fullName} Eklediklerim.csv'
        );
      } catch (e) {
        AppLogger.warning('Kullanıcı entry\'leri Excel güncellenirken hata: $e');
      }
      await Future.delayed(const Duration(milliseconds: 500));

      // Sabit giderler Excel'i
      try {
        await UploadService.initializeGoogleSheetsWithFixedExpenses(formattedFixedExpenses);
      } catch (e) {
        AppLogger.warning('Sabit giderler Excel güncellenirken hata: $e');
      }
      await Future.delayed(const Duration(milliseconds: 500));

      // Tüm veriler Excel'i (settings)
      try {
        await UploadService.initializeGoogleSheetsWithAllData(
          entries: formattedActiveEntries, 
          fixedExpenses: formattedFixedExpenses
        );
      } catch (e) {
        AppLogger.warning('Tüm veriler Excel güncellenirken hata: $e');
      }
      
      AppLogger.info('Excel dosyaları başarıyla güncellendi (Sıralı)');
    } catch (e) {
      // Hata olsa bile sessizce devam et (kullanıcıyı rahatsız etme)
      AppLogger.warning('Excel dosyaları güncellenirken genel hata: $e');
    }
  }

  // Google Sheets açma işlemi HomeScreen'e taşındı.


  Widget _buildContent(ThemeData theme) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Column(
      children: [
        // Kompakt başlık ve arama barı
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 16 : 20,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Başlık (mobilde gizle veya küçült)
              if (!isSmallScreen)
                Text(
                  'Eklediklerim',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              if (!isSmallScreen) const SizedBox(width: 8),
              // Ay filtresi seçiliyse tarih chip'i ve önceki/sonraki butonları göster
              if (_dateFilterType == DateFilterType.month && _selectedMonth != null) ...[
                // Önceki ay butonu
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(
                    minWidth: isSmallScreen ? 32 : 36,
                    minHeight: isSmallScreen ? 32 : 36,
                  ),
                  onPressed: () {
                    final prevMonth = DateTime(_selectedMonth!.year, _selectedMonth!.month - 1, 1);
                    final november2024 = DateTime(2024, 11, 1);
                    if (prevMonth.isAfter(november2024.subtract(const Duration(days: 1))) ||
                        prevMonth.isAtSameMomentAs(november2024)) {
                      setState(() {
                        _selectedMonth = prevMonth;
                      });
                    }
                  },
                  tooltip: 'Önceki ay',
                ),
                const SizedBox(width: 4),
                // Tarih chip/button
                Material(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  elevation: 1,
                  shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.1),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _selectMonth(context, theme),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 12 : 16,
                        vertical: isSmallScreen ? 6 : 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            size: isSmallScreen ? 16 : 18,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          SizedBox(width: isSmallScreen ? 6 : 8),
                          Flexible(
                            child: Text(
                              DateFormat('MMM yyyy', 'tr_TR').format(_selectedMonth!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                                fontSize: isSmallScreen ? 11 : 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: isSmallScreen ? 4 : 6),
                          Icon(
                            Icons.arrow_drop_down_rounded,
                            size: isSmallScreen ? 16 : 18,
                            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Sonraki ay butonu
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(
                    minWidth: isSmallScreen ? 32 : 36,
                    minHeight: isSmallScreen ? 32 : 36,
                  ),
                  onPressed: () {
                    final now = DateTime.now();
                    final nextMonth = DateTime(_selectedMonth!.year, _selectedMonth!.month + 1, 1);
                    if (nextMonth.isBefore(DateTime(now.year, now.month + 1, 1)) ||
                        nextMonth.isAtSameMomentAs(DateTime(now.year, now.month, 1))) {
                      setState(() {
                        _selectedMonth = nextMonth;
                      });
                    }
                  },
                  tooltip: 'Sonraki ay',
                ),
                SizedBox(width: isSmallScreen ? 4 : 8),
              ],
              // Arama
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Ara...',
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                  onChanged: (value) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {});
                      }
                    });
                  },
                ),
              ),
              SizedBox(width: isSmallScreen ? 4 : 8),
              // Sıralama butonu
              PopupMenuButton<MySortOption>(
                icon: Icon(
                  Icons.sort_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  size: isSmallScreen ? 20 : 24,
                ),
                tooltip: 'Sırala',
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: isSmallScreen ? 36 : 48,
                  minHeight: isSmallScreen ? 36 : 48,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (value) {
                  setState(() {
                    _sortOption = value;
                  });
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: MySortOption.dateDesc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_downward,
                          size: 18,
                          color: _sortOption == MySortOption.dateDesc
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('Tarih (Yeni → Eski)'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: MySortOption.dateAsc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_upward,
                          size: 18,
                          color: _sortOption == MySortOption.dateAsc
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('Tarih (Eski → Yeni)'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: MySortOption.amountDesc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_downward,
                          size: 18,
                          color: _sortOption == MySortOption.amountDesc
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('Miktar (Yüksek → Düşük)'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: MySortOption.amountAsc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_upward,
                          size: 18,
                          color: _sortOption == MySortOption.amountAsc
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('Miktar (Düşük → Yüksek)'),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(width: isSmallScreen ? 4 : 8),
              // Filtre butonu
              IconButton(
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: isSmallScreen ? 36 : 48,
                  minHeight: isSmallScreen ? 36 : 48,
                ),
                icon: Stack(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: isSmallScreen ? 20 : 24,
                      color: _getActiveFilterCount() > 0
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    if (_getActiveFilterCount() > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 12,
                            minHeight: 12,
                          ),
                          child: Text(
                            '${_getActiveFilterCount()}',
                            style: TextStyle(
                              color: theme.colorScheme.onError,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                tooltip: 'Filtrele',
                onPressed: () => _showFilterDialog(context, theme),
              ),
            ],
          ),
        ),
        // Liste
        Expanded(
          child: StreamBuilder<List<ExpenseEntry>>(
            stream: FirestoreService.streamMyEntries(widget.currentUser.userId),
            builder: (context, snapshot) {
              // Hata durumu
              if (snapshot.hasError) {
                final errorMessage = snapshot.error.toString();
                AppLogger.error('MyEntriesTab StreamBuilder hatası', snapshot.error);
                
                String userMessage = 'Veriler yüklenirken bir hata oluştu';
                if (errorMessage.contains('index') || errorMessage.contains('Index')) {
                  userMessage = 'Firestore index hatası. Lütfen Firebase Console\'da gerekli index\'i oluşturun.';
                } else if (errorMessage.contains('permission') || errorMessage.contains('Permission') || errorMessage.contains('permission-denied')) {
                  userMessage = 'Firestore erişim izni hatası. Lütfen çıkış yapıp tekrar giriş yapın.';
                }
                
                return ErrorRetryWidget(
                  message: userMessage,
                  onRetry: () async {
                    if (errorMessage.contains('permission')) {
                      try {
                        final currentUser = FirebaseAuth.instance.currentUser;
                        if (currentUser != null) await currentUser.getIdToken(true);
                      } catch (_) {}
                    }
                  },
                );
              }

              final allEntries = snapshot.data ?? [];
              
              if (snapshot.hasData && !_hasReceivedData) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _hasReceivedData = true);
                });
              }
              
              if (snapshot.connectionState == ConnectionState.waiting && 
                  !_hasReceivedData && 
                  !snapshot.hasData) {
                return const LoadingWidget(message: 'Kayıtlar yükleniyor...');
              }
              
              final filteredEntries = _filterAndSort(allEntries);

              if (allEntries.isEmpty) {
                return const EmptyStateWidget(
                  title: 'Henüz kayıt eklemediniz',
                  subtitle: 'Yukarıdaki "Ekleme" sekmesinden kayıt ekleyebilirsiniz',
                  icon: Icons.receipt_long,
                );
              }

              if (filteredEntries.isEmpty) {
                return const EmptyStateWidget(
                  title: 'Arama/Filtre sonucu bulunamadı',
                  subtitle: 'Farklı bir arama terimi veya filtre deneyin',
                  icon: Icons.search_off,
                );
              }

              // Toplamları hesapla
              final totalIncome = filteredEntries
                  .where((entry) => entry.entryType == 'income')
                  .fold<double>(0.0, (sum, entry) => sum + entry.amount);
              
              final totalExpense = filteredEntries
                  .where((entry) => entry.entryType == 'expense')
                  .fold<double>(0.0, (sum, entry) => sum + entry.amount);
              
              final totalTaxDeductible = filteredEntries
                  .where((entry) => entry.entryType == 'tax_deductible')
                  .fold<double>(0.0, (sum, entry) => sum + entry.amount);
              
              final netResult = totalIncome - totalExpense;

              return RefreshIndicator(
                onRefresh: () async {
                  await Future.delayed(const Duration(milliseconds: 500));
                },
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filteredEntries.length + (filteredEntries.isNotEmpty ? 1 : 0),
                  cacheExtent: AppConfig.listViewCacheExtent.toDouble(),
                  itemBuilder: (context, index) {
                    if (index == 0 && filteredEntries.isNotEmpty) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12, top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.account_balance_wallet_rounded,
                                      size: 20,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      (_searchController.text.isEmpty && _getActiveFilterCount() == 0) ? 'Toplam' : 'Filtrelenmiş Toplam',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                                // Net sonuç (gelir - gider)
                                Text(
                                  netResult >= 0
                                      ? NumberFormat.currency(
                                          symbol: '₺',
                                          decimalDigits: 2,
                                          locale: 'tr_TR',
                                        ).format(netResult)
                                      : '-${NumberFormat.currency(
                                          symbol: '₺',
                                          decimalDigits: 2,
                                          locale: 'tr_TR',
                                        ).format(netResult.abs())}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: netResult >= 0 
                                        ? Colors.green 
                                        : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Gelir
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.trending_up,
                                      size: 16,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Gelir: ',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    Text(
                                      NumberFormat.currency(
                                        symbol: '₺',
                                        decimalDigits: 2,
                                        locale: 'tr_TR',
                                      ).format(totalIncome),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                // Gider
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.trending_down,
                                      size: 16,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Gider: ',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    Text(
                                      NumberFormat.currency(
                                        symbol: '₺',
                                        decimalDigits: 2,
                                        locale: 'tr_TR',
                                      ).format(totalExpense),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            // Vergiden düşülecek toplamı (eğer varsa) - minimal görünüm
                            if (totalTaxDeductible > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Vergiden düşülecek: ',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                    Text(
                                      NumberFormat.currency(
                                        symbol: '₺',
                                        decimalDigits: 2,
                                        locale: 'tr_TR',
                                      ).format(totalTaxDeductible),
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    }
                    
                    // Entry item'ları (index - 1 çünkü ilk item toplam kartı)
                    final entryIndex = filteredEntries.isNotEmpty ? index - 1 : index;
                    final entry = filteredEntries[entryIndex];
                    final displayEntry = entry.ownerName.isEmpty || entry.ownerId == widget.currentUser.userId
                        ? entry.copyWith(ownerName: widget.currentUser.fullName)
                        : entry;
                    return RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: EntryCard(
                          entry: displayEntry,
                          onDelete: () => _deleteEntry(context, entry),
                          showOwnerIcon: true,
                          isSelected: _selectedEntryIds.contains(entry.id),
                          isSelectionMode: _isSelectionMode,
                          onLongPress: () {
                            if (entry.id == null) return;
                            setState(() {
                              _isSelectionMode = true;
                              _selectedEntryIds.add(entry.id!);
                            });
                          },
                          onSelect: () {
                            if (entry.id == null) return;
                            setState(() {
                              if (_selectedEntryIds.contains(entry.id)) {
                                _selectedEntryIds.remove(entry.id);
                                if (_selectedEntryIds.isEmpty) {
                                  _isSelectionMode = false;
                                }
                              } else {
                                _selectedEntryIds.add(entry.id!);
                              }
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin için gerekli
    final theme = Theme.of(context);
    return Scaffold(
      body: _buildContent(theme),
      bottomNavigationBar: _isSelectionMode 
          ? StreamBuilder(
              stream: FirestoreService.streamMyEntries(widget.currentUser.userId),
              builder: (context, snapshot) {
                final entries = snapshot.data ?? [];
                final selectedEntries = entries.where((e) => _selectedEntryIds.contains(e.id)).toList();
                final selectedTotal = selectedEntries.fold<double>(0.0, (sum, e) => sum + e.amount);
                
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // İptal butonu
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _isSelectionMode = false;
                              _selectedEntryIds.clear();
                            });
                          },
                          icon: const Icon(Icons.close),
                          label: const Text('İptal'),
                        ),
                        // Sil butonu
                        TextButton.icon(
                          onPressed: () => _deleteSelectedEntries(context),
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          label: const Text('Sil', style: TextStyle(color: Colors.red)),
                        ),
                        // Seçili miktar ve toplam
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${_selectedEntryIds.length} kayıt seçildi',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                              ),
                            ),
                            Text(
                              NumberFormat.currency(
                                symbol: '₺',
                                decimalDigits: 2,
                                locale: 'tr_TR',
                              ).format(selectedTotal),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            )
          : null,
      floatingActionButton: null,
    );
  }
}

