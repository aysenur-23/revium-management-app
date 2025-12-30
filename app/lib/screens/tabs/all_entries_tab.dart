/**
 * Tüm Eklenenler sekmesi
 * Tüm kullanıcıların kayıtlarını gösterir ve filtreleme yapar
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/firestore_service.dart';
import '../../services/upload_service.dart';
import '../../services/local_excel_service.dart';
import '../../widgets/entry_card.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/error_retry_widget.dart';
import '../../widgets/loading_widget.dart';
import '../../config/app_config.dart';
import '../../utils/app_logger.dart';
import '../home_screen.dart';
import 'dart:async';

class AllEntriesTab extends StatefulWidget {
  final UserProfile? currentUser;

  const AllEntriesTab({
    super.key,
    this.currentUser,
  });

  @override
  State<AllEntriesTab> createState() => _AllEntriesTabState();
}

enum SortOption {
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

class _AllEntriesTabState extends State<AllEntriesTab> with AutomaticKeepAliveClientMixin {
  String? _selectedOwnerFilter;
  DateTimeRange? _selectedDateRange;
  final TextEditingController _searchController = TextEditingController();
  SortOption _sortOption = SortOption.dateDesc;
  
  // Gelişmiş tarih filtresi
  DateFilterType _dateFilterType = DateFilterType.all;
  DateTime? _selectedMonth;
  int? _selectedYear;
  DateTime? _selectedDay;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openExcel(BuildContext context) async {
    try {
      AppLogger.info('📊 Excel açma işlemi başlatıldı (Tüm Eklenenler)');
      
      // Loading dialog göster
      if (mounted) {
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
                    Text('Excel hazırlanıyor...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // Tüm entry'leri al
      AppLogger.info('Firestore\'dan tüm entry\'ler alınıyor...');
      final allEntries = await FirestoreService.getAllEntries();
      AppLogger.info('${allEntries.length} entry bulundu');

      if (!mounted) return;
      Navigator.of(context).pop(); // Loading dialog'u kapat

      if (allEntries.isEmpty) {
        AppLogger.warning('Entry bulunamadı, işlem iptal ediliyor');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Henüz kayıt bulunmuyor.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Lokal CSV oluştur ve paylaş (backend'e gerek yok)
      await LocalExcelService.createAndShareCSV(
        entries: allEntries,
        fileName: 'Tum_Eklenenler_${DateTime.now().toString().split(' ')[0]}.csv',
      );
      
      AppLogger.success('✅ Excel başarıyla paylaşıldı');
    } catch (e, stackTrace) {
      AppLogger.error('Excel açma hatası', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Excel açma hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }


  List<ExpenseEntry> _filterEntries(List<ExpenseEntry> entries) {
    var filtered = entries;

    // Kişi filtresi
    if (_selectedOwnerFilter != null && _selectedOwnerFilter != 'Hepsi') {
      filtered = filtered
          .where((entry) => entry.ownerName == _selectedOwnerFilter)
          .toList();
    }

    // Gelişmiş tarih filtresi
    if (_dateFilterType != DateFilterType.all) {
      filtered = filtered.where((entry) {
        if (entry.createdAt == null) return false;
        
        final entryDate = entry.createdAt!;
        
        switch (_dateFilterType) {
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
          case DateFilterType.all:
            return true;
        }
      }).toList();
    }

    // Arama filtresi
    final searchQuery = _searchController.text.trim().toLowerCase();
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((entry) {
        return entry.description.toLowerCase().contains(searchQuery) ||
            entry.ownerName.toLowerCase().contains(searchQuery) ||
            entry.amount.toString().contains(searchQuery);
      }).toList();
    }

    // Sıralama
    filtered.sort((a, b) {
      switch (_sortOption) {
        case SortOption.dateDesc:
          if (a.createdAt == null && b.createdAt == null) return 0;
          if (a.createdAt == null) return 1;
          if (b.createdAt == null) return -1;
          return b.createdAt!.compareTo(a.createdAt!);
        case SortOption.dateAsc:
          if (a.createdAt == null && b.createdAt == null) return 0;
          if (a.createdAt == null) return 1;
          if (b.createdAt == null) return -1;
          return a.createdAt!.compareTo(b.createdAt!);
        case SortOption.amountDesc:
          return b.amount.compareTo(a.amount);
        case SortOption.amountAsc:
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
    
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.5,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Başlık
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Ay Seçin', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              // Yıl seçici
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
                      onPressed: () => setModalState(() => selectedYear--),
                    ),
                    Text('$selectedYear', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: selectedYear < now.year ? () => setModalState(() => selectedYear++) : null,
                    ),
                  ],
                ),
              ),
              // Aylar grid
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
                    final isSelected = selectedMonthIndex == index;
                    final isFuture = selectedYear == now.year && index > now.month - 1;
                    
                    return Material(
                      color: isSelected ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: isFuture ? null : () {
                          setModalState(() => selectedMonthIndex = index);
                        },
                        child: Center(
                          child: Text(
                            months[index],
                            style: TextStyle(
                              color: isFuture 
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
              // Onayla butonu
              Padding(
                padding: const EdgeInsets.all(24),
                child: FilledButton(
                  onPressed: () {
                    setState(() {
                      _dateFilterType = DateFilterType.month;
                      _selectedMonth = DateTime(selectedYear, selectedMonthIndex + 1);
                    });
                    Navigator.pop(context);
                  },
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                  child: Text('${months[selectedMonthIndex]} $selectedYear Seç'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  /// Tarih filtresi seçenekleri
  void _showDateFilterOptions(BuildContext context, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
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
                Text('Tarih Filtresi', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            // Filtre seçenekleri
            _buildDateFilterOption(
              context: context,
              theme: theme,
              icon: Icons.all_inclusive_rounded,
              title: 'Tüm Zamanlar',
              subtitle: 'Tüm kayıtları göster',
              isSelected: _dateFilterType == DateFilterType.all,
              onTap: () {
                setState(() {
                  _dateFilterType = DateFilterType.all;
                  _selectedMonth = null;
                  _selectedYear = null;
                  _selectedDay = null;
                  _selectedDateRange = null;
                });
                Navigator.pop(context);
              },
            ),
            _buildDateFilterOption(
              context: context,
              theme: theme,
              icon: Icons.calendar_month_rounded,
              title: 'Aylık',
              subtitle: _dateFilterType == DateFilterType.month && _selectedMonth != null
                  ? DateFormat('MMMM yyyy', 'tr_TR').format(_selectedMonth!)
                  : 'Belirli bir ay seçin',
              isSelected: _dateFilterType == DateFilterType.month,
              isRecommended: true,
              onTap: () {
                Navigator.pop(context);
                _selectMonth(context, theme);
              },
            ),
            _buildDateFilterOption(
              context: context,
              theme: theme,
              icon: Icons.calendar_today_rounded,
              title: 'Yıllık',
              subtitle: _dateFilterType == DateFilterType.year && _selectedYear != null
                  ? '$_selectedYear'
                  : 'Belirli bir yıl seçin',
              isSelected: _dateFilterType == DateFilterType.year,
              onTap: () {
                Navigator.pop(context);
                _selectYear(context, theme);
              },
            ),
            _buildDateFilterOption(
              context: context,
              theme: theme,
              icon: Icons.today_rounded,
              title: 'Günlük',
              subtitle: _dateFilterType == DateFilterType.day && _selectedDay != null
                  ? DateFormat('dd MMMM yyyy', 'tr_TR').format(_selectedDay!)
                  : 'Belirli bir gün seçin',
              isSelected: _dateFilterType == DateFilterType.day,
              onTap: () {
                Navigator.pop(context);
                _selectDay(context);
              },
            ),
            _buildDateFilterOption(
              context: context,
              theme: theme,
              icon: Icons.date_range_rounded,
              title: 'Özel Aralık',
              subtitle: _dateFilterType == DateFilterType.custom && _selectedDateRange != null
                  ? '${DateFormat('dd.MM.yy', 'tr_TR').format(_selectedDateRange!.start)} - ${DateFormat('dd.MM.yy', 'tr_TR').format(_selectedDateRange!.end)}'
                  : 'Başlangıç ve bitiş tarihi seçin',
              isSelected: _dateFilterType == DateFilterType.custom,
              onTap: () {
                Navigator.pop(context);
                _selectDateRange(context);
              },
            ),
          ],
        ),
      ),
    );
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
    switch (_dateFilterType) {
      case DateFilterType.all:
        return Icons.all_inclusive_rounded;
      case DateFilterType.month:
        return Icons.calendar_month_rounded;
      case DateFilterType.year:
        return Icons.calendar_today_rounded;
      case DateFilterType.day:
        return Icons.today_rounded;
      case DateFilterType.custom:
        return Icons.date_range_rounded;
    }
  }

  String _getDateFilterText() {
    switch (_dateFilterType) {
      case DateFilterType.all:
        return 'Tüm Zamanlar';
      case DateFilterType.month:
        if (_selectedMonth != null) {
          return DateFormat('MMMM yyyy', 'tr_TR').format(_selectedMonth!);
        }
        return 'Ay Seç';
      case DateFilterType.year:
        if (_selectedYear != null) {
          return '$_selectedYear';
        }
        return 'Yıl Seç';
      case DateFilterType.day:
        if (_selectedDay != null) {
          return DateFormat('dd MMMM yyyy', 'tr_TR').format(_selectedDay!);
        }
        return 'Gün Seç';
      case DateFilterType.custom:
        if (_selectedDateRange != null) {
          return '${DateFormat('dd.MM.yy', 'tr_TR').format(_selectedDateRange!.start)} - ${DateFormat('dd.MM.yy', 'tr_TR').format(_selectedDateRange!.end)}';
        }
        return 'Tarih Aralığı Seç';
    }
  }

  void _showFilterDialog(BuildContext context, ThemeData theme, List<String> ownerNames) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Başlık
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
            // Kişi filtresi
            Text(
              'Kişi',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedOwnerFilter ?? 'Hepsi',
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: 'Hepsi',
                  child: Text('Hepsi'),
                ),
                ...ownerNames.map((name) {
                  return DropdownMenuItem<String>(
                    value: name,
                    child: Text(name),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedOwnerFilter = value;
                });
              },
            ),
            const SizedBox(height: 24),
            // Tarih filtresi
            Text(
              'Tarih Filtresi',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _showDateFilterOptions(context, theme);
              },
              icon: Icon(_getDateFilterIcon(), size: 18),
              label: Text(_getDateFilterText()),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (_dateFilterType != DateFilterType.all) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _dateFilterType = DateFilterType.all;
                    _selectedMonth = null;
                    _selectedYear = null;
                    _selectedDay = null;
                    _selectedDateRange = null;
                  });
                },
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Tarih Filtresini Temizle'),
              ),
            ],
            const SizedBox(height: 24),
            // Tüm filtreleri temizle
            if (_getActiveFilterCount() > 0)
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _selectedOwnerFilter = null;
                    _dateFilterType = DateFilterType.all;
                    _selectedMonth = null;
                    _selectedYear = null;
                    _selectedDay = null;
                    _selectedDateRange = null;
                    _searchController.clear();
                  });
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Tüm Filtreleri Temizle'),
              ),
          ],
        ),
      ),
    );
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedOwnerFilter != null && _selectedOwnerFilter != 'Hepsi') {
      count++;
    }
    if (_dateFilterType != DateFilterType.all) {
      count++;
    }
    if (_searchController.text.trim().isNotEmpty) {
      count++;
    }
    return count;
  }

  /// Entry'yi siler (sadece sahibi silebilir)
  Future<void> _deleteEntry(BuildContext context, ExpenseEntry entry) async {
    // Entry'nin sahibi kontrolü
    if (widget.currentUser == null || entry.ownerId != widget.currentUser!.userId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu kaydı silme yetkiniz yok. Sadece kendi kayıtlarınızı silebilirsiniz.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Onay dialog'u göster
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kaydı Sil'),
        content: const Text('Bu kaydı silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Loading göster
    if (mounted) {
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
                  Text('Kayıt siliniyor...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      // Entry'yi Firestore'dan sil
      await FirestoreService.deleteEntry(entry.id!, widget.currentUser!.userId);

      // Google Drive'dan dosyayı sil (varsa)
      if (entry.driveFileId.isNotEmpty) {
        try {
          await UploadService.deleteFile(entry.driveFileId);
          AppLogger.info('Google Drive dosyası silindi: ${entry.driveFileId}');
        } catch (e) {
          AppLogger.warning('Google Drive dosyası silinirken hata: $e');
          // Dosya silme hatası kritik değil, devam et
        }
      }

      // Excel dosyalarını güncelle (arka planda)
      _updateExcelFilesInBackground();

      if (mounted) {
        Navigator.of(context).pop(); // Loading dialog'u kapat
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kayıt başarıyla silindi'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Entry silme hatası', e);
      if (mounted) {
        Navigator.of(context).pop(); // Loading dialog'u kapat
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kayıt silinirken hata oluştu: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Excel dosyalarını arka planda güncelle (entry silindikten sonra)
  Future<void> _updateExcelFilesInBackground() async {
    try {
      // Tüm entry'leri çek
      final allEntries = await FirestoreService.getAllEntries();
      final formattedAllEntries = allEntries.map((entry) {
        return {
          'createdAt': entry.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
          'notes': entry.notes ?? '',
          'ownerName': entry.ownerName,
          'amount': entry.amount,
          'description': entry.description,
          'fileUrl': entry.fileUrl,
        };
      }).toList();

      // Tüm sabit giderleri çek
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

      // Kullanıcının entry'lerini çek (my entries Excel için)
      final currentUserId = widget.currentUser?.userId;
      List<Map<String, dynamic>> formattedMyEntries = [];
      if (currentUserId != null) {
        final myEntries = await FirestoreService.getMyEntries(currentUserId);
        formattedMyEntries = myEntries.map((entry) {
          return {
            'createdAt': entry.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
            'notes': entry.notes ?? '',
            'ownerName': entry.ownerName,
            'amount': entry.amount,
            'description': entry.description,
            'fileUrl': entry.fileUrl,
          };
        }).toList();
      }

      // Tüm Excel dosyalarını paralel olarak güncelle
      await Future.wait([
        // Tüm entry'ler Excel'i
        UploadService.initializeGoogleSheetsWithEntries(formattedAllEntries).catchError((e) {
          AppLogger.warning('Tüm entry\'ler Excel güncellenirken hata: $e');
          return null;
        }),
        // Kullanıcının entry'leri Excel'i (varsa)
        if (formattedMyEntries.isNotEmpty)
          UploadService.createMyEntriesExcel(formattedMyEntries, widget.currentUser?.fullName).catchError((e) {
            AppLogger.warning('Kullanıcı entry\'leri Excel güncellenirken hata: $e');
            return null;
          }),
        // Sabit giderler Excel'i
        UploadService.initializeGoogleSheetsWithFixedExpenses(formattedFixedExpenses).catchError((e) {
          AppLogger.warning('Sabit giderler Excel güncellenirken hata: $e');
          return null;
        }),
        // Tüm veriler Excel'i (settings)
        UploadService.initializeGoogleSheetsWithAllData(formattedAllEntries, formattedFixedExpenses).catchError((e) {
          AppLogger.warning('Tüm veriler Excel güncellenirken hata: $e');
          return null;
        }),
      ], eagerError: false);

      AppLogger.info('Excel dosyaları güncellendi (${formattedAllEntries.length} entry, ${formattedFixedExpenses.length} sabit gider)');
    } catch (e) {
      AppLogger.warning('Excel dosyaları güncellenirken genel hata: $e');
    }
  }

  Widget _buildContent(ThemeData theme, bool isSmallScreen) {
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
              // Başlık
              Text(
                'Tüm Eklenenler',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(width: 8),
              // Arama - Flexible ile taşmayı önle
              Flexible(
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
              const SizedBox(width: 8),
              // Sıralama butonu
              PopupMenuButton<SortOption>(
                icon: Icon(
                  Icons.sort_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                tooltip: 'Sırala',
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
                    value: SortOption.dateDesc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_downward,
                          size: 18,
                          color: _sortOption == SortOption.dateDesc
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('Tarih (Yeni → Eski)'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: SortOption.dateAsc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_upward,
                          size: 18,
                          color: _sortOption == SortOption.dateAsc
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('Tarih (Eski → Yeni)'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: SortOption.amountDesc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_downward,
                          size: 18,
                          color: _sortOption == SortOption.amountDesc
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('Miktar (Yüksek → Düşük)'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: SortOption.amountAsc,
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_upward,
                          size: 18,
                          color: _sortOption == SortOption.amountAsc
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
              const SizedBox(width: 8),
              // Filtre butonu
              StreamBuilder<List<String>>(
                stream: FirestoreService.streamAllOwnerNames(),
                builder: (context, ownerNamesSnapshot) {
                  final ownerNames = ownerNamesSnapshot.data ?? [];
                  return IconButton(
                    icon: Stack(
                      children: [
                        Icon(
                          Icons.tune_rounded,
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
                    onPressed: () => _showFilterDialog(context, theme, ownerNames),
                  );
                },
              ),
            ],
          ),
        ),
        // Liste
        Expanded(
          child: StreamBuilder<List<ExpenseEntry>>(
            stream: FirestoreService.streamAllEntries(),
            builder: (context, snapshot) {
              // Sadece ilk yüklemede loading göster
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const LoadingWidget(message: 'Kayıtlar yükleniyor...');
              }

              if (snapshot.hasError) {
                final errorMessage = snapshot.error.toString();
                AppLogger.error('AllEntriesTab StreamBuilder hatası', snapshot.error);
                
                String userMessage = 'Veriler yüklenirken bir hata oluştu';
                if (errorMessage.contains('permission') || errorMessage.contains('Permission') || errorMessage.contains('permission-denied')) {
                  userMessage = 'Firestore erişim izni hatası. Lütfen çıkış yapıp tekrar giriş yapın. Sorun devam ederse Firebase Console\'da güvenlik kurallarını kontrol edin.';
                } else if (errorMessage.contains('index') || errorMessage.contains('Index')) {
                  userMessage = 'Firestore index hatası. Lütfen Firebase Console\'da gerekli index\'i oluşturun.';
                }
                
                return ErrorRetryWidget(
                  message: userMessage,
                  onRetry: () async {
                    // Permission hatası durumunda token'ı yenile
                    if (errorMessage.contains('permission') || errorMessage.contains('Permission') || errorMessage.contains('permission-denied')) {
                      try {
                        final currentUser = FirebaseAuth.instance.currentUser;
                        if (currentUser != null) {
                          await currentUser.getIdToken(true);
                          AppLogger.info('Token yenilendi - StreamBuilder yeniden denenecek');
                        }
                      } catch (e) {
                        AppLogger.error('Token yenileme hatası', e);
                      }
                    }
                    // StreamBuilder otomatik yeniden deneyecek
                  },
                );
              }

              final allEntries = snapshot.data ?? [];
              final filteredEntries = _filterEntries(allEntries);

              if (allEntries.isEmpty) {
                return EmptyStateWidget(
                  title: 'Henüz kayıt yok',
                  subtitle: 'İlk kaydı eklemek için "Ekleme" sekmesini kullanın',
                  icon: Icons.receipt_long,
                );
              }

              if (filteredEntries.isEmpty) {
                return EmptyStateWidget(
                  title: 'Arama/Filtre sonucu bulunamadı',
                  subtitle: 'Farklı bir arama terimi veya filtre deneyin',
                  icon: Icons.search_off,
                );
              }

              // Toplam hesapla
              final totalAmount = filteredEntries.fold<double>(
                0.0,
                (sum, entry) => sum + entry.amount,
              );

              return RefreshIndicator(
                onRefresh: () async {
                  await Future.delayed(const Duration(milliseconds: 500));
                },
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  shrinkWrap: false,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filteredEntries.length + (filteredEntries.isNotEmpty ? 1 : 0),
                  cacheExtent: AppConfig.listViewCacheExtent.toDouble(),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  itemBuilder: (context, index) {
                    // İlk item toplam kartı
                    if (index == 0 && filteredEntries.isNotEmpty) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12, top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
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
                                  _getActiveFilterCount() > 0 ? 'Filtrelenmiş Toplam' : 'Toplam',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              NumberFormat.currency(
                                symbol: '₺',
                                decimalDigits: 2,
                                locale: 'tr_TR',
                              ).format(totalAmount),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    
                    // Entry item'ları (index - 1 çünkü ilk item toplam kartı)
                    final entryIndex = filteredEntries.isNotEmpty ? index - 1 : index;
                    final entry = widget.currentUser != null && 
                                 filteredEntries[entryIndex].ownerId == widget.currentUser!.userId &&
                                 filteredEntries[entryIndex].ownerName.isEmpty
                      ? filteredEntries[entryIndex].copyWith(ownerName: widget.currentUser!.fullName)
                      : filteredEntries[entryIndex];
                    
                    // Sadece entry'nin sahibi silme yapabilir
                    final canDelete = widget.currentUser != null && 
                                    entry.ownerId == widget.currentUser!.userId;
                    
                    return RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: EntryCard(
                          entry: entry,
                          onDelete: canDelete ? () => _deleteEntry(context, entry) : null,
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
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      body: _buildContent(theme, isSmallScreen),
      floatingActionButton: FloatingActionButton(
        heroTag: 'all_entries_excel_fab',
        onPressed: () => _openExcel(context),
        tooltip: 'Excel',
        child: const Icon(Icons.table_chart_rounded),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    );
  }
}

