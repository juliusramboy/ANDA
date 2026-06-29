import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/borrower.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'borrower_detail_screen.dart';
import 'add_loan_screen.dart';

class BorrowersScreen extends StatefulWidget {
  const BorrowersScreen({super.key});

  @override
  State<BorrowersScreen> createState() => _BorrowersScreenState();
}

class _BorrowersScreenState extends State<BorrowersScreen> {
  final db = DatabaseHelper.instance;
  final fmt = NumberFormat('#,##0.00');
  List<Borrower> borrowers = [];
  List<Borrower> filtered = [];
  int activeCount = 0;
  bool loading = true;
  final searchCtrl = TextEditingController();
  bool searching = false;

  @override
  void initState() {
    super.initState();
    _load();
    searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await db.getAllBorrowers();
    final ac = await db.getActiveBorrowers();
    setState(() {
      borrowers = all;
      filtered = all;
      activeCount = ac;
      loading = false;
    });
  }

  void _filter() {
    final q = searchCtrl.text.toLowerCase();
    setState(() {
      filtered =
          borrowers.where((b) => b.fullName.toLowerCase().contains(q)).toList();
    });
  }

  bool _isDue(Borrower b) {
    if (b.status != 'active') return false;
    try {
      final d = DateFormat('MM/dd/yyyy').parse(b.repaymentDate);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dueDay = DateTime(d.year, d.month, d.day);
      return dueDay.isBefore(today) || dueDay.isAtSameMomentAs(today);
    } catch (_) {
      return false;
    }
  }

  String _nextDue(Borrower b) {
    try {
      final d = DateFormat('MM/dd/yyyy').parse(b.repaymentDate);
      return DateFormat('MMM dd').format(d);
    } catch (_) {
      return b.repaymentDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Header ──
                          Row(
                            children: [
                              if (Navigator.canPop(context)) ...[
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(
                                    Icons.arrow_back_ios_new,
                                    size: 20,
                                    color: AppTheme.navy,
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('YOUR VAULT',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textGrey,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5)),
                                    Text(
                                      '${borrowers.length} Borrowers.',
                                      style: const TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textDark),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: () =>
                                        setState(() => searching = !searching),
                                    icon: const Icon(Icons.search),
                                    color: AppTheme.navy,
                                  ),
                                  Container(
                                    decoration: const BoxDecoration(
                                        color: AppTheme.navy,
                                        shape: BoxShape.circle),
                                    child: IconButton(
                                      onPressed: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  const AddLoanScreen()),
                                        );
                                        _load();
                                      },
                                      icon: const Icon(Icons.add,
                                          color: AppTheme.white),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          if (searching) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: searchCtrl,
                              autofocus: true,
                              decoration: InputDecoration(
                                hintText: 'Search borrowers...',
                                prefixIcon: const Icon(Icons.search),
                                filled: true,
                                fillColor: AppTheme.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),

                          // ── Active card ──
                          NavyCard(
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  right: 0,
                                  top: -10,
                                  child: Text(
                                    '$activeCount',
                                    style: TextStyle(
                                      fontSize: 80,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.yellow.withOpacity(0.3),
                                    ),
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.people,
                                        color: AppTheme.yellow, size: 28),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Active Borrowers',
                                      style: TextStyle(
                                          color: AppTheme.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const Text(
                                      'Currently enrolled and active',
                                      style: TextStyle(
                                          color: Colors.white60, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),

                    // ── Grid ──
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('No borrowers found.',
                                  style: TextStyle(color: AppTheme.textGrey)))
                          : GridView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.1,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final b = filtered[i];
                                final isDue = _isDue(b) && b.dismissedWiggleDate != b.repaymentDate;
                                return WiggleWrapper(
                                  wiggle: isDue,
                                  child: GestureDetector(
                                    onTap: () async {
                                      if (b.id != null && b.dismissedWiggleDate != b.repaymentDate) {
                                        final updated = b.copyWith(dismissedWiggleDate: b.repaymentDate);
                                        await db.updateBorrower(updated);
                                      }
                                      if (!context.mounted) return;
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => BorrowerDetailScreen(
                                                borrowerId: b.id!)),
                                      );
                                      _load();
                                    },
                                    onLongPress: () async {
                                      if (b.id != null) {
                                        final updated = b.copyWith(dismissedWiggleDate: b.repaymentDate);
                                        await db.updateBorrower(updated);
                                        _load();
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Wiggle stopped for ${b.fullName}'),
                                            duration: const Duration(seconds: 1),
                                          ),
                                        );
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: AppTheme.white,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              AnimatedAvatar(
                                                  name: b.fullName,
                                                  size: 32),
                                              StatusDot(status: b.status),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(b.fullName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: AppTheme.textDark),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                          Text(
                                            'Next Due: ${_nextDue(b)}',
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: AppTheme.textGrey),
                                          ),
                                          const Spacer(),
                                          b.status == 'fully_paid'
                                              ? ImageFiltered(
                                                  imageFilter: ImageFilter.blur(
                                                      sigmaX: 4, sigmaY: 4),
                                                  child: Text(
                                                    '₱${fmt.format(b.amountBorrowed)}',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15,
                                                        color: AppTheme.textDark),
                                                  ),
                                                )
                                              : Text(
                                                  '₱${fmt.format(b.amountBorrowed)}',
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 15,
                                                      color: AppTheme.textDark),
                                                ),
                                        ],
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
}

class WiggleWrapper extends StatefulWidget {
  final Widget child;
  final bool wiggle;

  const WiggleWrapper({super.key, required this.child, required this.wiggle});

  @override
  State<WiggleWrapper> createState() => _WiggleWrapperState();
}

class _WiggleWrapperState extends State<WiggleWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _animation = Tween<double>(begin: -0.025, end: 0.025).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    if (widget.wiggle) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(WiggleWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wiggle && !oldWidget.wiggle) {
      _controller.repeat(reverse: true);
    } else if (!widget.wiggle && oldWidget.wiggle) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.wiggle) return widget.child;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _animation.value,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
