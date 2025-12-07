/**
 * İstatistikler ekranı
 * Aylık/haftalık özetler ve grafikler
 */

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
  DateTime? _selectedMonth; // null = Tümü, değer = Seçili ay
  bool _hasReceivedData = false; // İlk veri geldi mi kontrolü

  List<ExpenseEntry> _getFilteredEntries(List<ExpenseEntry> allEntries) {
    // Eğer ay seçilmemişse (null), tüm kayıtları döndür
    if (_selectedMonth == null) {
      return allEntries;
    }
    
    // Ayın ilk günü (00:00:00)
    final startDate = DateTime(_selectedMonth!.year, _selectedMonth!.month, 1);
    // Ayın son günü (23:59:59.999)
    final endDate = DateTime(_selectedMonth!.year, _selectedMonth!.month + 1, 0, 23, 59, 59, 999);

    return allEntries.where((entry) {
      if (entry.createdAt == null) return false;
      return entry.createdAt!.isAfter(startDate.subtract(const Duration(milliseconds: 1))) &&
             entry.createdAt!.isBefore(endDate.add(const Duration(milliseconds: 1)));
    }).toList();
  }

  Future<void> _selectMonth() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filtreleme Seçeneği'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.all_inclusive_rounded),
              title: const Text('Tümü'),
              subtitle: const Text('Tüm maliyetleri göster'),
              onTap: () => Navigator.of(context).pop('all'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.calendar_month_rounded),
              title: const Text('Ay Seç'),
              subtitle: const Text('Belirli bir ay seç'),
              onTap: () => Navigator.of(context).pop('month'),
            ),
          ],
        ),
      ),
    );

    if (result == 'all') {
      setState(() {
        _selectedMonth = null;
      });
    } else if (result == 'month') {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _selectedMonth ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        locale: const Locale('tr', 'TR'),
        helpText: 'Ay Seçin',
        cancelText: 'İptal',
        confirmText: 'Seç',
        initialDatePickerMode: DatePickerMode.year,
      );

      if (picked != null) {
        setState(() {
          _selectedMonth = picked;
        });
      }
    }
  }

  String _calculateDailyAverage(double total, int entryCount) {
    // Eğer ay seçiliyse, o ayın gün sayısını kullan
    // Eğer tümü seçiliyse, toplam gün sayısını hesapla (ilk kayıttan bugüne kadar)
    int days;
    if (_selectedMonth != null) {
      days = DateTime(
        _selectedMonth!.year,
        _selectedMonth!.month + 1,
        0,
      ).day;
    } else {
      // Tümü seçiliyse, yaklaşık olarak 30 gün kullan (veya gerçek gün sayısını hesapla)
      days = 30; // Basit yaklaşım
    }
    
    final dailyAverage = days > 0 && entryCount > 0
        ? total / days
        : 0.0;
    // Sadece TL sembolü kullan
    return NumberFormat.currency(
      symbol: '₺',
      decimalDigits: 2,
    ).format(dailyAverage);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Web'de locale data yüklenmemiş olabilir, güvenli formatlama
    String filterText;
    String filterSubtext;
    if (_selectedMonth == null) {
      filterText = 'Tümü';
      filterSubtext = 'Tüm maliyetler';
    } else {
      try {
        filterText = DateFormat('MMMM yyyy', kIsWeb ? null : 'tr_TR').format(_selectedMonth!);
        filterSubtext = 'Seçili ay';
      } catch (e) {
        filterText = DateFormat('MMMM yyyy').format(_selectedMonth!);
        filterSubtext = 'Seçili ay';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('İstatistikler'),
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectMonth,
            tooltip: 'Ay Seç',
          ),
        ],
      ),
      body: StreamBuilder<List<ExpenseEntry>>(
        stream: FirestoreService.streamMyEntries(widget.currentUser.userId),
        builder: (context, snapshot) {
          // Hata durumu - öncelikli kontrol
          if (snapshot.hasError) {
            final errorMessage = snapshot.error.toString();
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'İstatistikler yüklenirken hata oluştu',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    errorMessage.contains('permission') || errorMessage.contains('Permission')
                        ? 'Firestore izin hatası. Lütfen Firestore rules\'ı kontrol edin.'
                        : errorMessage,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // Loading durumu - sadece ilk yüklemede göster
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // Veri varsa hemen göster (cache'den veya yeni veri)
          final allEntries = snapshot.data ?? [];
          
          // İlk veri geldiğinde flag'i set et
          if (snapshot.hasData && !_hasReceivedData) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _hasReceivedData = true;
                });
              }
            });
          }
          
          // Filtrelenmiş kayıtlar (ay seçiliyse o ay, değilse tümü)
          final filteredEntries = _getFilteredEntries(allEntries);
          
          final total = filteredEntries.fold(0.0, (sum, entry) => sum + entry.amount);
          final averageAmount = filteredEntries.isEmpty ? 0.0 : total / filteredEntries.length;
          final entryCount = filteredEntries.length;

          return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ay seçici
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(
                        color: theme.colorScheme.outline.withValues(alpha: 0.08),
                        width: 1,
                      ),
                    ),
                    child: InkWell(
                      onTap: _selectMonth,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    theme.colorScheme.primaryContainer,
                                    theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.calendar_month_rounded,
                                color: theme.colorScheme.primary,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    filterSubtext,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    filterText,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 20,
                                      letterSpacing: -0.3,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Özet kartları
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Toplam',
                          value: NumberFormat.currency(
                            symbol: '₺',
                            decimalDigits: 2,
                          ).format(total),
                          icon: Icons.account_balance_wallet,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _StatCard(
                          title: 'Ortalama',
                          value: NumberFormat.currency(
                            symbol: '₺',
                            decimalDigits: 2,
                          ).format(averageAmount),
                          icon: Icons.trending_up,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Kayıt Sayısı',
                          value: '$entryCount',
                          icon: Icons.receipt_long,
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _StatCard(
                          title: _selectedMonth == null ? 'Günlük Ort.' : 'Günlük Ort.',
                          value: _calculateDailyAverage(total, entryCount),
                          icon: Icons.calendar_view_day,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // Günlük dağılım - sadece ay seçiliyse göster
                  if (_selectedMonth != null && filteredEntries.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Günlük Harcamalar',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: theme.colorScheme.outline.withValues(alpha: 0.08),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: _buildDailyBreakdown(filteredEntries),
                        ),
                      ),
                    ),
                  ] else if (filteredEntries.isEmpty)
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: theme.colorScheme.outline.withValues(alpha: 0.08),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(56),
                        child: Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.bar_chart_rounded,
                                  size: 52,
                                  color: theme.colorScheme.primary.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                _selectedMonth == null 
                                    ? 'Kayıt bulunamadı'
                                    : 'Bu ay için kayıt bulunamadı',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
        },
      ),
    );
  }

  List<Widget> _buildDailyBreakdown(List<ExpenseEntry> monthlyEntries) {
    final Map<int, double> dailyTotals = {};
    final theme = Theme.of(context);

    for (var entry in monthlyEntries) {
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
      return [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'Bu ay için günlük veri bulunamadı',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ];
    }

    return sortedDays.map((day) {
      final amount = dailyTotals[day]!;
      final percentage = maxAmount > 0 ? (amount / maxAmount) * 100 : 0.0;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                '$day',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Stack(
                children: [
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: percentage / 100,
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.primary.withValues(alpha: 0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
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
              width: 90,
              child: Text(
                NumberFormat.currency(
                  symbol: '₺',
                  decimalDigits: 0,
                ).format(amount),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: 0.2),
                        color.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 18),
                Flexible(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    softWrap: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontSize: 28,
                  letterSpacing: -0.7,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

