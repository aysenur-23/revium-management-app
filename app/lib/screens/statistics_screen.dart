import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'dart:async';
import '../services/firestore_service.dart';
import '../services/google_sheets_service.dart';
import '../models/expense_entry.dart';
import '../models/fixed_expense.dart';
import '../models/user_profile.dart';
import '../utils/app_logger.dart';

class StatisticsScreen extends StatefulWidget {
  final UserProfile currentUser;

  const StatisticsScreen({
    super.key,
    required this.currentUser,
  });

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  DateTime? _selectedDate; // null = Tümü, değer = Seçili tarih
  bool _hasSelectedDay = false; // Gün seçildi mi?
  bool _isYearOnly = false; // Sadece yıl mı seçildi?
  bool _hasReceivedData = false; // İlk veri geldi mi kontrolü
  List<FixedExpense> _fixedExpenses = []; // Sabit giderler
  Timer? _refreshTimer;
  
  // Cache için
  List<ExpenseEntry>? _cachedFixedExpenseEntries;
  DateTime? _cachedDate;
  bool _cachedHasSelectedDay = false;
  bool _cachedIsYearOnly = false;

  @override
  void initState() {
    super.initState();
    // Sabit giderleri arka planda yükle, sayfa açılmasını bloklamasın
    _loadFixedExpenses();
    // Her 30 saniyede bir otomatik yenile
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadFixedExpenses();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Sabit giderleri yükler (async, bloklamaz)
  Future<void> _loadFixedExpenses() async {
    // İlk yüklemede loading gösterme, arka planda yükle
    try {
      final expenses = await GoogleSheetsService.getFixedExpenses();
      if (mounted) {
        setState(() {
          _fixedExpenses = expenses.where((e) => e.isActive).toList();
          // Cache'i temizle, yeniden hesaplanacak
          _cachedFixedExpenseEntries = null;
        });
        AppLogger.info('✅ ${_fixedExpenses.length} aktif sabit gider istatistiklere eklendi');
      }
    } catch (e) {
      AppLogger.error('Sabit giderler yüklenirken hata', e);
      if (mounted) {
        setState(() {
          // Hata durumunda boş liste kullan (istatistikler yine de gösterilebilir)
          _fixedExpenses = [];
          _cachedFixedExpenseEntries = null;
        });
      }
    }
  }

  /// Sabit giderleri ExpenseEntry'lere dönüştürür (tarih filtrelemesi için)
  /// Cache kullanarak performansı artırır
  List<ExpenseEntry> _convertFixedExpensesToEntries() {
    // Cache kontrolü - aynı parametrelerle daha önce hesaplanmışsa cache'den dön
    if (_cachedFixedExpenseEntries != null &&
        _cachedDate == _selectedDate &&
        _cachedHasSelectedDay == _hasSelectedDay &&
        _cachedIsYearOnly == _isYearOnly) {
      AppLogger.debug('📊 Cache\'den sabit gider entry\'leri döndürülüyor: ${_cachedFixedExpenseEntries!.length}');
      return _cachedFixedExpenseEntries!;
    }

    final now = DateTime.now();
    final entries = <ExpenseEntry>[];

    AppLogger.debug('📊 _convertFixedExpensesToEntries: ${_fixedExpenses.length} sabit gider var, tarih: ${_selectedDate?.toString() ?? "null"}, gün seçili: $_hasSelectedDay, yıl seçili: $_isYearOnly');

    for (final expense in _fixedExpenses) {
      if (!expense.isActive) {
        AppLogger.debug('⏭️ Sabit gider pasif, atlanıyor: ${expense.description}');
        continue;
      }

      // Tarih filtrelemesi
      if (_selectedDate != null) {
        if (_hasSelectedDay) {
          // Gün seçilmişse: Sadece aylık sabit giderler için o günü ekle
          if (expense.recurrence == 'monthly' || expense.recurrence == null) {
            // Aylık sabit giderler için seçilen günün ayına uygun olanları ekle
            if (expense.startDate == null ||
                (expense.startDate!.year <= _selectedDate!.year &&
                 expense.startDate!.month <= _selectedDate!.month)) {
              entries.add(ExpenseEntry(
                ownerId: expense.ownerId,
                ownerName: expense.ownerName,
                description: expense.description,
                notes: expense.notes,
                amount: expense.amount,
                fileUrl: '',
                fileType: 'image',
                driveFileId: '',
                fixedExpenseId: expense.id,
                createdAt: DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day),
              ));
            }
          }
        } else if (_isYearOnly) {
          // Yıl seçilmişse: Yıllık ve aylık sabit giderler için
          if (expense.recurrence == 'yearly') {
            if (expense.startDate == null || expense.startDate!.year <= _selectedDate!.year) {
              entries.add(ExpenseEntry(
                ownerId: expense.ownerId,
                ownerName: expense.ownerName,
                description: expense.description,
                notes: expense.notes,
                amount: expense.amount,
                fileUrl: '',
                fileType: 'image',
                driveFileId: '',
                fixedExpenseId: expense.id,
                createdAt: DateTime(_selectedDate!.year, 1, 1),
              ));
            }
          } else if (expense.recurrence == 'monthly' || expense.recurrence == null) {
            // Aylık sabit giderler için yılın her ayı için ekle
            if (expense.startDate == null || expense.startDate!.year <= _selectedDate!.year) {
              for (int month = 1; month <= 12; month++) {
                entries.add(ExpenseEntry(
                  ownerId: expense.ownerId,
                  ownerName: expense.ownerName,
                  description: expense.description,
                  notes: expense.notes,
                  amount: expense.amount,
                  fileUrl: '',
                  fileType: 'image',
                  driveFileId: '',
                  fixedExpenseId: expense.id,
                  createdAt: DateTime(_selectedDate!.year, month, 1),
                ));
              }
            }
          }
        } else {
          // Ay seçilmişse: Sadece aylık sabit giderler için
          if (expense.recurrence == 'monthly' || expense.recurrence == null) {
            if (expense.startDate == null ||
                (expense.startDate!.year <= _selectedDate!.year &&
                 expense.startDate!.month <= _selectedDate!.month)) {
              entries.add(ExpenseEntry(
                ownerId: expense.ownerId,
                ownerName: expense.ownerName,
                description: expense.description,
                notes: expense.notes,
                amount: expense.amount,
                fileUrl: '',
                fileType: 'image',
                driveFileId: '',
                fixedExpenseId: expense.id,
                createdAt: DateTime(_selectedDate!.year, _selectedDate!.month, 1),
              ));
            }
          }
        }
      } else {
        // Tarih seçilmemişse: Tüm aktif sabit giderleri ekle (aylık için 12 ay, yıllık için 1 kez)
        if (expense.recurrence == 'yearly') {
          entries.add(ExpenseEntry(
            ownerId: expense.ownerId,
            ownerName: expense.ownerName,
            description: expense.description,
            notes: expense.notes,
            amount: expense.amount,
            fileUrl: '',
            fileType: 'image',
            driveFileId: '',
            fixedExpenseId: expense.id,
            createdAt: expense.startDate ?? now,
          ));
        } else {
          // Aylık veya belirtilmemiş: Son 12 ay için ekle
          for (int i = 0; i < 12; i++) {
            final date = DateTime(now.year, now.month - i, 1);
            if (expense.startDate == null || expense.startDate!.isBefore(date) || expense.startDate!.isAtSameMomentAs(date)) {
              entries.add(ExpenseEntry(
                ownerId: expense.ownerId,
                ownerName: expense.ownerName,
                description: expense.description,
                notes: expense.notes,
                amount: expense.amount,
                fileUrl: '',
                fileType: 'image',
                driveFileId: '',
                fixedExpenseId: expense.id,
                createdAt: date,
              ));
            }
          }
        }
      }
    }

    AppLogger.debug('📊 _convertFixedExpensesToEntries: ${entries.length} entry oluşturuldu');
    
    // Cache'e kaydet
    _cachedFixedExpenseEntries = entries;
    _cachedDate = _selectedDate;
    _cachedHasSelectedDay = _hasSelectedDay;
    _cachedIsYearOnly = _isYearOnly;
    
    return entries;
  }

