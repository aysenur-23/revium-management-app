/// Tüm Eklenenler sekmesi
/// Tüm kullanıcıların kayıtlarını gösterir ve filtreleme yapar
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/firestore_service.dart';
import '../../services/upload_service.dart';
import '../../widgets/entry_card_v2.dart';
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
  String? _selectedEntryTypeFilter; // 'expense', 'income', null (hepsi)
  DateTimeRange? _selectedDateRange;
  final TextEditingController _searchController = TextEditingController();
  SortOption _sortOption = SortOption.dateDesc;
  
  // Gelişmiş tarih filtresi
  DateFilterType _dateFilterType = DateFilterType.all;
  DateTime? _selectedMonth;
  int? _selectedYear;
  DateTime? _selectedDay;
  
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

  Future<void> _openIncomeExcel(BuildContext context) async {
    try {
      AppLogger.info('📊 Ortak Gelirleri Excel açma işlemi başlatıldı');
      
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
                    Text('Ortak Gelirleri Excel hazırlanıyor...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // Eksiksiz içerik: tüm ortak gelir kayıtları alınır, Excel'e yazılır, sonra açılır
      AppLogger.info('Firestore\'dan ortak gelirleri alınıyor...');
      final incomeEntries = await FirestoreService.getEntriesByType('income');
      AppLogger.info('${incomeEntries.length} ortak geliri bulundu');

      if (incomeEntries.isEmpty) {
        if (!mounted) return;
        Navigator.of(context).pop(); // Loading dialog'u kapat
        AppLogger.warning('Ortak geliri bulunamadı');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Henüz ortak geliri kaydı bulunmuyor.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Ortak gelirleri için Excel oluştur
      final formattedIncomeEntries = incomeEntries.map((entry) {
        return {
          'createdAt': entry.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
          'notes': entry.notes ?? '',
          'ownerName': entry.ownerName,
          'amount': entry.amount,
          'description': entry.description,
          'fileUrl': entry.fileUrl,
        };
      }).toList();

      // Loading mesajını güncelle
      if (mounted) {
        Navigator.of(context).pop(); // İlk loading dialog'u kapat
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
                    Text('Excel oluşturuluyor...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final result = await UploadService.createIncomeEntriesExcel(formattedIncomeEntries);

      if (!mounted) return;
      Navigator.of(context).pop(); // Loading dialog'u kapat

      if (result != null && result['url'] != null) {
        // Excel URL'ini aç
        final url = result['url'] as String;
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          AppLogger.success('✅ Ortak Gelirleri Excel başarıyla açıldı');
        } else {
          throw Exception('Excel URL\'si açılamadı');
        }
      } else {
        throw Exception('Excel oluşturulamadı');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Ortak Gelirleri Excel açma hatası', e, stackTrace);
      if (mounted) {
        // Loading dialog'u kapat (eğer açıksa)
        try {
          Navigator.of(context).pop();
        } catch (_) {
          // Dialog zaten kapalı olabilir
        }
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

  // Google Sheets açma işlemleri HomeScreen'e taşındı.


  List<ExpenseEntry> _filterEntries(List<ExpenseEntry> entries) {
    var filtered = entries;

    // Kişi filtresi
    if (_selectedOwnerFilter != null && _selectedOwnerFilter != 'Hepsi') {
      filtered = filtered
          .where((entry) => entry.ownerName == _selectedOwnerFilter)
          .toList();
    }

    // Gelir/Gider filtresi
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

  /// Ay seçimi (Hesaplamalar sayfasındaki gibi)
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
              // Tüm Zamanlar seçeneği
              ListTile(
                leading: Radio<DateTime?>(
                  value: null,
                  // ignore: deprecated_member_use
                  groupValue: _selectedMonth,
                  // ignore: deprecated_member_use
                  onChanged: (value) {
                    Navigator.of(ctx).pop(null);
                  },
                ),
                title: const Text('Tüm Zamanlar'),
                onTap: () {
                  Navigator.of(ctx).pop(null);
                },
              ),
              const Divider(height: 1),
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
                    final isSelected = selectedMonthIndex == index && 
                                     _selectedMonth != null &&
                                     _selectedMonth!.year == selectedYear;
                    final isFuture = selectedYear == now.year && index > now.month - 1;
                    final isPast = selectedYear < 2024 || 
                                  (selectedYear == 2024 && index < 10); // Kasım 2024'ten önce
                    
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
      // Tüm Zamanlar seçildi
      setState(() {
        _dateFilterType = DateFilterType.all;
        _selectedMonth = null;
        _selectedYear = null;
        _selectedDay = null;
        _selectedDateRange = null;
      });
    } else {
      // Ay seçildi
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

  /// Tarih filtresi seçenekleri (Hesaplamalar sayfasındaki gibi)
  void _showDateFilterOptions(BuildContext context, ThemeData theme) {
    // Direkt ay seçim bottom sheet'ini aç (hesaplamalardaki gibi)
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
    if (_dateFilterType == DateFilterType.month && _selectedMonth != null) {
      return DateFormat('MMMM yyyy', 'tr_TR').format(_selectedMonth!);
    }
    if (_dateFilterType == DateFilterType.month) return 'Ay Seç';
    if (_dateFilterType == DateFilterType.year && _selectedYear != null) {
      return '$_selectedYear';
    }
    if (_dateFilterType == DateFilterType.year) return 'Yıl Seç';
    if (_dateFilterType == DateFilterType.day && _selectedDay != null) {
      return DateFormat('d MMM yyyy', 'tr_TR').format(_selectedDay!);
    }
    if (_dateFilterType == DateFilterType.day) return 'Gün Seç';
    if (_dateFilterType == DateFilterType.custom && _selectedDateRange != null) {
      return '${DateFormat('d MMM', 'tr_TR').format(_selectedDateRange!.start)} - ${DateFormat('d MMM yyyy', 'tr_TR').format(_selectedDateRange!.end)}';
    }
    if (_dateFilterType == DateFilterType.custom) return 'Tarih Aralığı Seç';
    return 'Tüm Zamanlar';
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
        child: SingleChildScrollView(
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
              // ignore: deprecated_member_use
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
            // Gelir/Gider filtresi
            Text(
              'Gelir/Gider',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _selectedEntryTypeFilter ?? 'Hepsi',
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              items: const [
                DropdownMenuItem<String>(
                  value: 'Hepsi',
                  child: Text('Hepsi'),
                ),
                DropdownMenuItem<String>(
                  value: 'expense',
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Gider'),
                    ],
                  ),
                ),
                DropdownMenuItem<String>(
                  value: 'income',
                  child: Row(
                    children: [
                      Icon(Icons.trending_up, size: 18, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Gelir'),
                    ],
                  ),
                ),
                DropdownMenuItem<String>(
                  value: 'tax_deductible',
                  child: Row(
                    children: [
                      Icon(Icons.assignment_turned_in, size: 18, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Vergiden Düşülecek'),
                    ],
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedEntryTypeFilter = value;
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
            // Tarih filtresi chip (Hesaplamalar sayfasındaki gibi)
            Material(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
              elevation: 1,
              shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.1),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  Navigator.of(context).pop();
                  _selectMonth(context, theme);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _dateFilterType == DateFilterType.all 
                            ? Icons.all_inclusive_rounded 
                            : Icons.calendar_month_rounded,
                        size: 20,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _dateFilterType == DateFilterType.all
                              ? 'Tüm Zamanlar'
                              : (_selectedMonth != null 
                                  ? DateFormat('MMMM yyyy', 'tr_TR').format(_selectedMonth!)
                                  : 'Ay Seç'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            letterSpacing: 0.2,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 22,
                        color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                    ],
                  ),
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
                    _selectedEntryTypeFilter = null;
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
      ),
    );
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedOwnerFilter != null && _selectedOwnerFilter != 'Hepsi') {
      count++;
    }
    if (_selectedEntryTypeFilter != null && _selectedEntryTypeFilter != 'Hepsi') {
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
          ),
        );
      }
      return;
    }

    // 1. Onay al
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kayıt Sil'),
        content: Text('Bu kaydı silmek istediğinizden emin misiniz?\n\n${entry.description} - ₺${entry.amount.toStringAsFixed(2)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true || entry.id == null) return;

    try {
      // 2. Firestore'dan sil
      await FirestoreService.deleteEntry(entry.id!, widget.currentUser!.userId);
      
      // 3. Excel'leri arka planda güncelle
      _updateExcelFilesInBackground();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kayıt başarıyla silindi'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Silme hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Seçili kayıtları toplu sil
  Future<void> _deleteSelectedEntries(BuildContext context) async {
    final count = _selectedEntryIds.length;
    if (count == 0 || widget.currentUser == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Toplu Sil'),
        content: Text('$count kaydı silmek istediğinizden emin misiniz?\n\nNot: Sadece kendi oluşturduğunuz kayıtlar silinecektir.'),
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
      final result = await FirestoreService.deleteEntriesBatch(selectedIds, widget.currentUser!.userId);
      final deleted = result['deleted'] ?? 0;
      final skipped = result['skipped'] ?? 0;

      if (context.mounted) {
        Navigator.of(context).pop(); // Loading kapat
        setState(() {
          _isSelectionMode = false;
          _selectedEntryIds.clear();
        });

        String message;
        Color bgColor;
        if (deleted > 0 && skipped == 0) {
          message = '$deleted kayıt başarıyla silindi';
          bgColor = Colors.green;
        } else if (deleted > 0 && skipped > 0) {
          message = '$deleted kayıt silindi. $skipped kayıt başka kullanıcıya ait olduğu için atlandı.';
          bgColor = Colors.orange;
        } else {
          message = 'Seçilen kayıtlar size ait değil. Sadece kendi oluşturduğunuz kayıtları silebilirsiniz.';
          bgColor = Colors.orange;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: bgColor,
          ),
        );
      }

      // Excel dosyalarını güncelle
      if (deleted > 0) {
        _updateExcelFilesInBackground();
      }
    } catch (e) {
      if (context.mounted) {
        try { Navigator.of(context).pop(); } catch (_) {} // Loading kapat
        final errorMsg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Excel dosyalarını arka planda güncelle (entry silindikten sonra)
  Future<void> _updateExcelFilesInBackground() async {
    try {
      // 1. Aktif Kayıtları Çek
      final activeEntries = await FirestoreService.getActiveEntries();

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

      // Kullanıcının kendi kayıtlarını filtrele (My Entries Excel için)
      final currentUserId = widget.currentUser?.userId;
      List<Map<String, dynamic>> formattedMyActiveEntries = [];
      
      if (currentUserId != null) {
        final myActive = activeEntries.where((e) => e.ownerId == currentUserId).toList();
        formattedMyActiveEntries = format(myActive);
      }

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

      // 4. Tüm Excel dosyalarını SIRALI olarak güncelle
      
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
      if (currentUserId != null) {
        try {
          await UploadService.createExcelFile(
            entries: formattedMyActiveEntries,
            fileName: widget.currentUser?.fullName != null 
                ? '${widget.currentUser!.fullName} Eklediklerim.csv' 
                : 'Eklediklerim.csv'
          );
        } catch (e) {
          AppLogger.warning('Kullanıcı entry\'leri Excel güncellenirken hata: $e');
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 4. Tüm Excel dosyalarını SIRALI olarak güncelle (API Rate Limit önlemi)
      
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
              // Dönem chip'i (Ay / Yıl / Tüm Zamanlar) — her zaman görünür, tıklanınca filtre açılır
              Material(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _selectMonth(context, theme),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 10 : 14,
                      vertical: isSmallScreen ? 6 : 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getDateFilterIcon(),
                          size: isSmallScreen ? 16 : 18,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        SizedBox(width: isSmallScreen ? 4 : 6),
                        Flexible(
                          child: Text(
                            _getDateFilterText(),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                              fontSize: isSmallScreen ? 11 : 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down_rounded,
                          size: isSmallScreen ? 18 : 20,
                          color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Başlık (mobilde gizle veya küçült)
              if (!isSmallScreen)
                Text(
                  'Tüm Eklenenler',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              if (!isSmallScreen) const SizedBox(width: 8),
              // Ay filtresi seçiliyse önceki/sonraki butonları göster (dönem zaten chip'te)
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
                    // Gelecek aya geçilemez
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
              // Arama - Expanded ile taşmayı önle
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
              PopupMenuButton<SortOption>(
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
              SizedBox(width: isSmallScreen ? 4 : 8),
              // Filtre butonu
              StreamBuilder<List<String>>(
                stream: FirestoreService.streamAllOwnerNames(),
                builder: (context, ownerNamesSnapshot) {
                  final ownerNames = ownerNamesSnapshot.data ?? [];
                  return IconButton(
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
                return const EmptyStateWidget(
                  title: 'Henüz kayıt yok',
                  subtitle: 'İlk kaydı eklemek için "Ekleme" sekmesini kullanın',
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

              // Gelir ve gider toplamlarını hesapla (vergiden düşülecekler hariç)
              final totalIncome = filteredEntries
                  .where((entry) => entry.entryType == 'income')
                  .fold<double>(0.0, (sum, entry) => sum + entry.amount);
              
              final totalExpense = filteredEntries
                  .where((entry) => entry.entryType == 'expense')
                  .fold<double>(0.0, (sum, entry) => sum + entry.amount);
              
              // Vergiden düşülecek toplamı
              final totalTaxDeductible = filteredEntries
                  .where((entry) => entry.entryType == 'tax_deductible')
                  .fold<double>(0.0, (sum, entry) => sum + entry.amount);
              
              // Net sonuç (gelir - gider) - vergiden düşülecekler hariç
              final netResult = totalIncome - totalExpense;

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
                                      _getActiveFilterCount() > 0 ? 'Filtrelenmiş Toplam' : 'Toplam',
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
                            const SizedBox(height: 8),
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
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      body: _buildContent(theme, isSmallScreen),
      bottomNavigationBar: _isSelectionMode 
          ? StreamBuilder(
              stream: FirestoreService.streamAllEntries(),
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

