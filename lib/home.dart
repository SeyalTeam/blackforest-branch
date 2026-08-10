import 'package:flutter/material.dart';
import 'common_scaffold.dart';
import 'closingentry.dart';
import 'expense.dart';
import 'categories_page.dart';
import 'billsheet.dart';
import 'qr_update_page.dart';
import 'stock_order.dart';
import 'stockorder_report.dart';
import 'table_creation_page.dart';
import 'stock_status_page.dart';
import 'table_tracking_page.dart';
import 'kitchen_chef_page.dart';
import 'favorite_rules_page.dart';
import 'dealer_billing.dart';
import 'cake_order_page.dart';

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
    // Updated to 16 cards
    for (int i = 0; i < 16; i++) {
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
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // --------------------------- NAVIGATION --------------------------------

  void _openBilling() {
    Navigator.push(context, _createRoute(const CategoriesPage()));
  }

  void _openStock() {
    Navigator.push(context, _createRoute(const StockOrderPage()));
  }

  void _openInstock() {
    Navigator.push(
      context,
      _createRoute(
        const CategoriesPage(isInstockEntry: true),
      ), // Reuse categories with instock flag
    );
  }

  void _openReturn() {
    Navigator.push(
      context,
      _createRoute(const CategoriesPage(isReturnOrder: true)),
    );
  }

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

  void _openStockReport() {
    Navigator.push(context, _createRoute(const StockOrderReportPage()));
  }

  void _openStockStatus() {
    Navigator.push(context, _createRoute(const StockStatusPage()));
  }

  void _openTableTracking() {
    Navigator.push(context, _createRoute(const TableTrackingPage()));
  }

  void _openTableCreation() {
    Navigator.push(context, _createRoute(const TableCreationPage()));
  }

  void _openChefManagement() {
    Navigator.push(
      context,
      _createRoute(const KitchenChefPage(showNamesOnly: true)),
    );
  }

  void _openFavoriteRules() {
    Navigator.push(context, _createRoute(const FavoriteRulesPage()));
  }

  void _openDealerBilling() {
    Navigator.push(context, _createRoute(const DealerBillingPage()));
  }

  void _openCake() {
    Navigator.push(context, _createRoute(const CakeOrderPage()));
  }

  Route _createRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, animation, __) =>
          FadeTransition(opacity: animation, child: page),
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  // --------------------------- CARD UI --------------------------------

  Widget _buildCard(
    int index,
    IconData? icon,
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
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [start, end],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: start.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compactCard =
                    constraints.maxWidth < 110 || constraints.maxHeight < 110;
                final iconSize = compactCard ? 30.0 : 48.0;
                final labelSize = compactCard ? 12.0 : 16.0;
                final gap = compactCard ? 4.0 : 8.0;
                final verticalPadding = compactCard ? 8.0 : 12.0;

                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: verticalPadding,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: iconSize, color: Colors.white),
                        SizedBox(height: gap),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: labelSize,
                            fontWeight: FontWeight.bold,
                            height: 1.15,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------- MAIN UI --------------------------------

  @override
  Widget build(BuildContext context) {
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
                final crossCount = constraints.maxWidth > 600 ? 4 : 3;
                final compactGrid = constraints.maxWidth <= 420;
                final spacing = compactGrid ? 12.0 : 24.0;

                return GridView.count(
                  crossAxisCount: crossCount,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.0,
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
                      const Color(0xFFD32F2F),
                      const Color(0xFFFF1744),
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

                    _buildCard(
                      9, // New Instock Card
                      Icons.check_circle_outline, // Distinct icon
                      const Color(0xFF11998e),
                      const Color(0xFF38ef7d),
                      'Instock',
                      _openInstock,
                    ),

                    _buildCard(
                      5,
                      Icons.assignment_return,
                      const Color(0xFFFF5E7E),
                      const Color(0xFFFF9A9E),
                      'Return',
                      _openReturn,
                    ),

                    _buildCard(
                      6,
                      Icons.assignment,
                      const Color(0xFFFF9966),
                      const Color(0xFFFF5E62),
                      'Stock Report',
                      _openStockReport,
                    ),

                    _buildCard(
                      7,
                      Icons.qr_code,
                      const Color(0xFF7F00FF),
                      const Color(0xFFE100FF),
                      'QR Update',
                      _openQrUpdate,
                    ),

                    _buildCard(
                      10,
                      Icons.inventory,
                      const Color(0xFF1565C0),
                      const Color(0xFF42A5F5),
                      'Stock Status',
                      _openStockStatus,
                    ),

                    _buildCard(
                      11,
                      Icons.table_bar,
                      const Color(0xFF546E7A),
                      const Color(0xFF78909C),
                      'Table',
                      _openTableTracking,
                    ),

                    _buildCard(
                      8,
                      Icons.table_restaurant,
                      const Color(0xFF607D8B),
                      const Color(0xFF90A4AE),
                      'Table Creation',
                      _openTableCreation,
                    ),

                    _buildCard(
                      12,
                      Icons.soup_kitchen,
                      const Color(0xFF795548),
                      const Color(0xFFA1887F),
                      'Chef',
                      _openChefManagement,
                    ),

                    _buildCard(
                      13,
                      Icons.qr_code_2,
                      const Color(0xFFFFB75E),
                      const Color(0xFFED8F03),
                      'QRC',
                      _openFavoriteRules,
                    ),

                    _buildCard(
                      14,
                      Icons.business,
                      const Color(0xFF00796B),
                      const Color(0xFF00BFA5),
                      'Dealer Billing',
                      _openDealerBilling,
                    ),

                    _buildCard(
                      15,
                      Icons.cake,
                      const Color(0xFFD81B60),
                      const Color(0xFFF48FB1),
                      'Cake',
                      _openCake,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
