/**
 * Sabit Giderler sekmesi
 * Google Sheets'ten sabit giderleri görüntüler (dinamik okuma)
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
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

enum SortOption {
  amountDesc,
  amountAsc,
  descriptionAsc,
  descriptionDesc,
}

class _FixedExpensesTabState extends State<FixedExpensesTab> with AutomaticKeepAliveClientMixin {
  List<FixedExpense> _expenses = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;
  final TextEditingController _searchController = TextEditingController();
  SortOption _sortOption = SortOption.amountDesc;
  bool _showOnlyActive = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadExpensesFromGoogleSheets();
    // Her 30 saniyede bir otomatik yenile
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadExpensesFromGoogleSheets();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
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
      });
    } catch (e) {
      AppLogger.error('Google Sheets yükleme hatası', e);
      setState(() {
        _isLoading = false;
        // Daha kullanıcı dostu ve detaylı hata mesajı
        final errorMsg = e.toString();
        String userFriendlyMessage = '';
        
        if (errorMsg.contains('Supabase\'e bağlanılamıyor') || errorMsg.contains('İnternet bağlantısı yok')) {
          userFriendlyMessage = 'Supabase\'e bağlanılamıyor. İnternet bağlantınızı kontrol edin veya daha sonra tekrar deneyin.';
        } else if (errorMsg.contains('zaman aşımı') || errorMsg.contains('timeout')) {
          userFriendlyMessage = 'Google Sheets okuma zaman aşımı. Lütfen tekrar deneyin.';
        } else if (errorMsg.contains('404') || errorMsg.contains('bulunamadı')) {
          userFriendlyMessage = 'Google Sheets dosyası veya sheet bulunamadı. Lütfen dosya ayarlarını kontrol edin.';
        } else if (errorMsg.contains('403') || errorMsg.contains('erişim izni')) {
          userFriendlyMessage = 'Dosyaya erişim izni yok. Google Sheets dosyasını "Herkes linki olan herkes görüntüleyebilir" olarak paylaşın.';
        } else if (errorMsg.contains('detail')) {
          // Backend'den gelen detaylı hata mesajını göster
          userFriendlyMessage = errorMsg;
        } else {
          userFriendlyMessage = 'Sabit giderler yüklenirken hata oluştu:\n${errorMsg.length > 200 ? errorMsg.substring(0, 200) + "..." : errorMsg}';
        }
        
        _errorMessage = userFriendlyMessage;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      body: _buildContent(theme, isSmallScreen),
    );
  }

  Widget _buildContent(ThemeData theme, bool isSmallScreen) {
    if (_isLoading) {
      return const LoadingWidget(message: 'Sabit giderler yükleniyor...');
    }

    if (_errorMessage != null) {
      return ErrorRetryWidget(
        message: _errorMessage!,
        onRetry: _loadExpensesFromGoogleSheets,
      );
    }

    if (_expenses.isEmpty) {
      return EmptyStateWidget(
        title: 'Sabit gider bulunamadı',
        subtitle: 'Google Sheets\'te veri yok veya format hatalı',
        icon: Icons.receipt_long,
      );
    }

    // Filtreleme ve arama
    var filteredExpenses = _expenses;
    
    // Arama filtresi
    if (_searchController.text.isNotEmpty) {
      final searchLower = _searchController.text.toLowerCase();
      filteredExpenses = filteredExpenses.where((e) {
        return e.description.toLowerCase().contains(searchLower) ||
               (e.category != null && e.category!.toLowerCase().contains(searchLower)) ||
               e.ownerName.toLowerCase().contains(searchLower) ||
               (e.notes != null && e.notes!.toLowerCase().contains(searchLower));
      }).toList();
    }
    
    // Aktif/pasif filtresi
    if (_showOnlyActive) {
      filteredExpenses = filteredExpenses.where((e) => e.isActive).toList();
    }
    
    // Sıralama
    filteredExpenses = _sortExpenses(filteredExpenses);

    if (filteredExpenses.isEmpty) {
      return Column(
        children: [
          _buildHeader(theme, isSmallScreen),
          Expanded(
            child: EmptyStateWidget(
              title: 'Arama/Filtre sonucu bulunamadı',
              subtitle: 'Farklı bir arama terimi veya filtre deneyin',
              icon: Icons.search_off,
            ),
          ),
        ],
      );
    }

    // Toplam hesapla (filtrelenmiş ve aktif olanlar)
    final totalAmount = filteredExpenses.where((e) => e.isActive).fold<double>(
      0.0,
      (sum, expense) => sum + expense.amount,
    );

    return Column(
      children: [
        _buildHeader(theme, isSmallScreen),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadExpensesFromGoogleSheets,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              shrinkWrap: false,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: filteredExpenses.length + (filteredExpenses.isNotEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                // İlk item toplam kartı
                if (index == 0 && filteredExpenses.isNotEmpty) {
                  final activeCount = filteredExpenses.where((e) => e.isActive).length;
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
                              _searchController.text.isNotEmpty || _showOnlyActive
                                  ? 'Filtrelenmiş Toplam'
                                  : 'Aylık Toplam',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
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
                            if (activeCount > 0)
                              Text(
                                '$activeCount aktif',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                }
                
                // Expense item'ları (index - 1 çünkü ilk item toplam kartı)
                final expenseIndex = filteredExpenses.isNotEmpty ? index - 1 : index;
                return RepaintBoundary(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildExpenseCard(filteredExpenses[expenseIndex], theme, isSmallScreen),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  List<FixedExpense> _sortExpenses(List<FixedExpense> expenses) {
    final sorted = List<FixedExpense>.from(expenses);
    switch (_sortOption) {
      case SortOption.amountDesc:
        sorted.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case SortOption.amountAsc:
        sorted.sort((a, b) => a.amount.compareTo(b.amount));
        break;
      case SortOption.descriptionAsc:
        sorted.sort((a, b) => a.description.compareTo(b.description));
        break;
      case SortOption.descriptionDesc:
        sorted.sort((a, b) => b.description.compareTo(a.description));
        break;
    }
    return sorted;
  }

  Widget _buildHeader(ThemeData theme, bool isSmallScreen) {
    return Container(
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
          // Başlık
          Text(
            'Sabit Giderler',
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
              PopupMenuItem(
                value: SortOption.descriptionAsc,
                child: Row(
                  children: [
                    Icon(
                      Icons.arrow_upward,
                      size: 18,
                      color: _sortOption == SortOption.descriptionAsc
                          ? theme.colorScheme.primary
                          : null,
                    ),
                    const SizedBox(width: 8),
                    const Text('Açıklama (A → Z)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: SortOption.descriptionDesc,
                child: Row(
                  children: [
                    Icon(
                      Icons.arrow_downward,
                      size: 18,
                      color: _sortOption == SortOption.descriptionDesc
                          ? theme.colorScheme.primary
                          : null,
                    ),
                    const SizedBox(width: 8),
                    const Text('Açıklama (Z → A)'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Filtre butonu (sadece aktif göster)
          IconButton(
            icon: Icon(
              _showOnlyActive ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: _showOnlyActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            tooltip: _showOnlyActive ? 'Tümünü göster' : 'Sadece aktifleri göster',
            onPressed: () {
              setState(() {
                _showOnlyActive = !_showOnlyActive;
              });
            },
          ),
          // Yenile butonu
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadExpensesFromGoogleSheets,
            tooltip: 'Yenile',
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(FixedExpense expense, ThemeData theme, bool isSmallScreen) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Material(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(20),
          elevation: 0,
          child: InkWell(
            onTap: () => _showExpenseDetails(expense, theme),
            borderRadius: BorderRadius.circular(20),
            splashColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
            highlightColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.05),
                  width: 0.5,
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
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Üst kısım: İkon, Açıklama, Miktar
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // İkon - EntryCard gibi 48x48 Container
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: expense.isActive
                                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            expense.isActive ? Icons.receipt_long_rounded : Icons.pause_circle_rounded,
                            color: expense.isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Açıklama ve detaylar - Expanded ile overflow önleniyor
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                expense.description,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  letterSpacing: -0.2,
                                  height: 1.3,
                                  decoration: expense.isActive ? null : TextDecoration.lineThrough,
                                  color: expense.isActive 
                                      ? null 
                                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              // Kategori ve kişi - EntryCard gibi ikonlu, tek satırda
                              Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                children: [
                                  if (expense.category != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.category_rounded,
                                          size: 12,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            expense.category!,
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.primary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.person_outline_rounded,
                                        size: 12,
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          expense.ownerName,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (expense.recurrence != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.repeat_rounded,
                                          size: 12,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            _getRecurrenceText(expense.recurrence!),
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
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
                    // Miktar badge - tam genişlik, ortalanmış
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: expense.isActive
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          NumberFormat.currency(
                            symbol: '₺',
                            decimalDigits: 0,
                            locale: 'tr_TR',
                          ).format(expense.amount),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: expense.isActive
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            letterSpacing: 0,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
