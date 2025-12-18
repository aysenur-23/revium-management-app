/**
 * Sabit Giderler sekmesi
 * Google Sheets'ten sabit giderleri görüntüler (dinamik okuma)
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../home_screen.dart';
import '../../utils/app_logger.dart';
import '../../models/fixed_expense.dart';
import '../../services/google_sheets_service.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/error_retry_widget.dart';
import '../../widgets/loading_widget.dart';

class FixedExpensesTab extends StatefulWidget {
  final UserProfile? currentUser;

  const FixedExpensesTab({
    super.key,
    this.currentUser,
  });

  @override
  State<FixedExpensesTab> createState() => _FixedExpensesTabState();
}

class _FixedExpensesTabState extends State<FixedExpensesTab> with AutomaticKeepAliveClientMixin {
  List<FixedExpense> _expenses = [];
  bool _isLoading = true;
  String? _errorMessage;
  DateTime? _lastLoadTime;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadExpensesFromGoogleSheets();
  }

  /// Google Sheets'ten sabit giderleri yükler
  Future<void> _loadExpensesFromGoogleSheets() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final expenses = await GoogleSheetsService.getFixedExpenses();
      
      setState(() {
        _expenses = expenses;
        _isLoading = false;
        _lastLoadTime = DateTime.now();
      });
    } catch (e) {
      AppLogger.error('Google Sheets yükleme hatası', e);
      setState(() {
        _isLoading = false;
        _errorMessage = 'Sabit giderler yüklenirken hata oluştu: ${e.toString()}';
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      body: Column(
        children: [
          // Başlık
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                Text(
                  'Sabit Giderler',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                const Spacer(),
                // Yenile butonu ve son yükleme zamanı
                Row(
                  children: [
                    if (_lastLoadTime != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          'Son güncelleme: ${DateFormat('HH:mm').format(_lastLoadTime!)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: _loadExpensesFromGoogleSheets,
                      tooltip: 'Yenile',
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Liste
          Expanded(
            child: _buildContent(theme, isSmallScreen),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, bool isSmallScreen) {
    if (_isLoading) {
      return const LoadingWidget(message: 'Sabit giderler yükleniyor...');
    }

    if (_errorMessage != null) {
      return ErrorRetryWidget(
        message: _errorMessage!,
        onRetry: _loadExpensesFromCSV,
      );
    }

    if (_expenses.isEmpty) {
      return EmptyStateWidget(
        title: 'Sabit gider bulunamadı',
        subtitle: 'Google Sheets\'te veri yok veya format hatalı',
        icon: Icons.receipt_long,
      );
    }

    // Aktif ve pasif giderleri ayır
    final activeExpenses = _expenses.where((e) => e.isActive).toList();
    final inactiveExpenses = _expenses.where((e) => !e.isActive).toList();

    // Toplam hesapla (sadece aktif olanlar)
    final totalAmount = activeExpenses.fold<double>(
      0.0,
      (sum, expense) => sum + expense.amount,
    );

    return RefreshIndicator(
      onRefresh: _loadExpensesFromGoogleSheets,
      child: ListView(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
        children: [
          // Toplam kartı
          Card(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aylık Toplam Sabit Gider',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        NumberFormat.currency(
                          symbol: '₺',
                          decimalDigits: 2,
                          locale: 'tr_TR',
                        ).format(totalAmount),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${activeExpenses.length} aktif gider',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Aktif giderler
          if (activeExpenses.isNotEmpty) ...[
            Text(
              'Aktif Giderler',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...activeExpenses.map((expense) => RepaintBoundary(
              child: _buildExpenseCard(expense, theme, isSmallScreen),
            )),
            const SizedBox(height: 16),
          ],
          // Pasif giderler
          if (inactiveExpenses.isNotEmpty) ...[
            Text(
              'Pasif Giderler',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            ...inactiveExpenses.map((expense) => RepaintBoundary(
              child: _buildExpenseCard(expense, theme, isSmallScreen),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildExpenseCard(FixedExpense expense, ThemeData theme, bool isSmallScreen) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showExpenseDetails(expense, theme),
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sol ikon
                  CircleAvatar(
                    backgroundColor: expense.isActive
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      expense.isActive ? Icons.check_circle : Icons.pause_circle,
                      color: expense.isActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Açıklama ve detaylar
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          expense.description,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            decoration: expense.isActive ? null : TextDecoration.lineThrough,
                            color: expense.isActive ? null : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (expense.category != null)
                          Text(
                            expense.category!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        Text(
                          expense.ownerName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Tutar
                  Text(
                    NumberFormat.currency(
                      symbol: '₺',
                      decimalDigits: 2,
                      locale: 'tr_TR',
                    ).format(expense.amount),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: expense.isActive 
                          ? theme.colorScheme.primary 
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              // Alt bilgiler
              if (expense.recurrence != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getRecurrenceText(expense.recurrence!),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
              // Notlar
              if (expense.notes != null && expense.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  expense.notes!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _getRecurrenceText(String recurrence) {
    switch (recurrence.toLowerCase()) {
      case 'monthly':
        return 'Aylık';
      case 'yearly':
        return 'Yıllık';
      case 'one-time':
        return 'Tek Seferlik';
      default:
        return recurrence;
    }
  }

  /// Sabit gider detaylarını gösterir (sadece görüntüleme)
  void _showExpenseDetails(FixedExpense expense, ThemeData theme) {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Başlık ve durum
            Row(
              children: [
                Expanded(
                  child: Text(
                    expense.description,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: expense.isActive ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    expense.isActive ? 'Aktif' : 'Pasif',
                    style: TextStyle(
                      color: expense.isActive ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Tutar
            _buildDetailRow(theme, Icons.currency_lira_rounded, 'Tutar', 
              NumberFormat.currency(symbol: '₺', decimalDigits: 2, locale: 'tr_TR').format(expense.amount),
              isPrimary: true),
            if (expense.category != null)
              _buildDetailRow(theme, Icons.category_rounded, 'Kategori', expense.category!),
            _buildDetailRow(theme, Icons.person_rounded, 'Kaynak', expense.ownerName),
            if (expense.recurrence != null)
              _buildDetailRow(theme, Icons.repeat_rounded, 'Tekrarlama', _getRecurrenceText(expense.recurrence!)),
            if (expense.notes != null && expense.notes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Notlar', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
              const SizedBox(height: 4),
              Text(expense.notes!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 16),
            // Bilgilendirme
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Sabit giderler Google Sheets\'ten dinamik olarak yüklenmektedir. Yeni eklemeler otomatik olarak görünecektir.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(ThemeData theme, IconData icon, String label, String value, {bool isPrimary = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: isPrimary ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 12),
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          const Spacer(),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: isPrimary ? FontWeight.w700 : FontWeight.w500,
            color: isPrimary ? theme.colorScheme.primary : null,
          )),
        ],
      ),
    );
  }
}
