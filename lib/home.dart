import 'package:flutter/material.dart';
import 'common_scaffold.dart';
import 'closingentry.dart';
import 'expense.dart';
import 'categories_page.dart';
import 'billsheet.dart';
import 'qr_update_page.dart';
import 'stock_order.dart';
import 'stockorder_reports.dart'; // NEW IMPORT for stockorder_reports.dart

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final Map<int, AnimationController> _controllers = {};
  final Map<int, Animation<double>> _animations = {};

  @override
  void initState() {
    super.initState();
    // Updated: 8 cards in main grid + 3 in reports row (indices 0-7 for main, 8-10 for reports)
    for (int i = 0; i < 11; i++) {
      _controllers[i] = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 150),
      );
      _animations[i] = Tween<double>(begin: 1.0, end: 0.95).animate(
        CurvedAnimation(parent: _controllers[i]!, curve: Curves.easeOut),
      );
    }
  }

  @override
  void dispose() {
    _controllers.values.forEach((c) => c.dispose());
    super.dispose();
  }

  // --------------------------- NAVIGATION --------------------------------

  /// Billing
  void _openBilling() {
    Navigator.push(
      context,
      _createRoute(const CategoriesPage()),
    );
  }

  /// Stock Order (existing, from stock_order.dart)
  void _openStock() {
    Navigator.push(
      context,
      _createRoute(const StockOrderPage()),
    );
  }

  /// ⭐ Return Order (Corrected)
  /// DOES NOT HIGHLIGHT BILLSHEET
  void _openReturn() {
    Navigator.push(
      context,
      _createRoute(const CategoriesPage(isReturnOrder: true)),
    );
  }

  /// Bill Sheet
  void _openSheet() {
    Navigator.push(context, _createRoute(const BillSheetPage()));
  }

  void _openClosing() {
    Navigator.push(context, _createRoute(const ClosingEntryPage()));
  }

  void _openExpense() {
    Navigator.push(context, _createRoute(const ExpenseDetailsPage()));
  }

  void _openQrUpdate() {
    Navigator.push(context, _createRoute(const QrUpdatePage()));
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coming soon ✨'),
        backgroundColor: Colors.deepPurple,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // NEW: Open Stock Report (from stockorder_reports.dart)
  void _openStockReport() {
    Navigator.push(
      context,
      _createRoute(const StockOrdersPage()), // Assuming class name; adjust if different
    );
  }

  /// Custom fade route
  Route _createRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, animation, __) => FadeTransition(
        opacity: animation,
        child: page,
      ),
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  // --------------------------- CARD UI --------------------------------

  Widget _buildCard(
      int index,
      IconData? icon, // Changed to nullable
      Color start,
      Color end,
      String label,
      VoidCallback onTap,
      {double size = 140} // Use single size for square
      ) {
    return AnimatedBuilder(
      animation: _animations[index]!,
      builder: (context, _) => Transform.scale(
        scale: _animations[index]!.value,
        child: GestureDetector(
          onTapDown: (_) => _controllers[index]!.forward(),
          onTapUp: (_) {
            _controllers[index]!.reverse();
            onTap();
          },
          onTapCancel: () => _controllers[index]!.reverse(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16), // Reduced for compactness
              gradient: LinearGradient(
                colors: [start, end],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: start.withOpacity(0.4),
                  blurRadius: 12, // Reduced blur for compactness
                  offset: const Offset(0, 6), // Reduced offset
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 48, color: Colors.white), // Reduced icon size if present
                  const SizedBox(height: 8), // Reduced spacing
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16, // Reduced font size for compactness
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------- MAIN UI --------------------------------

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return CommonScaffold(
      title: 'Dashboard',
      pageType: PageType.home,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final crossCount = constraints.maxWidth > 600 ? 4 : 2;

                return GridView.count(
                  crossAxisCount: crossCount,
                  crossAxisSpacing: 24,
                  mainAxisSpacing: 24,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.0, // Square
                  children: [
                    _buildCard(
                      0,
                      Icons.receipt_long,
                      const Color(0xFF00C9FF),
                      const Color(0xFF92FE9D),
                      'Billing',
                      _openBilling,
                    ),

                    _buildCard(
                      1,
                      Icons.table_chart,
                      const Color(0xFFFF6B6B),
                      const Color(0xFFFF8E53),
                      'Sheet',
                      _openSheet,
                    ),

                    _buildCard(
                      2,
                      Icons.account_balance_wallet,
                      const Color(0xFFFFD700),
                      const Color(0xFFFFA500),
                      'Closing',
                      _openClosing,
                    ),

                    _buildCard(
                      3,
                      Icons.payments,
                      const Color(0xFFE91E63),
                      const Color(0xFFFF4081),
                      'Expense',
                      _openExpense,
                    ),

                    _buildCard(
                      4,
                      Icons.inventory_2,
                      const Color(0xFF4FACFE),
                      const Color(0xFF00F2FE),
                      'Stock',
                      _openStock,
                    ),

                    /// ⭐ FIXED — Return opens return categories & no footer highlight
                    _buildCard(
                      5,
                      Icons.assignment_return,
                      const Color(0xFFFF5E7E),
                      const Color(0xFFFF9A9E),
                      'Return',
                      _openReturn,
                    ),

                    // Removed Reports card

                    _buildCard(
                      6, // Shifted index (was 7)
                      Icons.shopping_cart,
                      const Color(0xFFFA8BFF),
                      const Color(0xFF8B6CFF),
                      'Orders',
                      _comingSoon,
                    ),

                    _buildCard(
                      7, // Shifted index (was 8)
                      Icons.qr_code,
                      const Color(0xFF7F00FF),
                      const Color(0xFFE100FF),
                      'QR Update',
                      _openQrUpdate,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 32), // Slightly reduced spacing

            // NEW: Reports Row with 3 smaller cards in one row
            const Text(
              'Reports',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12), // Reduced spacing
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: _buildCard(
                    8, // New index
                    null, // No icon
                    const Color(0xFF4FACFE),
                    const Color(0xFF00F2FE),
                    'Stock',
                    _openStockReport,
                    size: 100, // Reduced size for compact squares
                  ),
                ),
                const SizedBox(width: 12), // Reduced spacing
                Expanded(
                  child: _buildCard(
                    9, // New index
                    null, // No icon
                    const Color(0xFFFF5E7E),
                    const Color(0xFFFF9A9E),
                    'Return',
                    _comingSoon, // Replace if needed
                    size: 100,
                  ),
                ),
                const SizedBox(width: 12), // Reduced spacing
                Expanded(
                  child: _buildCard(
                    10, // New index
                    null, // No icon
                    const Color(0xFFFF6B6B),
                    const Color(0xFFFF8E53),
                    'Cakes',
                    _comingSoon, // Replace if needed
                    size: 100,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32), // Slightly reduced spacing

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _quickStat('Total Stock', '12,847', Colors.blue),
                  _quickStat('Pending Returns', '23', Colors.red),
                  _quickStat('Today Expense', '₹8,420', Colors.pink),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Quick statistics UI
  Widget _quickStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
      ],
    );
  }
}