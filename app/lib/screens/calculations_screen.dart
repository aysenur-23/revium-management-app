import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/expense_entry.dart';
import '../models/user_profile.dart';
import '../models/fixed_expense.dart';
import '../services/firestore_service.dart';
import '../services/google_sheets_service.dart';
import '../widgets/entry_card_v2.dart';
import '../utils/app_logger.dart';

class CalculationsScreen extends StatefulWidget {
  final UserProfile currentUser;

  const CalculationsScreen({
    super.key,
    required this.currentUser,
  });

  @override
  State<CalculationsScreen> createState() => _CalculationsScreenState();
}

class _CalculationsScreenState extends State<CalculationsScreen> {
  List<ExpenseEntry> _allEntries = [];
  // Gelirler (ortak ödemeleri)
  List<ExpenseEntry> _incomes = [];
  // Vergiden düşülecekler
  List<ExpenseEntry> _taxDeductibles = [];
  List<FixedExpense> _fixedExpenses = []; // Sabit giderler listesi
  bool _isLoading = true;
  DateTime? _selectedMonth; // Seçili ay (null = tüm zamanlar)
  
  // Tüm zamanlar için
  double _totalExpenses = 0.0;
  double _totalIncome = 0.0; // Toplam girdi
  double _totalTaxDeductible = 0.0; // Toplam vergiden düşülecek
  double _netProfit = 0.0; // Net kar (gelir - gider)
  double _averageExpense = 0.0;
  double _maxExpense = 0.0;
  double _minExpense = 0.0;
  // ignore: prefer_final_fields
  Map<String, double> _expensesByUser = {}; // Kullanıcı bazında toplam
  // ignore: prefer_final_fields
  Map<String, double> _incomeByUser = {}; // Kullanıcı bazında toplam girdi
  // ignore: prefer_final_fields
  Map<String, double> _taxDeductibleByUser = {}; // Kullanıcı bazında vergiden düşülecek
  
