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
  DateTime _selectedMonth = DateTime.now();
  bool _isLoading = false;
  List<ExpenseEntry> _monthlyEntries = [];
  double _monthlyTotal = 0;
  double _averageAmount = 0;
  int _entryCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Ayın ilk günü (00:00:00)
      final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      // Ayın son günü (23:59:59.999)
      final endDate = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59, 999);

      final entries = await FirestoreService.getEntriesByDateRange(
        startDate,
        endDate,
        widget.currentUser.userId,
      );

      final total = entries.fold(0.0, (sum, entry) => sum + entry.amount);
      final average = entries.isEmpty ? 0.0 : total / entries.length;

      setState(() {
        _monthlyEntries = entries;
        _monthlyTotal = total;
        _averageAmount = average;
        _entryCount = entries.length;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _monthlyEntries = [];
        _monthlyTotal = 0;
        _averageAmount = 0;
        _entryCount = 0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İstatistikler yüklenirken hata: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectMonth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('tr', 'TR'),
      helpText: 'Ay Seçin',
      cancelText: 'İptal',
      confirmText: 'Seç',
    );

    if (picked != null) {
      setState(() {
        _selectedMonth = picked;
      });
      _loadStatistics();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Web'de locale data yüklenmemiş olabilir, güvenli formatlama
    String monthName;
    try {
      monthName = DateFormat('MMMM yyyy', kIsWeb ? null : 'tr_TR').format(_selectedMonth);
    } catch (e) {
      // Locale data yüklenmemişse varsayılan format kullan
      monthName = DateFormat('MMMM yyyy').format(_selectedMonth);
    }
    
    // Günlük ortalama hesapla
    final daysInMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
    ).day;
    final dailyAverage = daysInMonth > 0 && _entryCount > 0
        ? _monthlyTotal / daysInMonth
        : 0.0;
    // Sadece TL sembolü kullan
    final dailyAverageText = NumberFormat.currency(
      symbol: '₺',
      decimalDigits: 2,
    ).format(dailyAverage);

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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ay seçici
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: InkWell(
                      onTap: _selectMonth,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.calendar_month,
                                color: theme.colorScheme.primary,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Seçili Ay',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    monthName,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
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
                  const SizedBox(height: 20),
                  // Özet kartları
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Toplam',
                          value: NumberFormat.currency(
                            symbol: '₺',
                            decimalDigits: 2,
                          ).format(_monthlyTotal),
                          icon: Icons.account_balance_wallet,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          title: 'Ortalama',
                          value: NumberFormat.currency(
                            symbol: '₺',
                            decimalDigits: 2,
                          ).format(_averageAmount),
                          icon: Icons.trending_up,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Kayıt Sayısı',
                          value: '$_entryCount',
                          icon: Icons.receipt_long,
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          title: 'Günlük Ort.',
                          value: dailyAverageText,
                          icon: Icons.calendar_view_day,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Günlük dağılım
                  if (_monthlyEntries.isNotEmpty) ...[
                    Text(
                      'Günlük Harcamalar',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: _buildDailyBreakdown(),
                        ),
                      ),
                    ),
                  ] else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.bar_chart,
                                size: 64,
                                color: theme.colorScheme.primary.withOpacity(0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Bu ay için kayıt bulunamadı',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  List<Widget> _buildDailyBreakdown() {
    final Map<int, double> dailyTotals = {};
    final theme = Theme.of(context);

    for (var entry in _monthlyEntries) {
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
                color: theme.colorScheme.onSurface.withOpacity(0.6),
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                '$day',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Stack(
                children: [
                  Container(
                    height: 24,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: percentage / 100,
                    child: Container(
                      height: 24,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: Text(
                NumberFormat.currency(
                  symbol: '₺',
                  decimalDigits: 0,
                ).format(amount),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.right,
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
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

