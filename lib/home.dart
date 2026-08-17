import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  String _username = 'User';
  String _role = '';
  String _branchName = '';

  @override
  void initState() {
    super.initState();
    _loadSessionPrefs();

    // Initialize 16 controllers for animations (matching indexes 0 to 15)
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

  Future<void> _loadSessionPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name') ??
        prefs.getString('employee_name') ??
        prefs.getString('username') ??
        prefs.getString('email')?.split('@').first ??
        'User';
    final role = prefs.getString('role') ?? '';
    final branchName = prefs.getString('branchName') ?? '';
    if (mounted) {
      setState(() {
        _username = (name.isEmpty || name == 'Menu') ? 'User' : name;
        _role = role;
        _branchName = branchName;
      });
    }
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
      ),
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

  // --------------------------- WIDGETS --------------------------------

  Widget _buildWelcomeHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF2E170F), Color(0xFF4A1A12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E170F).withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFF8EFE6),
            child: Text(
              _username.isNotEmpty ? _username[0].toUpperCase() : 'U',
              style: const TextStyle(
                color: Color(0xFF2E170F),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, $_username!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Active Shift  •  ${_role.toUpperCase()}  •  $_branchName',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 18,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
        ],
      ),
    );
  }

  Widget _buildKioskGrid(BuildContext context, List<_QuickAction> actions) {
    final double width = MediaQuery.of(context).size.width;
    int crossCount = 3;
    if (width > 900) {
      crossCount = 6;
    } else if (width > 600) {
      crossCount = 4;
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.0, // Clean square touch buttons
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        return _buildKioskCard(action);
      },
    );
  }

  Widget _buildKioskCard(_QuickAction action) {
    final int idx = action.index;
    return AnimatedBuilder(
      animation: _animations[idx]!,
      builder: (context, _) => Transform.scale(
        scale: _animations[idx]!.value,
        child: GestureDetector(
          onTapDown: (_) => _controllers[idx]!.forward(),
          onTapUp: (_) {
            _controllers[idx]!.reverse();
            action.onTap();
          },
          onTapCancel: () => _controllers[idx]!.reverse(),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: action.accentColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    action.icon,
                    color: action.accentColor,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    action.label,
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
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
    // 16 simplified POS actions grouped into 4 units
    final posActions = [
      _QuickAction(
        index: 1,
        icon: Icons.description_rounded,
        label: 'Bill Sheet',
        accentColor: const Color(0xFFEF4444),
        onTap: _openSheet,
      ),
      _QuickAction(
        index: 14,
        icon: Icons.business_rounded,
        label: 'Dealer Bills',
        accentColor: const Color(0xFFEF4444),
        onTap: _openDealerBilling,
      ),
      _QuickAction(
        index: 2,
        icon: Icons.account_balance_wallet_rounded,
        label: 'Close Shift',
        accentColor: const Color(0xFFEF4444),
        onTap: _openClosing,
      ),
      _QuickAction(
        index: 3,
        icon: Icons.payments_rounded,
        label: 'Expenses',
        accentColor: const Color(0xFFEF4444),
        onTap: _openExpense,
      ),
      _QuickAction(
        index: 15,
        icon: Icons.cake_rounded,
        label: 'Cake Orders',
        accentColor: const Color(0xFFEF4444),
        onTap: _openCake,
      ),
      _QuickAction(
        index: 0,
        icon: Icons.receipt_long_rounded,
        label: 'Billing',
        accentColor: const Color(0xFFEF4444),
        onTap: _openBilling,
      ),
    ];

    final stockActions = [
      _QuickAction(
        index: 4,
        icon: Icons.inventory_2_rounded,
        label: 'Stock Order',
        accentColor: const Color(0xFF0F766E),
        onTap: _openStock,
      ),
      _QuickAction(
        index: 5,
        icon: Icons.assignment_return_rounded,
        label: 'Return Stock',
        accentColor: const Color(0xFF0F766E),
        onTap: _openReturn,
      ),
      _QuickAction(
        index: 9,
        icon: Icons.check_circle_outline_rounded,
        label: 'Instock Entry',
        accentColor: const Color(0xFF0F766E),
        onTap: _openInstock,
      ),
      _QuickAction(
        index: 10,
        icon: Icons.warehouse_rounded,
        label: 'Stock Levels',
        accentColor: const Color(0xFF0F766E),
        onTap: _openStockStatus,
      ),
      _QuickAction(
        index: 6,
        icon: Icons.assignment_rounded,
        label: 'Stock Logs',
        accentColor: const Color(0xFF0F766E),
        onTap: _openStockReport,
      ),
    ];

    final operationActions = [
      _QuickAction(
        index: 11,
        icon: Icons.table_bar_rounded,
        label: 'Table Map',
        accentColor: const Color(0xFFD97706),
        onTap: _openTableTracking,
      ),
      _QuickAction(
        index: 8,
        icon: Icons.table_restaurant_rounded,
        label: 'Table Design',
        accentColor: const Color(0xFFD97706),
        onTap: _openTableCreation,
      ),
      _QuickAction(
        index: 12,
        icon: Icons.soup_kitchen_rounded,
        label: 'Chef Screen',
        accentColor: const Color(0xFFD97706),
        onTap: _openChefManagement,
      ),
      _QuickAction(
        index: 13,
        icon: Icons.qr_code_2_rounded,
        label: 'QR Control',
        accentColor: const Color(0xFFD97706),
        onTap: _openFavoriteRules,
      ),
    ];

    final systemActions = [
      _QuickAction(
        index: 7,
        icon: Icons.qr_code_rounded,
        label: 'QR Sync',
        accentColor: const Color(0xFF7C3AED),
        onTap: _openQrUpdate,
      ),
    ];

    return CommonScaffold(
      title: 'Branch POS',
      pageType: PageType.home,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeHeader(context),
            _buildSectionHeader('Sales & Checkout', const Color(0xFFEF4444)),
            _buildKioskGrid(context, posActions),
            _buildSectionHeader('Stock & Inventory', const Color(0xFF0F766E)),
            _buildKioskGrid(context, stockActions),
            _buildSectionHeader('Dining & Kitchen', const Color(0xFFD97706)),
            _buildKioskGrid(context, operationActions),
            _buildSectionHeader('Others', const Color(0xFF7C3AED)),
            _buildKioskGrid(context, systemActions),
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  final int index;
  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  const _QuickAction({
    required this.index,
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });
}