  // Seçili ay için
  double _monthlyTotalExpenses = 0.0;
  double _monthlyTotalIncome = 0.0;
  double _monthlyTotalTaxDeductible = 0.0;
  double _monthlyNetProfit = 0.0;
  List<ExpenseEntry> _monthlyExpenses = [];
  List<ExpenseEntry> _monthlyIncomes = [];
  List<ExpenseEntry> _monthlyTaxDeductibles = [];
  // ignore: prefer_final_fields
  Map<String, double> _monthlyExpensesByUser = {};
  // ignore: prefer_final_fields
  Map<String, double> _monthlyIncomeByUser = {};
  // ignore: prefer_final_fields
  Map<String, double> _monthlyTaxDeductibleByUser = {};
  
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Varsayılan olarak mevcut ay seçili
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
    // Veriyi bir sonraki frame'de yükle (Navigator kilidini önlemek için)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
    _loadData();
      }
    });
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Entry'leri ve sabit giderleri paralel yükle
      final entriesFuture = FirestoreService.getAllEntries();
      final fixedExpensesFuture = GoogleSheetsService.getFixedExpenses()
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              AppLogger.warning('Sabit giderler yükleme zaman aşımı (30 saniye)');
              return <FixedExpense>[];
            },
          )
          .catchError((e, stackTrace) {
        AppLogger.error('Sabit giderler yüklenirken hata', e, stackTrace);
        AppLogger.warning('Sabit giderler yüklenirken hata (devam ediliyor): $e');
        // Hata mesajını kullanıcıya göster (sadece kritik hatalar için)
        if (mounted && e.toString().contains('timeout') == false) {
          // SnackBar'ı gecikmeli göster (UI bloklamasını önlemek için)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Sabit giderler yüklenemedi: ${e.toString()}'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 5),
                  action: SnackBarAction(
                    label: 'Tekrar Dene',
                    textColor: Colors.white,
                    onPressed: () {
                      _loadData();
                    },
                  ),
                ),
              );
            }
          });
        }
        return <FixedExpense>[];
      });
      
      final entries = await entriesFuture;
      final fixedExpenses = await fixedExpensesFuture;
      
      // Sabit giderleri state'e kaydet
      setState(() {
        _fixedExpenses = fixedExpenses;
      });
      
      AppLogger.info('📊 ${fixedExpenses.length} sabit gider yüklendi');
      
      if (!mounted) return;
      
      // Kasım 2024'ten itibaren filtrele (Tüm Zamanlar için)
      final november2024 = DateTime(2024, 11, 1);
      final filteredEntries = entries.where((entry) {
        if (entry.createdAt == null) return false;
        final entryDate = entry.createdAt!;
        // Kasım 2024'ün ilk gününden itibaren (1 Kasım 2024 dahil)
        return (entryDate.year == 2024 && entryDate.month >= 11) || entryDate.year > 2024;
      }).toList();
      
      // Sabit giderleri filtrele (Kasım 2024'ten itibaren, aktif olanlar)
      final filteredFixedExpenses = fixedExpenses.where((fe) {
        if (!fe.isActive) return false;
        // startDate varsa ve Kasım 2024'ten önceyse dahil etme
        if (fe.startDate != null) {
          final startDate = fe.startDate!;
          if (startDate.year < 2024 || (startDate.year == 2024 && startDate.month < 11)) {
            return false;
          }
        }
        // createdAt varsa ve Kasım 2024'ten önceyse dahil etme
        if (fe.createdAt != null) {
          final createdAt = fe.createdAt!;
          if (createdAt.year < 2024 || (createdAt.year == 2024 && createdAt.month < 11)) {
            return false;
          }
        }
        return true;
      }).toList();

      if (filteredEntries.isEmpty) {
        if (mounted) {
          setState(() {
            _allEntries = [];
            _totalExpenses = 0.0;
            _isLoading = false;
          });
        }
        return;
      }

      // Tarihe göre sırala (en eski en başta)
      filteredEntries.sort((a, b) {
        final aDate = a.createdAt ?? DateTime.now();
        final bDate = b.createdAt ?? DateTime.now();
        return aDate.compareTo(bDate);
      });

      // Harcamaları, girdileri ve vergiden düşülecekleri ayır (Kasım 2024'ten itibaren)
      final expenses = filteredEntries.where((e) => e.entryType == 'expense').toList();
      _incomes = filteredEntries.where((e) => e.entryType == 'income').toList();
      _taxDeductibles = filteredEntries.where((e) => e.entryType == 'tax_deductible').toList();

      // Sabit giderleri hesapla (Tüm Zamanlar için - Kasım 2024'ten bugüne)
      double totalFixedExpenses = 0.0;
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month, 1);
      
      for (var fixedExpense in filteredFixedExpenses) {
        final startDate = fixedExpense.startDate ?? fixedExpense.createdAt ?? november2024;
        final effectiveStartDate = startDate.isBefore(november2024) ? november2024 : startDate;
        final effectiveStartMonth = DateTime(effectiveStartDate.year, effectiveStartDate.month, 1);
        final recurrence = fixedExpense.recurrence?.toLowerCase() ?? 'monthly';
        
        if (recurrence == 'monthly') {
          // Aylık: Kasım 2024'ten bugüne kadar her ay için ekle
          int months = 0;
          DateTime month = effectiveStartMonth;
          while (month.isBefore(currentMonth) || month.isAtSameMomentAs(currentMonth)) {
            months++;
            month = DateTime(month.year, month.month + 1, 1);
          }
          totalFixedExpenses += fixedExpense.amount * months;
        } else if (recurrence == 'yearly') {
          // Yıllık: Her yıl için ekle (Kasım 2024'ten itibaren)
          int years = 0;
          int startYear = effectiveStartDate.year;
          for (int year = startYear; year <= now.year; year++) {
            if (year > 2024 || (year == 2024 && effectiveStartDate.month >= 11)) {
              years++;
            }
          }
          totalFixedExpenses += fixedExpense.amount * years;
        } else {
          // One-time: Sadece bir kez ekle (eğer Kasım 2024'ten sonraysa)
          totalFixedExpenses += fixedExpense.amount;
        }
      }

      // Toplam harcamayı hesapla (sabit giderler dahil, vergiden düşülecekler hariç)
      _totalExpenses = expenses.fold(0.0, (sum, entry) => sum + entry.amount) + totalFixedExpenses;
      
      // Toplam girdiyi hesapla
      _totalIncome = _incomes.fold(0.0, (sum, entry) => sum + entry.amount);
      
      // Toplam vergiden düşülecek
      _totalTaxDeductible = _taxDeductibles.fold(0.0, (sum, entry) => sum + entry.amount);
      
      // Net kar hesapla (gelir - gider) - vergiden düşülecekler dahil değil
      _netProfit = _totalIncome - _totalExpenses;
      
      // Ortalama harcama (sadece harcamalar için)
      _averageExpense = expenses.isNotEmpty ? _totalExpenses / expenses.length : 0.0;
      
      // En yüksek ve en düşük harcama
      if (expenses.isNotEmpty) {
        _maxExpense = expenses.map((e) => e.amount).reduce((a, b) => a > b ? a : b);
        _minExpense = expenses.map((e) => e.amount).reduce((a, b) => a < b ? a : b);
      } else {
        _maxExpense = 0.0;
        _minExpense = 0.0;
      }
      
      // Kullanıcı bazında toplam hesapla (Kasım 2024'ten itibaren)
      _expensesByUser.clear();
      _incomeByUser.clear();
      _taxDeductibleByUser.clear();
      for (var entry in filteredEntries) {
        final ownerName = entry.ownerName;
        if (entry.entryType == 'income') {
          _incomeByUser[ownerName] = (_incomeByUser[ownerName] ?? 0.0) + entry.amount;
        } else if (entry.entryType == 'tax_deductible') {
          _taxDeductibleByUser[ownerName] = (_taxDeductibleByUser[ownerName] ?? 0.0) + entry.amount;
        } else {
          _expensesByUser[ownerName] = (_expensesByUser[ownerName] ?? 0.0) + entry.amount;
        }
      }
      
      // Sabit giderleri kullanıcı bazında ekle
      for (var fixedExpense in filteredFixedExpenses) {
        final ownerName = fixedExpense.ownerName;
        final startDate = fixedExpense.startDate ?? fixedExpense.createdAt ?? november2024;
        final effectiveStartDate = startDate.isBefore(november2024) ? november2024 : startDate;
        final effectiveStartMonth = DateTime(effectiveStartDate.year, effectiveStartDate.month, 1);
        final recurrence = fixedExpense.recurrence?.toLowerCase() ?? 'monthly';
        
        double fixedAmount = 0.0;
        if (recurrence == 'monthly') {
          int months = 0;
          DateTime month = effectiveStartMonth;
          while (month.isBefore(currentMonth) || month.isAtSameMomentAs(currentMonth)) {
            months++;
            month = DateTime(month.year, month.month + 1, 1);
          }
          fixedAmount = fixedExpense.amount * months;
        } else if (recurrence == 'yearly') {
          int years = 0;
          int startYear = effectiveStartDate.year;
          for (int year = startYear; year <= now.year; year++) {
            if (year > 2024 || (year == 2024 && effectiveStartDate.month >= 11)) {
              years++;
            }
          }
          fixedAmount = fixedExpense.amount * years;
        } else {
          fixedAmount = fixedExpense.amount;
        }
        
        _expensesByUser[ownerName] = (_expensesByUser[ownerName] ?? 0.0) + fixedAmount;
      }
      
      // Tüm girdileri birleştir (gösterim için)
      final allEntriesCombined = [...expenses, ..._incomes];
      allEntriesCombined.sort((a, b) {
        final aDate = a.createdAt ?? DateTime.now();
        final bDate = b.createdAt ?? DateTime.now();
        return aDate.compareTo(bDate);
      });

      // Seçili ay için filtreleme ve hesaplama
      if (_selectedMonth != null) {
        final monthStart = DateTime(_selectedMonth!.year, _selectedMonth!.month, 1);
        final monthEnd = DateTime(_selectedMonth!.year, _selectedMonth!.month + 1, 0, 23, 59, 59, 999);
        
        _monthlyExpenses = expenses.where((entry) {
          if (entry.createdAt == null) return false;
          return entry.createdAt!.isAfter(monthStart.subtract(const Duration(milliseconds: 1))) &&
                 entry.createdAt!.isBefore(monthEnd.add(const Duration(milliseconds: 1)));
        }).toList();
        
        _monthlyIncomes = _incomes.where((entry) {
          if (entry.createdAt == null) return false;
          return entry.createdAt!.isAfter(monthStart.subtract(const Duration(milliseconds: 1))) &&
                 entry.createdAt!.isBefore(monthEnd.add(const Duration(milliseconds: 1)));
        }).toList();
        
        _monthlyTaxDeductibles = _taxDeductibles.where((entry) {
          if (entry.createdAt == null) return false;
          return entry.createdAt!.isAfter(monthStart.subtract(const Duration(milliseconds: 1))) &&
                 entry.createdAt!.isBefore(monthEnd.add(const Duration(milliseconds: 1)));
        }).toList();
        
        // Seçili ay için sabit giderleri hesapla (sadece Kasım 2024'ten sonraki aylar için)
        double monthlyFixedExpenses = 0.0;
        double monthlyFixedIncomes = 0.0;
        if (_selectedMonth!.year > 2024 || (_selectedMonth!.year == 2024 && _selectedMonth!.month >= 11)) {
          for (var fixedExpense in filteredFixedExpenses) {
            final startDate = fixedExpense.startDate ?? fixedExpense.createdAt ?? november2024;
            final effectiveStartDate = startDate.isBefore(november2024) ? november2024 : startDate;
            final recurrence = fixedExpense.recurrence?.toLowerCase() ?? 'monthly';
            
            bool shouldInclude = false;
            if (recurrence == 'monthly') {
              // Aylık: Seçili ay, effectiveStartDate'ten sonra veya eşitse dahil et
              if (effectiveStartDate.year < _selectedMonth!.year || 
                  (effectiveStartDate.year == _selectedMonth!.year && effectiveStartDate.month <= _selectedMonth!.month)) {
                shouldInclude = true;
              }
            } else if (recurrence == 'yearly') {
              // Yıllık: Seçili ayın yılı, effectiveStartDate'in yılından sonra veya eşitse ve aynı aydaysa dahil et
              if (effectiveStartDate.year <= _selectedMonth!.year && effectiveStartDate.month == _selectedMonth!.month) {
                shouldInclude = true;
              }
            } else {
              // One-time: Sadece effectiveStartDate seçili aya eşitse dahil et
              if (effectiveStartDate.year == _selectedMonth!.year && effectiveStartDate.month == _selectedMonth!.month) {
                shouldInclude = true;
              }
            }
            
            if (shouldInclude) {
              if (fixedExpense.isIncome) {
                monthlyFixedIncomes += fixedExpense.amount;
              } else {
                monthlyFixedExpenses += fixedExpense.amount;
              }
            }
          }
        }
        
        _monthlyTotalExpenses = _monthlyExpenses.fold(0.0, (sum, entry) => sum + entry.amount) + monthlyFixedExpenses;
        _monthlyTotalIncome = _monthlyIncomes.fold(0.0, (sum, entry) => sum + entry.amount) + monthlyFixedIncomes;
        _monthlyTotalTaxDeductible = _monthlyTaxDeductibles.fold(0.0, (sum, entry) => sum + entry.amount);
        _monthlyNetProfit = _monthlyTotalIncome - _monthlyTotalExpenses;
        
        _monthlyExpensesByUser.clear();
        _monthlyIncomeByUser.clear();
        _monthlyTaxDeductibleByUser.clear();
        for (var entry in _monthlyExpenses) {
          final ownerName = entry.ownerName;
          _monthlyExpensesByUser[ownerName] = (_monthlyExpensesByUser[ownerName] ?? 0.0) + entry.amount;
        }
        for (var entry in _monthlyIncomes) {
          final ownerName = entry.ownerName;
          _monthlyIncomeByUser[ownerName] = (_monthlyIncomeByUser[ownerName] ?? 0.0) + entry.amount;
        }
        for (var entry in _monthlyTaxDeductibles) {
          final ownerName = entry.ownerName;
          _monthlyTaxDeductibleByUser[ownerName] = (_monthlyTaxDeductibleByUser[ownerName] ?? 0.0) + entry.amount;
        }
        
        // Seçili ay için sabit giderleri kullanıcı bazında ekle (sadece Kasım 2024'ten sonraki aylar için)
        if (_selectedMonth!.year > 2024 || (_selectedMonth!.year == 2024 && _selectedMonth!.month >= 11)) {
          for (var fixedExpense in filteredFixedExpenses) {
            final ownerName = fixedExpense.ownerName;
            final startDate = fixedExpense.startDate ?? fixedExpense.createdAt ?? november2024;
            final effectiveStartDate = startDate.isBefore(november2024) ? november2024 : startDate;
            final recurrence = fixedExpense.recurrence?.toLowerCase() ?? 'monthly';
            
            bool shouldInclude = false;
            if (recurrence == 'monthly') {
              if (effectiveStartDate.year < _selectedMonth!.year || 
                  (effectiveStartDate.year == _selectedMonth!.year && effectiveStartDate.month <= _selectedMonth!.month)) {
                shouldInclude = true;
              }
            } else if (recurrence == 'yearly') {
              if (effectiveStartDate.year <= _selectedMonth!.year && effectiveStartDate.month == _selectedMonth!.month) {
                shouldInclude = true;
              }
            } else {
              if (effectiveStartDate.year == _selectedMonth!.year && effectiveStartDate.month == _selectedMonth!.month) {
                shouldInclude = true;
              }
            }
            
            if (shouldInclude) {
              if (fixedExpense.isIncome) {
                _monthlyIncomeByUser[ownerName] = (_monthlyIncomeByUser[ownerName] ?? 0.0) + fixedExpense.amount;
              } else {
                _monthlyExpensesByUser[ownerName] = (_monthlyExpensesByUser[ownerName] ?? 0.0) + fixedExpense.amount;
              }
            }
          }
        }
      } else {
        // Tüm zamanlar seçiliyse
        _monthlyExpenses = [];
        _monthlyIncomes = [];
        _monthlyTaxDeductibles = [];
        _monthlyTotalExpenses = 0.0;
        _monthlyTotalIncome = 0.0;
        _monthlyTotalTaxDeductible = 0.0;
        _monthlyNetProfit = 0.0;
        _monthlyExpensesByUser.clear();
        _monthlyIncomeByUser.clear();
        _monthlyTaxDeductibleByUser.clear();
      }

      if (mounted) {
      setState(() {
          _allEntries = allEntriesCombined;
        _isLoading = false;
      });
      }
    } catch (e, stackTrace) {
      AppLogger.error('Hesaplamalar verisi yüklenirken hata', e, stackTrace);
      if (mounted) {
      setState(() {
        _errorMessage = 'Veriler yüklenirken bir hata oluştu: ${e.toString()}';
        _isLoading = false;
      });
      }
    }
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  /// Sabit giderleri aylık TEK KALEM olarak ExpenseEntry formatına dönüştür
  /// Her ay için "Sabit Giderler: X₺" şeklinde tek bir entry oluşturur
  List<ExpenseEntry> _convertFixedExpensesToEntries() {
    final List<ExpenseEntry> entries = [];
    final november2024 = DateTime(2024, 11, 1);
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);
    
    // Her ay için sabit gider toplamını hesapla
    final Map<String, double> monthlyTotals = {};
    
    for (var fixedExpense in _fixedExpenses) {
      if (!fixedExpense.isActive) continue;
      
      final startDate = fixedExpense.startDate ?? fixedExpense.createdAt ?? november2024;
      final effectiveStartDate = startDate.isBefore(november2024) ? november2024 : startDate;
      final effectiveStartMonth = DateTime(effectiveStartDate.year, effectiveStartDate.month, 1);
      final recurrence = fixedExpense.recurrence?.toLowerCase() ?? 'monthly';
      
      if (recurrence == 'monthly') {
        DateTime month = effectiveStartMonth;
        while (month.isBefore(currentMonth) || month.isAtSameMomentAs(currentMonth)) {
          final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
          monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0) + fixedExpense.amount;
          month = DateTime(month.year, month.month + 1, 1);
        }
      } else if (recurrence == 'yearly') {
        for (int year = effectiveStartDate.year; year <= now.year; year++) {
          if (year > 2024 || (year == 2024 && effectiveStartDate.month >= 11)) {
            final monthKey = '$year-${effectiveStartDate.month.toString().padLeft(2, '0')}';
            monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0) + fixedExpense.amount;
          }
        }
      } else {
        // Tek seferlik
        final monthKey = '${effectiveStartDate.year}-${effectiveStartDate.month.toString().padLeft(2, '0')}';
        monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0) + fixedExpense.amount;
      }
    }
    
    // Her ay için tek bir "Sabit Giderler" entry'si oluştur
    for (var entry in monthlyTotals.entries) {
      final parts = entry.key.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      
      entries.add(ExpenseEntry(
        id: 'fixed_${year}_$month',
        ownerId: 'system',
        ownerName: 'Sistem',
        description: 'Sabit Giderler (Toplam)',
        amount: entry.value,
        createdAt: DateTime(year, month, 1),
        entryType: 'expense',
        fileUrl: '',
        driveFileId: '',
        fileType: '',
        fixedExpenseId: 'fixed_total',
      ));
    }
    
    return entries;
  }

  /// Modern bottom sheet ay seçici
  Future<void> _selectMonth() async {
    final now = DateTime.now();
    int selectedYear = _selectedMonth?.year ?? now.year;
    int selectedMonthIndex = (_selectedMonth?.month ?? now.month) - 1;
    final theme = Theme.of(context);
    
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

    setState(() {
      _selectedMonth = result; // null olabilir (Tüm Zamanlar)
    });
    _loadData();
  }

  Widget _buildStatRow(ThemeData theme, String label, String value, IconData icon, [Color? iconColor]) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: iconColor ?? theme.colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// Özet metrik kartı (Gelir, Gider, Net Kar/Zarar, Vergiden Düşülecek)
  Widget _buildSummaryCard(
    ThemeData theme,
    String title,
    double income,
    double expenses,
    double netProfit,
    int incomeCount,
    int expenseCount, {
    double taxDeductible = 0.0,
    int taxDeductibleCount = 0,
    bool isMobile = false,
    VoidCallback? onIncomeTap,
    VoidCallback? onExpenseTap,
    VoidCallback? onTaxDeductibleTap,
  }) {
    final isAllTime = title == 'Tüm Zamanlar';
    return Card(
      elevation: isMobile ? 2 : 4,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
          width: isMobile ? 1 : 1.5,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
          color: theme.colorScheme.surface,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: isMobile ? 0.3 : 0.4),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: isMobile ? 0.05 : 0.08),
              blurRadius: isMobile ? 6 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 14,
                      vertical: isMobile ? 8 : 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primaryContainer,
                          theme.colorScheme.primaryContainer.withValues(alpha: 0.85),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
                          blurRadius: isMobile ? 4 : 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isAllTime ? Icons.calendar_today_rounded : Icons.calendar_month_rounded,
                          size: isMobile ? 16 : 18,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        SizedBox(width: isMobile ? 8 : 8),
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: isMobile ? 14 : 16,
                              color: theme.colorScheme.onPrimaryContainer,
                              letterSpacing: 0.1,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: isMobile ? 16 : 24),
              // Mobilde yatay scrollable, desktop'ta row
              LayoutBuilder(
                builder: (context, constraints) {
                // Mobilde 2x2 grid layout
                if (isMobile) {
                  return Column(
                    children: [
                      // Üst satır: Gelir ve Gider
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              theme,
                              'Gelir',
                              income,
                              Colors.green,
                              Icons.trending_up,
                              incomeCount,
                              isMobile: isMobile,
                              isLarge: true,
                              onTap: onIncomeTap,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricCard(
                              theme,
                              'Gider',
                              expenses,
                              theme.colorScheme.error,
                              Icons.account_balance_wallet,
                              expenseCount,
                              isMobile: isMobile,
                              isLarge: true,
                              onTap: onExpenseTap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Alt satır: Vergiden Düşülecek ve Net
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              theme,
                              'Vergi',
                              taxDeductible,
                              Colors.orange,
                              Icons.receipt_long,
                              taxDeductibleCount,
                              isMobile: isMobile,
                              onTap: onTaxDeductibleTap,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricCard(
                              theme,
                              'Net',
                              netProfit,
                              netProfit >= 0 ? Colors.green : theme.colorScheme.error,
                              netProfit >= 0 ? Icons.trending_up : Icons.trending_down,
                              null,
                              isHighlighted: true,
                              isMobile: isMobile,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }
                // Küçük ekranlarda tek sütun, büyük ekranlarda 3 sütun
                if (constraints.maxWidth < 600) {
                  return Column(
                    children: [
                      _buildMetricCard(
                        theme,
                        'Gelir',
                        income,
                        Colors.green,
                        Icons.trending_up,
                        incomeCount,
                        isMobile: isMobile,
                        isLarge: true,
                        onTap: onIncomeTap,
                      ),
                      const SizedBox(height: 12),
                      _buildMetricCard(
                        theme,
                        'Gider',
                        expenses,
                        theme.colorScheme.error,
                        Icons.account_balance_wallet,
                        expenseCount,
                        isMobile: isMobile,
                        isLarge: true,
                        onTap: onExpenseTap,
                      ),
                      const SizedBox(height: 12),
                      if (taxDeductible > 0) ...[
                        _buildMetricCard(
                          theme,
                          'Vergiden Düşülecek',
                          taxDeductible,
                          Colors.orange,
                          Icons.assignment_turned_in,
                          taxDeductibleCount,
                          isMobile: isMobile,
                          onTap: onTaxDeductibleTap,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _buildMetricCard(
                        theme,
                        'Net',
                        netProfit,
                        netProfit >= 0 ? Colors.green : theme.colorScheme.error,
                        netProfit >= 0 ? Icons.trending_up : Icons.trending_down,
                        null,
                        isHighlighted: true,
                        isMobile: isMobile,
                      ),
                    ],
                  );
                }
                // Desktop: 4 kartı yan yana tek satırda göster
                return Row(
                  children: [
                    // Gelir
                    Expanded(
                      child: _buildMetricCard(
                        theme,
                        'Gelir',
                        income,
                        Colors.green,
                        Icons.trending_up,
                        incomeCount,
                        isMobile: isMobile,
                        isLarge: true,
                        onTap: onIncomeTap,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Gider
                    Expanded(
                      child: _buildMetricCard(
                        theme,
                        'Gider',
                        expenses,
                        theme.colorScheme.error,
                        Icons.account_balance_wallet,
                        expenseCount,
                        isMobile: isMobile,
                        isLarge: true,
                        onTap: onExpenseTap,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Vergiden Düşülecek
                    Expanded(
                      child: _buildMetricCard(
                        theme,
                        'Vergi',
                        taxDeductible,
                        Colors.orange,
                        Icons.receipt_long,
                        taxDeductibleCount,
                        isMobile: isMobile,
                        onTap: onTaxDeductibleTap,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Net Kar/Zarar
                    Expanded(
                      child: _buildMetricCard(
                        theme,
                        'Net',
                        netProfit,
                        netProfit >= 0 ? Colors.green : theme.colorScheme.error,
                        netProfit >= 0 ? Icons.trending_up : Icons.trending_down,
                        null,
                        isHighlighted: true,
                        isMobile: isMobile,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Aylık özet gösteren bottom sheet (tıklayınca detay açılır)
  void _showMonthlySummaryBottomSheet(
    BuildContext context,
    ThemeData theme,
    String title,
    List<ExpenseEntry> entries,
    Color color,
    bool isIncome,
  ) {
    // Aylara göre grupla
    final Map<String, List<ExpenseEntry>> entriesByMonth = {};
    final Map<String, double> totalsByMonth = {};
    
    for (var entry in entries) {
      if (entry.createdAt == null) continue;
      final monthKey = DateFormat('yyyy-MM').format(entry.createdAt!);
      entriesByMonth.putIfAbsent(monthKey, () => []);
      entriesByMonth[monthKey]!.add(entry);
      totalsByMonth[monthKey] = (totalsByMonth[monthKey] ?? 0) + entry.amount;
    }
    
    // Aylara göre sırala (en yeni en üstte)
    final sortedMonths = entriesByMonth.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
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
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isIncome ? Icons.trending_up : Icons.account_balance_wallet,
                              color: color,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${sortedMonths.length} ay, ${entries.length} kayıt',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              // Toplam
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Toplam',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _formatCurrency(entries.fold(0.0, (sum, e) => sum + e.amount)),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Aylar listesi
              Expanded(
                child: sortedMonths.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 64,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Kayıt bulunamadı',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: sortedMonths.length,
                        itemBuilder: (context, index) {
                          final monthKey = sortedMonths[index];
                          final monthEntries = entriesByMonth[monthKey]!;
                          final monthTotal = totalsByMonth[monthKey]!;
                          final monthDate = DateTime.parse('$monthKey-01');
                          final monthName = DateFormat('MMMM yyyy', 'tr_TR').format(monthDate);
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Material(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  // Bu ayın detaylarını göster
                                  Navigator.of(ctx).pop(); // Özet sheet'i kapat
                                  _showEntriesBottomSheet(
                                    context,
                                    theme,
                                    '$monthName - ${isIncome ? "Gelirler" : "Giderler"}',
                                    monthEntries,
                                    color,
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      // Ay ikonu
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              DateFormat('MMM', 'tr_TR').format(monthDate).toUpperCase(),
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: color,
                                                fontSize: 10,
                                              ),
                                            ),
                                            Text(
                                              DateFormat('yy').format(monthDate),
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: color.withValues(alpha: 0.8),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      // Ay bilgisi
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              monthName,
                                              style: theme.textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${monthEntries.length} kayıt',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Tutar
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            _formatCurrency(monthTotal),
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: color,
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ],
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
  }

  /// Girdileri gösteren bottom sheet
  void _showEntriesBottomSheet(
    BuildContext context,
    ThemeData theme,
    String title,
    List<ExpenseEntry> entries,
    Color color,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
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
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              title.contains('Gelir') ? Icons.trending_up : Icons.account_balance_wallet,
                              color: color,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${entries.length} kayıt',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Girdiler listesi
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 64,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Kayıt bulunamadı',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: EntryCard(
                              entry: entry,
                              showOwnerIcon: true,
                              showMonthInfo: true,
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
  }

  /// Tek bir metrik kartı
  Widget _buildMetricCard(
    ThemeData theme,
    String label,
    double amount,
    Color color,
    IconData icon,
    int? count, {
    bool isHighlighted = false,
    bool isMobile = false,
    bool isLarge = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: EdgeInsets.all(isMobile ? (isLarge ? 16 : 14) : (isLarge ? 20 : 16)),
      decoration: BoxDecoration(
        color: isHighlighted
            ? color.withValues(alpha: 0.1)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
        border: isHighlighted
            ? Border.all(color: color.withValues(alpha: 0.3), width: isMobile ? 1.5 : 2)
            : Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.1),
                width: 1,
              ),
        boxShadow: isHighlighted
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: isMobile ? 6 : 10,
                  offset: Offset(0, isMobile ? 3 : 3),
                  spreadRadius: 0,
                ),
              ]
            : [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.05),
                  blurRadius: isMobile ? 4 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _formatCurrency(amount),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                      fontSize: isHighlighted ? (isLarge ? 17 : 15) : (isLarge ? 16 : 14),
                      letterSpacing: -0.3,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 18, color: color),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _formatCurrency(amount),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontSize: isHighlighted ? (isLarge ? 24 : 20) : (isLarge ? 22 : 18),
                    letterSpacing: -0.3,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (count != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$count adet',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = MediaQuery.of(context).size.width < 600;
            if (isMobile) {
              // Mobilde sadece başlık
              return const Text('Hesaplamalar');
            }
            // Desktop'ta başlık + ay seçici
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Hesaplamalar'),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // Önceki ay butonu
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: _selectedMonth != null
                          ? () {
                              final prevMonth = DateTime(_selectedMonth!.year, _selectedMonth!.month - 1, 1);
                              final november2024 = DateTime(2024, 11, 1);
                              // Kasım 2024'ten önceye geçilemez
                              if (prevMonth.isAfter(november2024.subtract(const Duration(days: 1))) ||
                                  prevMonth.isAtSameMomentAs(november2024)) {
                                setState(() {
                                  _selectedMonth = prevMonth;
                                });
                                _loadData();
                              }
                            }
                          : null,
                      tooltip: 'Önceki ay',
                    ),
                    const SizedBox(width: 8),
                    // Tarih chip/button
                    Flexible(
                      child: Material(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(24),
                        elevation: 1,
                        shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.1),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: _selectMonth,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_month_rounded,
                                  size: 20,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    _selectedMonth == null
                                        ? 'Tüm Zamanlar'
                                        : DateFormat('MMMM yyyy', 'tr_TR').format(_selectedMonth!),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      letterSpacing: 0.2,
                                    ),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
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
                    ),
                    const SizedBox(width: 8),
                    // Sonraki ay butonu
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: () {
                        final now = DateTime.now();
                        if (_selectedMonth == null) {
                          // Tüm zamanlar seçiliyse mevcut aya geç
                          setState(() {
                            _selectedMonth = DateTime(now.year, now.month, 1);
                          });
                          _loadData();
                        } else {
                          final nextMonth = DateTime(_selectedMonth!.year, _selectedMonth!.month + 1, 1);
                          // Gelecek aya geçilemez
                          if (nextMonth.isBefore(DateTime(now.year, now.month + 1, 1)) ||
                              nextMonth.isAtSameMomentAs(DateTime(now.year, now.month, 1))) {
                            setState(() {
                              _selectedMonth = nextMonth;
                            });
                            _loadData();
                          }
                        }
                      },
                      tooltip: 'Sonraki ay',
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          // Mobilde ay seçiciyi actions'a taşı
          Builder(
            builder: (context) {
              final isMobile = MediaQuery.of(context).size.width < 600;
              if (!isMobile) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Material(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  elevation: 1,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _selectMonth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            size: 18,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _selectedMonth == null
                                  ? 'Tüm Zamanlar'
                                  : DateFormat('MMM yyyy', 'tr_TR').format(_selectedMonth!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_drop_down_rounded,
                            size: 18,
                            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                color: theme.colorScheme.primary,
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Hesaplamalar yükleniyor...',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lütfen bekleyin',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
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
                          'Bir Hata Oluştu',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        textAlign: TextAlign.center,
                      ),
                        const SizedBox(height: 32),
                        FilledButton.icon(
                        onPressed: _loadData,
                          icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Yeniden Dene'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                      ),
                    ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      // Özet kartları (Yan yana veya alt alta)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: MediaQuery.of(context).size.width < 600 ? 8.0 : 16.0,
                            vertical: MediaQuery.of(context).size.width < 600 ? 8.0 : 20.0,
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isWideScreen = constraints.maxWidth > 800;
                              final isMobile = MediaQuery.of(context).size.width < 600;
                              
                              // Tüm zamanlar için giderler (sabit giderler DAHİL)
                              final normalExpenses = _allEntries.where((e) => e.entryType != 'income').toList();
                              final fixedExpenseEntries = _convertFixedExpensesToEntries();
                              final allTimeExpenses = [...normalExpenses, ...fixedExpenseEntries]
                                ..sort((a, b) {
                                  final aDate = a.createdAt ?? DateTime.now();
                                  final bDate = b.createdAt ?? DateTime.now();
                                  return bDate.compareTo(aDate); // En yeni en üstte
                                });
                              
                              // Tüm zamanlar kartı
                              final allTimeCard = _buildSummaryCard(
                                theme,
                                'Tüm Zamanlar',
                                _totalIncome,
                                _totalExpenses,
                                _netProfit,
                                _incomes.length,
                                allTimeExpenses.length,
                                taxDeductible: _totalTaxDeductible,
                                taxDeductibleCount: _taxDeductibles.length,
                                isMobile: isMobile,
                                onIncomeTap: () {
                                  _showMonthlySummaryBottomSheet(
                                    context,
                                    theme,
                                    'Tüm Zamanlar - Gelirler',
                                    _incomes,
                                    Colors.green,
                                    true, // isIncome
                                  );
                                },
                                onExpenseTap: () {
                                  _showMonthlySummaryBottomSheet(
                                    context,
                                    theme,
                                    'Tüm Zamanlar - Giderler',
                                    allTimeExpenses,
                                    theme.colorScheme.error,
                                    false, // isIncome
                                  );
                                },
                                onTaxDeductibleTap: () {
                                  _showMonthlySummaryBottomSheet(
                                    context,
                                    theme,
                                    'Tüm Zamanlar - Vergiden Düşülecek',
                                    _taxDeductibles,
                                    Colors.orange,
                                    false, // isIncome
                                  );
                                },
                              );
                              
                              // Seçili ay kartı
                              Widget? monthlyCard;
                              if (_selectedMonth != null) {
                                final monthName = DateFormat('MMMM yyyy', 'tr_TR').format(_selectedMonth!);
                                
                                // Seçili ay için sabit giderleri filtrele
                                final monthlyFixedExpenses = fixedExpenseEntries.where((e) {
                                  if (e.createdAt == null) return false;
                                  return e.createdAt!.year == _selectedMonth!.year &&
                                         e.createdAt!.month == _selectedMonth!.month;
                                }).toList();
                                
                                final allMonthlyExpenses = [..._monthlyExpenses, ...monthlyFixedExpenses]
                                  ..sort((a, b) {
                                    final aDate = a.createdAt ?? DateTime.now();
                                    final bDate = b.createdAt ?? DateTime.now();
                                    return bDate.compareTo(aDate);
                                  });
                                
                                monthlyCard = _buildSummaryCard(
                                  theme,
                                  monthName,
                                  _monthlyTotalIncome,
                                  _monthlyTotalExpenses,
                                  _monthlyNetProfit,
                                  _monthlyIncomes.length,
                                  allMonthlyExpenses.length,
                                  taxDeductible: _monthlyTotalTaxDeductible,
                                  taxDeductibleCount: _monthlyTaxDeductibles.length,
                                  isMobile: isMobile,
                                  onIncomeTap: () {
                                    _showEntriesBottomSheet(
                                      context,
                                      theme,
                                      '$monthName - Gelirler',
                                      _monthlyIncomes,
                                      Colors.green,
                                    );
                                  },
                                  onExpenseTap: () {
                                    _showEntriesBottomSheet(
                                      context,
                                      theme,
                                      '$monthName - Giderler',
                                      allMonthlyExpenses,
                                      theme.colorScheme.error,
                                    );
                                  },
                                  onTaxDeductibleTap: () {
                                    _showEntriesBottomSheet(
                                      context,
                                      theme,
                                      '$monthName - Vergiden Düşülecek',
                                      _monthlyTaxDeductibles,
                                      Colors.orange,
                                    );
                                  },
                                );
                              }
                              
                              // Büyük ekranlarda yan yana, küçük ekranlarda alt alta
                              if (isWideScreen && monthlyCard != null) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: allTimeCard,
                                    ),
                                    SizedBox(width: isMobile ? 12 : 20),
                                    Expanded(
                                      child: monthlyCard,
                                    ),
                                  ],
                                );
                              } else {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    allTimeCard,
                                    if (monthlyCard != null) ...[
                                      SizedBox(height: isMobile ? 12 : 20),
                                      monthlyCard,
                                    ],
                                  ],
                                );
                              }
                            },
                          ),
                        ),
                      ),
                      // Detaylar bölümü
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: MediaQuery.of(context).size.width < 600 ? 12.0 : 16.0,
                            vertical: 8.0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Ortak Bazında Dağılımlar (Seçili duruma göre)
                              // Tüm Zamanlar seçiliyse toplam, ay seçiliyse aylık göster
                              if ((_selectedMonth == null && (_incomeByUser.isNotEmpty || _expensesByUser.isNotEmpty)) ||
                                  (_selectedMonth != null && (_monthlyIncomeByUser.isNotEmpty || _monthlyExpensesByUser.isNotEmpty))) ...[
                                SizedBox(height: MediaQuery.of(context).size.width < 600 ? 12 : 20),
                              Card(
                                elevation: 3,
                                shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  side: BorderSide(
                                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                                    width: 1,
                                  ),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        theme.colorScheme.surface,
                                        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                      ],
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                        // Gelir Dağılımı (Tüm Zamanlar veya Aylık)
                                        if ((_selectedMonth == null && _incomeByUser.isNotEmpty) ||
                                            (_selectedMonth != null && _monthlyIncomeByUser.isNotEmpty)) ...[
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                                            child: Row(
                                        children: [
                                                Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Icon(
                                                    Icons.account_balance_wallet,
                                                    color: Colors.green,
                                                    size: 18,
                                                  ),
                                          ),
                                                const SizedBox(width: 10),
                                          Text(
                                                  'Gelir Dağılımı',
                                            style: theme.textTheme.titleSmall?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13,
                                                    letterSpacing: 0.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                          ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          child: Column(
                                            children: (_selectedMonth == null ? _incomeByUser : _monthlyIncomeByUser).entries.map((entry) {
                                              final totalIncome = _selectedMonth == null ? _totalIncome : _monthlyTotalIncome;
                                              final percentage = totalIncome > 0
                                                  ? (entry.value / totalIncome * 100)
                                                  : 0.0;
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 12.0),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      flex: 2,
                                                      child: Text(
                                                        entry.key,
                                                        style: theme.textTheme.bodyMedium?.copyWith(
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 13,
                                                          letterSpacing: 0.1,
                                      ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 3,
                                                      child: Container(
                                                        height: 8,
                                                        decoration: BoxDecoration(
                                                          borderRadius: BorderRadius.circular(4),
                                                          color: theme.colorScheme.surfaceContainerHighest,
                                                        ),
                                                        child: FractionallySizedBox(
                                                          alignment: Alignment.centerLeft,
                                                          widthFactor: percentage / 100,
                                                          child: Container(
                                                            decoration: BoxDecoration(
                                                              borderRadius: BorderRadius.circular(4),
                                                              gradient: LinearGradient(
                                                                colors: [
                                                                  Colors.green,
                                                                  Colors.green.shade400,
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    SizedBox(
                                                      width: 50,
                                                      child: Text(
                                                        '${percentage.toStringAsFixed(0)}%',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                        textAlign: TextAlign.right,
                                ),
                              ),
                                                    const SizedBox(width: 12),
                                                    SizedBox(
                                                      width: 80,
                                                      child: Text(
                                                        _formatCurrency(entry.value),
                                                        style: theme.textTheme.bodyMedium?.copyWith(
                                                          fontWeight: FontWeight.w700,
                                                          color: Colors.green,
                                                          fontSize: 13,
                                                        ),
                                                        textAlign: TextAlign.right,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                          if ((_selectedMonth == null && _expensesByUser.isNotEmpty) ||
                                              (_selectedMonth != null && _monthlyExpensesByUser.isNotEmpty))
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              child: Divider(
                                                height: 1,
                                                thickness: 1,
                                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                                  ),
                                ),
                                        ],
                                        // Gider Dağılımı (Tüm Zamanlar veya Aylık)
                                        if ((_selectedMonth == null && _expensesByUser.isNotEmpty) ||
                                            (_selectedMonth != null && _monthlyExpensesByUser.isNotEmpty)) ...[
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                                            child: Row(
                                    children: [
                                                Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: theme.colorScheme.error.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Icon(
                                                    Icons.people_outline,
                                                    color: theme.colorScheme.error,
                                                    size: 18,
                                                  ),
                                          ),
                                                const SizedBox(width: 10),
                                          Text(
                                                  'Gider Dağılımı',
                                            style: theme.textTheme.titleSmall?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13,
                                                    letterSpacing: 0.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                          ),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                          child: Column(
                                            children: (_selectedMonth == null ? _expensesByUser : _monthlyExpensesByUser).entries.map((entry) {
                                              final totalExpenses = _selectedMonth == null ? _totalExpenses : _monthlyTotalExpenses;
                                              final percentage = totalExpenses > 0
                                                  ? (entry.value / totalExpenses * 100)
                                                  : 0.0;
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 12.0),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      flex: 2,
                                                      child: Text(
                                                        entry.key,
                                                        style: theme.textTheme.bodyMedium?.copyWith(
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 13,
                                                          letterSpacing: 0.1,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 3,
                                                      child: Container(
                                                        height: 8,
                                                        decoration: BoxDecoration(
                                                          borderRadius: BorderRadius.circular(4),
                                                          color: theme.colorScheme.surfaceContainerHighest,
                                                        ),
                                                        child: FractionallySizedBox(
                                                          alignment: Alignment.centerLeft,
                                                          widthFactor: percentage / 100,
                                                          child: Container(
                                                            decoration: BoxDecoration(
                                                              borderRadius: BorderRadius.circular(4),
                                                              gradient: LinearGradient(
                                                                colors: [
                                                                  theme.colorScheme.error,
                                                                  theme.colorScheme.error.withValues(alpha: 0.7),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                        ),
                                      ),
                                                    const SizedBox(width: 12),
                                                    SizedBox(
                                                      width: 50,
                                                      child: Text(
                                                        '${percentage.toStringAsFixed(0)}%',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                        textAlign: TextAlign.right,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    SizedBox(
                                                      width: 80,
                                                      child: Text(
                                                        _formatCurrency(entry.value),
                                                        style: theme.textTheme.bodyMedium?.copyWith(
                                                          fontWeight: FontWeight.w700,
                                                          color: theme.colorScheme.error,
                                                          fontSize: 13,
                                                        ),
                                                        textAlign: TextAlign.right,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              ],
                              // İstatistikler (kompakt)
                              if (_allEntries.isNotEmpty) ...[
                                const SizedBox(height: 20),
                              Card(
                                  elevation: 2,
                                  shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.08),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                                      width: 1,
                                  ),
                                ),
                                child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.analytics_outlined,
                                            color: theme.colorScheme.primary,
                                              size: 16,
                                          ),
                                            const SizedBox(width: 6),
                                          Text(
                                            'İstatistikler',
                                            style: theme.textTheme.titleSmall?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                        const SizedBox(height: 6),
                                        _buildStatRow(
                                          theme,
                                          'Ortalama',
                                          _formatCurrency(_averageExpense),
                                          Icons.trending_flat,
                                        ),
                                        const SizedBox(height: 6),
                                        _buildStatRow(
                                          theme,
                                          'En Yüksek',
                                          _formatCurrency(_maxExpense),
                                          Icons.arrow_upward,
                                          Colors.green,
                                        ),
                                        const SizedBox(height: 6),
                                        _buildStatRow(
                                          theme,
                                          'En Düşük',
                                          _formatCurrency(_minExpense),
                                          Icons.arrow_downward,
                                          Colors.orange,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // Alt boşluk
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 24),
                      ),
                    ],
                  ),
                ),
    );
  }
}





