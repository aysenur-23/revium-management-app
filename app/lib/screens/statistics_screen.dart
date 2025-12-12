import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../models/expense_entry.dart';
import '../models/user_profile.dart';

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
  DateTime? _selectedDate; // null = Tümü, değer = Seçili tarih (yıl-ay-gün)
  bool _hasSelectedDay = false; // Gün seçildi mi? (false ise sadece ay seçilmiş)
  bool _hasReceivedData = false; // İlk veri geldi mi kontrolü

  List<ExpenseEntry> _getFilteredEntries(List<ExpenseEntry> allEntries) {
    // Eğer tarih seçilmemişse (null), tüm kayıtları döndür
    if (_selectedDate == null) {
      return allEntries;
    }
    
    if (_hasSelectedDay) {
      // Gün seçilmişse: Sadece o günü filtrele
      final startDate = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      final endDate = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, 23, 59, 59, 999);

      return allEntries.where((entry) {
        if (entry.createdAt == null) return false;
        return entry.createdAt!.isAfter(startDate.subtract(const Duration(milliseconds: 1))) &&
               entry.createdAt!.isBefore(endDate.add(const Duration(milliseconds: 1)));
      }).toList();
    } else {
      // Sadece ay seçilmişse: O ayın tamamını filtrele
      final startDate = DateTime(_selectedDate!.year, _selectedDate!.month, 1);
      final endDate = DateTime(_selectedDate!.year, _selectedDate!.month + 1, 0, 23, 59, 59, 999);

      return allEntries.where((entry) {
        if (entry.createdAt == null) return false;
        return entry.createdAt!.isAfter(startDate.subtract(const Duration(milliseconds: 1))) &&
               entry.createdAt!.isBefore(endDate.add(const Duration(milliseconds: 1)));
      }).toList();
    }
  }

  Future<void> _selectDate() async {
    if (!mounted) return;
    
    // Modal bottom sheet ile stabil açılış
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
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
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
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
                    'Filtreleme Seçenekleri',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Options
            ListTile(
              leading: const Icon(Icons.all_inclusive_rounded),
              title: const Text('Tümü'),
              onTap: () => Navigator.of(context).pop('all'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_rounded),
              title: const Text('Tarih Seç'),
              onTap: () => Navigator.of(context).pop('date'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (!mounted) return;

    if (result == 'all') {
      setState(() {
        _selectedDate = null;
        _hasSelectedDay = false;
      });
    } else if (result == 'date') {
      // Tek bir DatePicker ile yıl -> ay -> gün seçimi (aynı dialog'da)
      final DateTime? pickedDate = await showDatePicker(
        context: context,
        initialDate: _selectedDate ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        locale: const Locale('tr', 'TR'),
        helpText: 'Tarih Seçin',
        cancelText: 'İptal',
        confirmText: 'Seç',
        initialDatePickerMode: DatePickerMode.year, // Önce yıl seçimi ile başla
      );

      if (!mounted) return;

      setState(() {
        if (pickedDate != null) {
          // Tarih seçildi
          _selectedDate = pickedDate;
          _hasSelectedDay = true;
        }
      });
    }
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
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        toolbarHeight: 110,
        automaticallyImplyLeading: true,
        centerTitle: false,
        title: Image.asset(
          'assets/logo_header.png',
          height: 85,
          width: 85,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.bar_chart_rounded,
              size: 64,
              color: theme.colorScheme.primary,
            );
          },
        ),
        titleSpacing: 16,
        elevation: 1,
        backgroundColor: theme.colorScheme.surface,
        actions: const [], // Filtreleme sadece _PremiumFilterCard'da
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: EdgeInsets.zero,
          child: StreamBuilder<List<ExpenseEntry>>(
        stream: FirestoreService.streamMyEntries(widget.currentUser.userId),
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

          // Loading durumu
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(
                color: theme.colorScheme.primary,
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
          final total = filteredEntries.fold(0.0, (sum, entry) => sum + entry.amount);
          final averageAmount = filteredEntries.isEmpty ? 0.0 : total / filteredEntries.length;
          final entryCount = filteredEntries.length;

          // Filtreleme metinleri
          final String filterText;
          final String filterSubtext;
          if (_selectedDate == null) {
            filterText = 'Tüm Kayıtlar';
            filterSubtext = 'Filtreleme';
          } else if (_hasSelectedDay) {
            // Gün seçilmişse
            filterText = DateFormat('dd MMMM yyyy', kIsWeb ? null : 'tr_TR').format(_selectedDate!);
            filterSubtext = 'Seçili Tarih';
          } else {
            // Sadece ay seçilmişse
            filterText = DateFormat('MMMM yyyy', kIsWeb ? null : 'tr_TR').format(_selectedDate!);
            filterSubtext = 'Seçili Ay';
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(left: 20, right: 20, top: 0, bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                  title: 'Toplam Harcama',
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
                    // Home screen'e dön - tüm kayıtları göster
                    Navigator.of(context).pop();
                    // "Tüm Eklenenler" sekmesine geçmek için home screen'e sinyal gönder
                    // Home screen zaten açık olduğu için sadece pop yeterli
                  },
                ),
                const SizedBox(height: 16),
                
                // İkincil istatistikler
                Row(
                  children: [
                    Expanded(
                      child: _CompactStatCard(
                        title: 'Ortalama',
                        value: NumberFormat.currency(
                          symbol: '₺',
                          decimalDigits: 2,
                          locale: 'tr_TR',
                        ).format(averageAmount),
                        icon: Icons.trending_up_rounded,
                        color: theme.colorScheme.secondary,
                        theme: theme,
                        onTap: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CompactStatCard(
                        title: 'Kayıt',
                        value: '$entryCount',
                        icon: Icons.receipt_long_rounded,
                        color: theme.colorScheme.tertiary,
                        theme: theme,
                        onTap: () {
                          Navigator.of(context).pop(_selectedDate);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _CompactStatCard(
                        title: 'Günlük Ort.',
                        value: _calculateDailyAverage(total, entryCount),
                        icon: Icons.calendar_view_day_rounded,
                        color: Colors.orange,
                        theme: theme,
                        onTap: () {
                          // Home screen'e dön - seçili tarih filtresi varsa göster
                          Navigator.of(context).pop(_selectedDate);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _CompactStatCard(
                        title: 'En Yüksek',
                        value: filteredEntries.isEmpty
                            ? '₺0'
                            : NumberFormat.currency(
                                symbol: '₺',
                                decimalDigits: 2,
                                locale: 'tr_TR',
                              ).format(
                                filteredEntries.map((e) => e.amount).reduce((a, b) => a > b ? a : b),
                              ),
                        icon: Icons.arrow_upward_rounded,
                        color: Colors.red,
                        theme: theme,
                        onTap: () {
                          // Home screen'e dön - seçili tarih filtresi varsa göster
                          Navigator.of(context).pop(_selectedDate);
                        },
                      ),
                    ),
                  ],
                ),
                
                // Günlük dağılım - sadece ay seçilmişse göster (gün seçildiyse günlük dağılım göstermeye gerek yok)
                if (_selectedDate != null && !_hasSelectedDay && filteredEntries.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _SectionHeader(
                    title: 'Seçili Ay Harcamaları',
                    theme: theme,
                  ),
                  const SizedBox(height: 16),
                  _DailyBreakdownCard(
                    entries: filteredEntries,
                    theme: theme,
                  ),
                ] else if (filteredEntries.isEmpty) ...[
                  const SizedBox(height: 32),
                  _EmptyStateCard(
                    message: _selectedDate == null 
                        ? 'Henüz kayıt bulunmuyor'
                        : (_hasSelectedDay 
                            ? 'Bu tarih için kayıt bulunamadı'
                            : 'Bu ay için kayıt bulunamadı'),
                    theme: theme,
                  ),
                ],
                const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
        ),
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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

// Daily Breakdown Card
class _DailyBreakdownCard extends StatelessWidget {
  final List<ExpenseEntry> entries;
  final ThemeData theme;

  const _DailyBreakdownCard({
    required this.entries,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final Map<int, double> dailyTotals = {};

    for (var entry in entries) {
      if (entry.createdAt != null) {
        final day = entry.createdAt!.day;
        dailyTotals[day] = (dailyTotals[day] ?? 0) + entry.amount;
      }
    }

    final sortedDays = dailyTotals.keys.toList()..sort();
    final maxAmount = dailyTotals.values.isEmpty
        ? 1.0
        : dailyTotals.values.reduce((a, b) => a > b ? a : b);

    if (sortedDays.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.08),
          ),
        ),
        child: Center(
          child: Text(
            'Bu ay için günlük veri bulunamadı',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

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
          children: sortedDays.map((day) {
            final amount = dailyTotals[day]!;
            final percentage = maxAmount > 0 ? (amount / maxAmount) * 100 : 0.0;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$day',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: percentage / 100,
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.colorScheme.primary,
                                  theme.colorScheme.primary.withValues(alpha: 0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 100,
                    child: Text(
                      NumberFormat.currency(
                        symbol: '₺',
                        decimalDigits: 2,
                        locale: 'tr_TR',
                      ).format(amount),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
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
