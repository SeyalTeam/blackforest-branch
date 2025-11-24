// lib/home.dart
import 'package:flutter/material.dart';
import 'common_scaffold.dart';
import 'closingentry.dart';
import 'expense.dart';
import 'categories_page.dart';
import 'billsheet.dart';
import 'qr_update_page.dart';
import 'stock_order.dart';   // IMPORTANT

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
    for (int i = 0; i < 9; i++) {
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

  void _openBilling() {
    Navigator.pushAndRemoveUntil(
      context,
      _createRoute(const CategoriesPage()),
          (route) => false,
    );
  }

  /// ⭐ FIXED — Stock now navigates to StockOrderPage() only
  void _openStock() {
    Navigator.push(
      context,
      _createRoute(const StockOrderPage()),
    );
  }

  void _openReturn() {
    Navigator.pushAndRemoveUntil(
      context,
      _createRoute(const CategoriesPage(isStockFilter: true)),
          (route) => false,
    );
  }

  void _openSheet() {
    Navigator.push(context, _createRoute(const BillSheetPage()));
  }

  void _openClosing() =>
      Navigator.push(context, _createRoute(const ClosingEntryPage()));

  void _openExpense() =>
      Navigator.push(context, _createRoute(const ExpenseDetailsPage()));

  void _openQrUpdate() =>
      Navigator.push(context, _createRoute(const QrUpdatePage()));

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coming soon ✨'),
        backgroundColor: Colors.deepPurple,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Route _createRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  Widget _buildCard(
      int index,
      IconData icon,
      Color start,
      Color end,
      String label,
      VoidCallback onTap,
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
            width: 140,
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [start, end],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: start.withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 56, color: Colors.white),
                const SizedBox(height: 16),
                Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
                  childAspectRatio: 1.1,
                  children: [
                    _buildCard(0, Icons.receipt_long,
                        const Color(0xFF00C9FF), const Color(0xFF92FE9D),
                        'Billing', _openBilling),
                    _buildCard(1, Icons.table_chart,
                        const Color(0xFFFF6B6B), const Color(0xFFFF8E53),
                        'Sheet', _openSheet),
                    _buildCard(2, Icons.account_balance_wallet,
                        const Color(0xFFFFD700), const Color(0xFFFFA500),
                        'Closing', _openClosing),
                    _buildCard(3, Icons.payments,
                        const Color(0xFFE91E63), const Color(0xFFFF4081),
                        'Expense', _openExpense),

                    /// ⭐ FIXED — correct stock navigation
                    _buildCard(4, Icons.inventory_2,
                        const Color(0xFF4FACFE), const Color(0xFF00F2FE),
                        'Stock', _openStock),

                    _buildCard(5, Icons.assignment_return,
                        const Color(0xFFFF5E7E), const Color(0xFFFF9A9E),
                        'Return', _openReturn),
                    _buildCard(6, Icons.bar_chart,
                        const Color(0xFF43E97B), const Color(0xFF38F9D7),
                        'Reports', _comingSoon),
                    _buildCard(7, Icons.shopping_cart,
                        const Color(0xFFFA8BFF), const Color(0xFF8B6CFF),
                        'Orders', _comingSoon),
                    _buildCard(8, Icons.qr_code,
                        const Color(0xFF7F00FF), const Color(0xFFE100FF),
                        'QR Update', _openQrUpdate),
                  ],
                );
              },
            ),

            const SizedBox(height: 40),

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

  Widget _quickStat(String label, String value, Color color) => Column(
    children: [
      Text(value,
          style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold, color: color)),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
    ],
  );
}