  List<ExpenseEntry> _getFilteredEntries(List<ExpenseEntry> allEntries) {
    // Sabit giderleri ekle
    final fixedExpenseEntries = _convertFixedExpensesToEntries();
    AppLogger.debug('📊 _getFilteredEntries: ${allEntries.length} Firestore entry + ${fixedExpenseEntries.length} sabit gider entry = ${allEntries.length + fixedExpenseEntries.length} toplam');
    final combinedEntries = [...allEntries, ...fixedExpenseEntries];

    // Eğer tarih seçilmemişse (null), tüm kayıtları döndür
    if (_selectedDate == null) {
      return combinedEntries;
    }
    
    if (_hasSelectedDay) {
      // Gün seçilmişse: Sadece o günü filtrele
      final startDate = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      final endDate = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, 23, 59, 59, 999);

      return combinedEntries.where((entry) {
        if (entry.createdAt == null) return false;
        return entry.createdAt!.isAfter(startDate.subtract(const Duration(milliseconds: 1))) &&
               entry.createdAt!.isBefore(endDate.add(const Duration(milliseconds: 1)));
      }).toList();
    } else if (_isYearOnly) {
      // Yıl seçilmişse: O yılın tamamını filtrele
      final startDate = DateTime(_selectedDate!.year, 1, 1);
      final endDate = DateTime(_selectedDate!.year, 12, 31, 23, 59, 59, 999);

      return combinedEntries.where((entry) {
        if (entry.createdAt == null) return false;
        return entry.createdAt!.isAfter(startDate.subtract(const Duration(milliseconds: 1))) &&
               entry.createdAt!.isBefore(endDate.add(const Duration(milliseconds: 1)));
      }).toList();
    } else {
      // Ay seçilmişse: O ayın tamamını filtrele
      final startDate = DateTime(_selectedDate!.year, _selectedDate!.month, 1);
      final endDate = DateTime(_selectedDate!.year, _selectedDate!.month + 1, 0, 23, 59, 59, 999);

      return combinedEntries.where((entry) {
        if (entry.createdAt == null) return false;
        return entry.createdAt!.isAfter(startDate.subtract(const Duration(milliseconds: 1))) &&
               entry.createdAt!.isBefore(endDate.add(const Duration(milliseconds: 1)));
      }).toList();
    }
  }

  Future<void> _selectDate() async {
    if (!mounted) return;
    
    final theme = Theme.of(context);
    
    // Modal bottom sheet ile filtreleme seçenekleri
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Dönem Seçin',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            // Tümü
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.all_inclusive_rounded, color: theme.colorScheme.primary, size: 20),
              ),
              title: const Text('Tüm Zamanlar', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Tüm kayıtları göster'),
              onTap: () => Navigator.of(ctx).pop('all'),
            ),
            const Divider(height: 1, indent: 72),
            // Aylık (Öncelikli)
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calendar_month_rounded, color: Colors.blue, size: 20),
              ),
              title: const Text('Aylık', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Bir ay seçin'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Önerilen', style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w600)),
              ),
              onTap: () => Navigator.of(ctx).pop('month'),
            ),
            const Divider(height: 1, indent: 72),
            // Yıllık
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calendar_today_rounded, color: Colors.green, size: 20),
              ),
              title: const Text('Yıllık', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Bir yıl seçin'),
              onTap: () => Navigator.of(ctx).pop('year'),
            ),
            const Divider(height: 1, indent: 72),
            // Günlük
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.today_rounded, color: Colors.orange, size: 20),
              ),
              title: const Text('Günlük', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Belirli bir gün seçin'),
              onTap: () => Navigator.of(ctx).pop('day'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (!mounted || result == null) return;

    if (result == 'all') {
      setState(() {
        _selectedDate = null;
        _hasSelectedDay = false;
      });
    } else if (result == 'month') {
      // Ay seçimi için özel picker
      await _selectMonth();
    } else if (result == 'year') {
      // Yıl seçimi
      await _selectYear();
    } else if (result == 'day') {
      // Gün seçimi
      final DateTime? pickedDate = await showDatePicker(
        context: context,
        initialDate: _selectedDate ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        locale: const Locale('tr', 'TR'),
        helpText: 'Gün Seçin',
        cancelText: 'İptal',
        confirmText: 'Seç',
      );

      if (!mounted) return;

      if (pickedDate != null) {
        setState(() {
          _selectedDate = pickedDate;
          _hasSelectedDay = true;
          _isYearOnly = false;
        });
      }
    }
  }

  Future<void> _selectMonth() async {
    final now = DateTime.now();
    int selectedYear = _selectedDate?.year ?? now.year;
    int selectedMonth = _selectedDate?.month ?? now.month;
    final theme = Theme.of(context);

    final result = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
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
              // Title with year selector
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: selectedYear > 2020 ? () {
                        setModalState(() => selectedYear--);
                      } : null,
                    ),
                    Text(
                      '$selectedYear',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: selectedYear < now.year ? () {
                        setModalState(() => selectedYear++);
                      } : null,
                    ),
                  ],
                ),
              ),
              // Month grid
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    final month = index + 1;
                    final isSelected = selectedMonth == month && (_selectedDate?.year == selectedYear);
                    final isFuture = selectedYear == now.year && month > now.month;
                    final monthNames = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 
                                        'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
                    
                    return Material(
                      color: isSelected 
                          ? theme.colorScheme.primary 
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: isFuture ? null : () {
                          Navigator.of(ctx).pop(DateTime(selectedYear, month, 1));
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Center(
                          child: Text(
                            monthNames[index],
                            style: TextStyle(
                              color: isFuture 
                                  ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                                  : isSelected 
                                      ? theme.colorScheme.onPrimary 
                                      : theme.colorScheme.onSurface,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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

    if (!mounted || result == null) return;

    setState(() {
      _selectedDate = result;
      _hasSelectedDay = false;
      _isYearOnly = false;
    });
  }

  Future<void> _selectYear() async {
    final now = DateTime.now();
    final theme = Theme.of(context);
    final years = List.generate(now.year - 2019, (i) => 2020 + i);

    final result = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              padding: const EdgeInsets.all(16),
              child: Text('Yıl Seçin', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            ...years.reversed.map((year) => ListTile(
              leading: Icon(
                year == (_selectedDate?.year) && !_hasSelectedDay && _selectedDate?.month == 1
                    ? Icons.check_circle_rounded 
                    : Icons.circle_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text('$year', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(year == now.year ? 'Bu yıl' : ''),
              onTap: () => Navigator.of(ctx).pop(year),
            )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (!mounted || result == null) return;

    setState(() {
      _selectedDate = DateTime(result, 1, 1);
      _hasSelectedDay = false;
      _isYearOnly = true;
    });
  }

  String _calculateDailyAverage(double total, int entryCount) {
    int days;
    if (_selectedDate != null) {
      if (_hasSelectedDay) {
        // Gün seçiliyse, sadece 1 gün
        days = 1;
      } else {
        // Sadece ay seçiliyse, o ayın gün sayısı
        final now = DateTime.now();
        final isCurrentMonth = _selectedDate!.year == now.year && _selectedDate!.month == now.month;
        if (isCurrentMonth) {
          days = now.day; // Şu anki ay ise bugüne kadar olan gün sayısı
        } else {
          days = DateTime(_selectedDate!.year, _selectedDate!.month + 1, 0).day; // Ayın toplam gün sayısı
        }
      }
    } else {
      days = 30; // Tümü seçiliyse varsayılan 30 gün
    }
    
    final dailyAverage = days > 0 && entryCount > 0
        ? total / days
        : 0.0;
    return NumberFormat.currency(
      symbol: '₺',
      decimalDigits: 2,
      locale: 'tr_TR',
    ).format(dailyAverage);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: 56,
        automaticallyImplyLeading: true,
        centerTitle: true,
        title: Text(
          'İstatistikler',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
      ),
      body: StreamBuilder<List<ExpenseEntry>>(
        stream: FirestoreService.streamAllEntries(),
        builder: (context, snapshot) {
          // Hata durumu
          if (snapshot.hasError) {
            final errorMessage = snapshot.error.toString();
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.error_outline_rounded,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'İstatistikler yüklenirken hata oluştu',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      errorMessage.contains('permission') || errorMessage.contains('Permission')
                          ? 'Firestore izin hatası. Lütfen Firestore rules\'ı kontrol edin.'
                          : errorMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          // Loading durumu - sadece ilk yüklemede göster
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData && !_hasReceivedData) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'İstatistikler yükleniyor...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            );
          }

          final allEntries = snapshot.data ?? [];
          
          if (snapshot.hasData && !_hasReceivedData) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _hasReceivedData = true;
                });
              }
            });
          }
          
          final filteredEntries = _getFilteredEntries(allEntries);
          
          // Gerçek entry sayısı (sabit giderlerden oluşturulan entry'ler hariç)
          final realEntryCount = filteredEntries.where((e) => e.fixedExpenseId == null).length;
          
          // Debug: Sabit giderler ve toplam entry sayısını logla
          final realEntries = filteredEntries.where((e) => e.fixedExpenseId == null).toList();
          final realTotal = realEntries.fold(0.0, (sum, entry) => sum + entry.amount);
          
          // Yıllık toplam hesapla: İçinde bulunduğumuz yıl için gerçek harcamalar + Yıllık sabit giderler + Aylık sabit giderler (yıl başından bugüne kadar geçen aylar)
          final now = DateTime.now();
          final yearStart = DateTime(now.year, 1, 1);
          final currentYearRealEntries = allEntries.where((entry) {
            if (entry.createdAt == null) return false;
            return entry.createdAt!.isAfter(yearStart.subtract(const Duration(days: 1))) && 
                   entry.createdAt!.isBefore(now.add(const Duration(days: 1)));
          }).toList();
          final currentYearRealTotal = currentYearRealEntries.fold(0.0, (sum, entry) => sum + entry.amount);
          
          // Yıllık sabit giderler
          final yearlyFixedExpenses = _fixedExpenses.where((e) => e.isActive && e.recurrence == 'yearly').toList();
          final yearlyFixedTotal = yearlyFixedExpenses.fold(0.0, (sum, expense) => sum + expense.amount);
          
          // Aylık sabit giderler (yıl başından bugüne kadar geçen aylar)
          final monthlyFixedExpenses = _fixedExpenses.where((e) => e.isActive && (e.recurrence == 'monthly' || e.recurrence == null)).toList();
          final monthsPassed = now.month; // Yıl başından bugüne kadar geçen ay sayısı
          final monthlyFixedTotal = monthlyFixedExpenses.fold(0.0, (sum, expense) => sum + expense.amount) * monthsPassed;
          
          // Yıllık toplam = İçinde bulunduğumuz yıldaki gerçek harcamalar + Yıllık sabit giderler + Aylık sabit giderler (geçen aylar)
          final yearlyTotal = currentYearRealTotal + yearlyFixedTotal + monthlyFixedTotal;
          
          AppLogger.debug('📊 İstatistikler: ${allEntries.length} Firestore entry, ${_fixedExpenses.length} sabit gider, ${filteredEntries.length} toplam filtrelenmiş entry, ${realEntryCount} gerçek entry');
          AppLogger.debug('📊 Yıllık Toplam: ${now.year} yılı gerçek=${currentYearRealTotal}₺, Yıllık sabit=${yearlyFixedTotal}₺, Aylık sabit (${monthsPassed} ay)=${monthlyFixedTotal}₺, Toplam=${yearlyTotal}₺');
          
          // Seçili filtreye göre toplam
          final total = _selectedDate == null 
              ? yearlyTotal  // Tüm zamanlar seçildiğinde yıllık toplam
              : realTotal;   // Tarih seçildiğinde sadece o dönemin gerçek harcamaları
          final averageAmount = realEntryCount > 0 ? filteredEntries.where((e) => e.fixedExpenseId == null).fold(0.0, (sum, entry) => sum + entry.amount) / realEntryCount : 0.0;
          final entryCount = realEntryCount; // Gerçek entry sayısını kullan

          // Filtreleme metinleri
          final String filterText;
          final String filterSubtext;
          if (_selectedDate == null) {
            filterText = 'Tüm Zamanlar';
            filterSubtext = 'Dönem seçmek için dokunun';
          } else if (_hasSelectedDay) {
            // Gün seçilmişse
            filterText = DateFormat('dd MMMM yyyy', kIsWeb ? null : 'tr_TR').format(_selectedDate!);
            filterSubtext = 'Günlük Görünüm';
          } else if (_isYearOnly) {
            // Yıl seçilmişse
            filterText = '${_selectedDate!.year} Yılı';
            filterSubtext = 'Yıllık Görünüm';
          } else {
            // Ay seçilmişse
            filterText = DateFormat('MMMM yyyy', kIsWeb ? null : 'tr_TR').format(_selectedDate!);
            filterSubtext = 'Aylık Görünüm';
          }

          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Sayfa başlığı ve açıklama
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Harcama Özeti',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Eklediğiniz kayıtların istatistikleri',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                
                // Kompakt filtre kartı
                _PremiumFilterCard(
                  filterText: filterText,
                  filterSubtext: filterSubtext,
                  onTap: _selectDate,
                  theme: theme,
                ),
                const SizedBox(height: 16),
                
                // Ana istatistik kartı - Toplam
                _HeroStatCard(
                  title: _selectedDate == null 
                      ? 'Yıllık Toplam Harcamanız'
                      : (_hasSelectedDay 
                          ? 'Günlük Harcamanız'
                          : (_isYearOnly 
                              ? 'Yıllık Harcamanız'
                              : 'O Ayın Toplam Harcaması')),
                  value: NumberFormat.currency(
                    symbol: '₺',
                    decimalDigits: 2,
                    locale: 'tr_TR',
                  ).format(total),
                  icon: Icons.account_balance_wallet_rounded,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: 0.7),
                    ],
                  ),
                  theme: theme,
                  onTap: () {
                    // Home screen'e dön ve "Tüm Eklenenler" sekmesine geç
                    Navigator.of(context).pop({'tab': 'all_entries'});
                  },
                ),
                const SizedBox(height: 16),
                
                // İkincil istatistikler
                Row(
                  children: [
                    Expanded(
                      child: _CompactStatCard(
                        title: 'Kayıt Başına Ortalama',
                        value: NumberFormat.currency(
                          symbol: '₺',
                          decimalDigits: 0,
                          locale: 'tr_TR',
                        ).format(averageAmount),
                        icon: Icons.trending_up_rounded,
                        color: theme.colorScheme.secondary,
                        theme: theme,
                        onTap: () {
                          // Home screen'e dön ve "Tüm Eklenenler" sekmesine geç
                          Navigator.of(context).pop({'tab': 'all_entries'});
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CompactStatCard(
                        title: 'Toplam Kayıt Sayısı',
                        value: '$entryCount adet',
                        icon: Icons.receipt_long_rounded,
                        color: theme.colorScheme.tertiary,
                        theme: theme,
                        onTap: () {
                          // Home screen'e dön ve "Tüm Eklenenler" sekmesine geç
                          Navigator.of(context).pop({'tab': 'all_entries'});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _CompactStatCard(
                        title: 'Günlük Ortalama',
                        value: _calculateDailyAverage(total, entryCount),
                        icon: Icons.calendar_view_day_rounded,
                        color: Colors.orange,
                        theme: theme,
                        onTap: () {
                          // Home screen'e dön ve "Tüm Eklenenler" sekmesine geç
                          Navigator.of(context).pop({'tab': 'all_entries'});
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CompactStatCard(
                        title: 'En Yüksek Harcama',
                        value: filteredEntries.isEmpty
                            ? '₺0'
                            : NumberFormat.currency(
                                symbol: '₺',
                                decimalDigits: 0,
                                locale: 'tr_TR',
                              ).format(
                                filteredEntries.map((e) => e.amount).reduce((a, b) => a > b ? a : b),
                              ),
                        icon: Icons.arrow_upward_rounded,
                        color: Colors.red,
                        theme: theme,
                        onTap: () {
                          // Home screen'e dön ve "Tüm Eklenenler" sekmesine geç
                          Navigator.of(context).pop({'tab': 'all_entries'});
                        },
                      ),
                    ),
                  ],
                ),
                
                // Ay harcamaları detayı - sadece ay seçilmişse göster (gün veya yıl seçildiyse gösterme)
                if (_selectedDate != null && !_hasSelectedDay && !_isYearOnly) ...[
                  const SizedBox(height: 32),
                  _SectionHeader(
                    title: 'Seçili Ay Harcamaları',
                    theme: theme,
                  ),
                  const SizedBox(height: 16),
                  _MonthlyExpensesCard(
                    realEntries: realEntries,
                    fixedExpenses: _fixedExpenses.where((e) => e.isActive && (e.recurrence == 'monthly' || e.recurrence == null)).toList(),
                    selectedDate: _selectedDate!,
                    theme: theme,
                  ),
                ] else if (_selectedDate == null && filteredEntries.isEmpty) ...[
                  // Sadece tarih seçilmediğinde ve hiç veri yoksa boş durum göster
                  const SizedBox(height: 32),
                  _EmptyStateCard(
                    message: 'Henüz kayıt bulunmuyor',
                    theme: theme,
                  ),
                ] else if (_selectedDate != null && _hasSelectedDay && filteredEntries.isEmpty) ...[
                  // Gün seçildiğinde ve veri yoksa boş durum göster
                  const SizedBox(height: 32),
                  _EmptyStateCard(
                    message: 'Bu tarih için kayıt bulunamadı',
                    theme: theme,
                  ),
                ],
                const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
  }

// Premium Filter Card
class _PremiumFilterCard extends StatelessWidget {
  final String filterText;
  final String filterSubtext;
  final VoidCallback onTap;
  final ThemeData theme;

  const _PremiumFilterCard({
    required this.filterText,
    required this.filterSubtext,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.calendar_month_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        filterSubtext,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        filterText,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          letterSpacing: -0.3,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Hero Stat Card - Ana istatistik
class _HeroStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final LinearGradient gradient;
  final ThemeData theme;
  final VoidCallback? onTap;

  const _HeroStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.gradient,
    required this.theme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: 120, // Kompakt yükseklik
          ),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 28,
                            letterSpacing: -0.8,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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

// Compact Stat Card - Eşit boyutta ve tıklanabilir
class _CompactStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final ThemeData theme;
  final VoidCallback? onTap;

  const _CompactStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.theme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120, // Kompakt yükseklik
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
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: color.withValues(alpha: 0.1),
          highlightColor: color.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        color: color,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                      fontSize: 20,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
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

// Section Header
class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader({
    required this.title,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 22,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

// Monthly Expenses Card - Sabit harcamalar ve gerçek harcamaları listeler
class _MonthlyExpensesCard extends StatelessWidget {
  final List<ExpenseEntry> realEntries;
  final List<FixedExpense> fixedExpenses;
  final DateTime selectedDate;
  final ThemeData theme;

  const _MonthlyExpensesCard({
    required this.realEntries,
    required this.fixedExpenses,
    required this.selectedDate,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // Sabit harcamaları filtrele - sadece seçili ay için geçerli olanlar
    final monthlyFixedExpenses = fixedExpenses.where((expense) {
      if (expense.startDate == null) return true;
      return expense.startDate!.year <= selectedDate.year && 
             expense.startDate!.month <= selectedDate.month;
    }).toList();

    // Gerçek harcamaları tarihe göre sırala
    final sortedRealEntries = List<ExpenseEntry>.from(realEntries)
      ..sort((a, b) {
        if (a.createdAt == null && b.createdAt == null) return 0;
        if (a.createdAt == null) return 1;
        if (b.createdAt == null) return -1;
        return b.createdAt!.compareTo(a.createdAt!);
      });

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sabit Harcamalar bölümü
            if (monthlyFixedExpenses.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sabit Harcamalar',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...monthlyFixedExpenses.map((expense) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.repeat_rounded,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              expense.description,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (expense.notes != null && expense.notes!.isNotEmpty)
                              Text(
                                expense.notes!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        NumberFormat.currency(
                          symbol: '₺',
                          decimalDigits: 2,
                          locale: 'tr_TR',
                        ).format(expense.amount),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (sortedRealEntries.isNotEmpty) ...[
                const SizedBox(height: 20),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
                ),
                const SizedBox(height: 20),
              ],
            ],
            // Gerçek Harcamalar bölümü
            if (sortedRealEntries.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.shopping_cart_rounded,
                    size: 20,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Gerçek Harcamalar',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...sortedRealEntries.take(20).map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          entry.fileType == 'pdf' 
                              ? Icons.picture_as_pdf_rounded 
                              : Icons.image_rounded,
                          size: 20,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.description,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (entry.createdAt != null)
                              Text(
                                DateFormat('dd.MM.yyyy', kIsWeb ? null : 'tr_TR').format(entry.createdAt!),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        NumberFormat.currency(
                          symbol: '₺',
                          decimalDigits: 2,
                          locale: 'tr_TR',
                        ).format(entry.amount),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (sortedRealEntries.length > 20)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    've ${sortedRealEntries.length - 20} harcama daha...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
            // Boş durum
            if (monthlyFixedExpenses.isEmpty && sortedRealEntries.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Bu ay için harcama bulunamadı',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Empty State Card
class _EmptyStateCard extends StatelessWidget {
  final String message;
  final ThemeData theme;

  const _EmptyStateCard({
    required this.message,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bar_chart_rounded,
                size: 48,
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
