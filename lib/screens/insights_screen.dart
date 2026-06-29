import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/expense.dart';
import '../theme/app_theme.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final db = DatabaseHelper.instance;
  final fmt = NumberFormat('#,##0.00');

  bool _loading = true;
  double _totalProfit = 0.0;
  double _totalExpenses = 0.0;

  List<double> _presentMonthTrend = [0.0, 0.0, 0.0, 0.0];
  List<double> _lastMonthTrend = [0.0, 0.0, 0.0, 0.0];

  List<Expense> _recentActivity = [];
  bool _showAllActivities = false;

  // Dropdown states
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;

  final List<int> _years = [2023, 2024, 2025, 2026];
  final List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    _initDateAndLoad();
  }

  Future<void> _initDateAndLoad() async {
    // Attempt to locate latest expense to pre-populate mock data nicely
    final all = await db.getAllExpenses();
    if (all.isNotEmpty) {
      // Find the first expense that matches the seeded Nov 2024 or latest date
      final latest = all.first;
      try {
        final parts = latest.date.split('/');
        if (parts.length == 3) {
          _selectedMonth = int.parse(parts[0]);
          _selectedYear = int.parse(parts[2]);
        }
      } catch (_) {}
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // 1. Load Profit vs Expenses stats
    final stats = await db.getMonthlyProfitAndExpenses(_selectedYear, _selectedMonth);
    _totalProfit = stats['profit'] ?? 0.0;
    _totalExpenses = stats['expenses'] ?? 0.0;

    // 2. Load trend data (Weekly cumulative income/profit)
    _presentMonthTrend = await db.getWeeklyProfitTrends(_selectedYear, _selectedMonth);

    // Fetch previous month's trend data
    int prevMonth = _selectedMonth - 1;
    int prevYear = _selectedYear;
    if (prevMonth == 0) {
      prevMonth = 12;
      prevYear = _selectedYear - 1;
    }
    _lastMonthTrend = await db.getWeeklyProfitTrends(prevYear, prevMonth);

    // 3. Load Recent Activity for selected month
    final activities = await db.getExpensesForMonth(_selectedYear, _selectedMonth);
    activities.sort((a, b) {
      DateTime parseDate(String dateStr) {
        try {
          final parts = dateStr.split('/');
          if (parts.length == 3) {
            return DateTime(int.parse(parts[2]), int.parse(parts[0]), int.parse(parts[1]));
          }
        } catch (_) {}
        return DateTime(2000);
      }
      return parseDate(b.date).compareTo(parseDate(a.date));
    });
    _recentActivity = activities;

    setState(() {
      _showAllActivities = false;
      _loading = false;
    });
  }

  IconData _getActivityIcon(String category, String type) {
    if (type == 'income') {
      if (category.toLowerCase() == 'investment') return Icons.account_balance_outlined;
      return Icons.assignment_outlined; // Services, general income
    }

    switch (category.toLowerCase()) {
      case 'rent':
        return Icons.business_outlined;
      case 'payroll':
        return Icons.people_outline;
      case 'utilities':
        return Icons.flash_on_outlined;
      case 'marketing':
        return Icons.campaign_outlined;
      case 'software':
        return Icons.cloud_queue;
      default:
        return Icons.category_outlined;
    }
  }

  Color _getActivityColor(String category, String type) {
    if (type == 'income') {
      if (category.toLowerCase() == 'investment') return Colors.blue.shade800;
      return AppTheme.navy;
    }

    switch (category.toLowerCase()) {
      case 'rent':
        return Colors.amber.shade700;
      case 'software':
        return Colors.grey.shade800;
      case 'marketing':
        return Colors.orange.shade700;
      case 'payroll':
        return Colors.purple.shade700;
      default:
        return Colors.teal.shade700;
    }
  }

  String _formatActivityDate(String dateStr) {
    try {
      final date = DateFormat('MM/dd/yyyy').parse(dateStr);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Insights',
          style: TextStyle(
            color: AppTheme.textDark,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Navy Performance Card ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      decoration: BoxDecoration(
                        color: AppTheme.navy,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.navy.withOpacity(0.2),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PERFORMANCE OVERVIEW',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Profit vs. Expenses',
                            style: TextStyle(
                              color: AppTheme.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'TOTAL PROFIT',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '₱${fmt.format(_totalProfit)}',
                                    style: const TextStyle(
                                      color: AppTheme.yellow,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 32),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'TOTAL EXPENSES',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '₱${fmt.format(_totalExpenses)}',
                                    style: const TextStyle(
                                      color: AppTheme.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Custom Paint Chart
                          SizedBox(
                            height: 140,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _BezierChartPainter(
                                presentTrend: _presentMonthTrend,
                                lastTrend: _lastMonthTrend,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Dropdowns Row ──
                    Row(
                      children: [
                        // Year Dropdown
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'YEAR',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textGrey,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF4EFEB),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: _selectedYear,
                                    isExpanded: true,
                                    icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textGrey),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textDark,
                                    ),
                                    dropdownColor: const Color(0xFFF4EFEB),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _selectedYear = val);
                                        _load();
                                      }
                                    },
                                    items: _years.map((y) {
                                      return DropdownMenuItem(value: y, child: Text('$y'));
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Month Dropdown
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'MONTH',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textGrey,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF4EFEB),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _months[_selectedMonth - 1],
                                    isExpanded: true,
                                    icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textGrey),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textDark,
                                    ),
                                    dropdownColor: const Color(0xFFF4EFEB),
                                    onChanged: (val) {
                                      if (val != null) {
                                        final idx = _months.indexOf(val) + 1;
                                        setState(() => _selectedMonth = idx);
                                        _load();
                                      }
                                    },
                                    items: _months.map((m) {
                                      return DropdownMenuItem(value: m, child: Text(m));
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ── Recent Activity ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Recent Activity',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _showAllActivities = !_showAllActivities;
                            });
                          },
                          child: Text(
                            _showAllActivities ? 'SHOW LESS' : 'VIEW ALL',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.navy,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (_recentActivity.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: AppTheme.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text(
                            'No activities recorded for this period.',
                            style: TextStyle(
                              color: AppTheme.textGrey,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _showAllActivities ? _recentActivity.length : (_recentActivity.length > 5 ? 5 : _recentActivity.length),
                        separatorBuilder: (ctx, idx) => const SizedBox(height: 12),
                        itemBuilder: (ctx, idx) {
                          final item = _recentActivity[idx];
                          final isIncome = item.type == 'income';
                          final color = _getActivityColor(item.category, item.type);

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.01),
                                  blurRadius: 5,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: Row(
                              children: [
                                // Category Icon
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _getActivityIcon(item.category, item.type),
                                    color: AppTheme.white,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                // Title / Date Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textDark,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_formatActivityDate(item.date)} • ${item.category}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Amount & Status
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${isIncome ? '+' : '-'}₱${fmt.format(item.amount)}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isIncome ? AppTheme.yellow : AppTheme.navy,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: item.status == 'completed' ? AppTheme.textGrey : AppTheme.red,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }
}

// ── CUSTOM CHART PAINTER ──

class _BezierChartPainter extends CustomPainter {
  final List<double> presentTrend;
  final List<double> lastTrend;

  _BezierChartPainter({required this.presentTrend, required this.lastTrend});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Pad chart space so labels and lines don't get cut off
    final paddingBottom = 24.0;
    final paddingTop = 12.0;
    final paddingLeft = 10.0;
    final paddingRight = 10.0;

    final chartH = h - paddingTop - paddingBottom;
    final chartW = w - paddingLeft - paddingRight;

    // Find the max value to scale lines
    double maxVal = 1000.0; // minimum scale ceiling
    for (final v in presentTrend) {
      if (v > maxVal) maxVal = v;
    }
    for (final v in lastTrend) {
      if (v > maxVal) maxVal = v;
    }

    // Determine X positions for Week 1, 2, 3, 4
    final xCoords = <double>[];
    for (int i = 0; i < 4; i++) {
      xCoords.add(paddingLeft + (chartW / 3) * i);
    }

    // Function to calculate Y coordinate for a given value
    double getY(double val) {
      final ratio = maxVal == 0 ? 0.0 : (val / maxVal);
      // SQLite starts from top-left, so subtract from bottom of chart area
      return paddingTop + chartH * (1.0 - ratio);
    }

    // Draw weeks text labels
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    final weekLabels = ['*WEEK 1', 'WEEK 2', 'WEEK 3', 'WEEK 4'];
    for (int i = 0; i < 4; i++) {
      textPainter.text = TextSpan(
        text: weekLabels[i],
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(xCoords[i] - textPainter.width / 2, h - 14),
      );
    }

    // 1. Draw Last Month trend (Dashed Grey/White Line)
    if (lastTrend.isNotEmpty) {
      final lastPath = Path();
      lastPath.moveTo(xCoords[0], getY(lastTrend[0]));
      for (int i = 0; i < lastTrend.length - 1; i++) {
        final cx1 = xCoords[i] + (xCoords[i + 1] - xCoords[i]) / 2;
        final cy1 = getY(lastTrend[i]);
        final cx2 = xCoords[i] + (xCoords[i + 1] - xCoords[i]) / 2;
        final cy2 = getY(lastTrend[i + 1]);
        lastPath.cubicTo(cx1, cy1, cx2, cy2, xCoords[i + 1], getY(lastTrend[i + 1]));
      }

      final lastPaint = Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      // Draw path dashed
      canvas.drawPath(_dashPath(lastPath, 4.0, 4.0), lastPaint);
    }

    // 2. Draw Present Month trend (Solid Yellow Line with gradient fill underneath)
    if (presentTrend.isNotEmpty) {
      final presentPath = Path();
      presentPath.moveTo(xCoords[0], getY(presentTrend[0]));
      for (int i = 0; i < presentTrend.length - 1; i++) {
        final cx1 = xCoords[i] + (xCoords[i + 1] - xCoords[i]) / 2;
        final cy1 = getY(presentTrend[i]);
        final cx2 = xCoords[i] + (xCoords[i + 1] - xCoords[i]) / 2;
        final cy2 = getY(presentTrend[i + 1]);
        presentPath.cubicTo(cx1, cy1, cx2, cy2, xCoords[i + 1], getY(presentTrend[i + 1]));
      }

      // Draw Gradient Fill underneath first
      final fillPath = Path.from(presentPath);
      fillPath.lineTo(xCoords[3], paddingTop + chartH); // bottom right of chart
      fillPath.lineTo(xCoords[0], paddingTop + chartH); // bottom left of chart
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          colors: [AppTheme.yellow.withOpacity(0.2), AppTheme.yellow.withOpacity(0.0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTRB(0, paddingTop, w, paddingTop + chartH));

      canvas.drawPath(fillPath, fillPaint);

      // Draw the solid yellow line
      final presentPaint = Paint()
        ..color = AppTheme.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(presentPath, presentPaint);

      // Draw dots at data points
      final dotPaint = Paint()..color = AppTheme.yellow;
      final borderPaint = Paint()
        ..color = AppTheme.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      for (int i = 0; i < presentTrend.length; i++) {
        final offset = Offset(xCoords[i], getY(presentTrend[i]));
        canvas.drawCircle(offset, 4.0, dotPaint);
        canvas.drawCircle(offset, 4.0, borderPaint);
      }
    }
  }

  Path _dashPath(Path source, double dashWidth, double dashSpace) {
    final Path dest = Path();
    for (final ui.PathMetric metric in source.computeMetrics()) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final double len = draw ? dashWidth : dashSpace;
        if (draw) {
          dest.addPath(
            metric.extractPath(distance, (distance + len).clamp(0.0, metric.length)),
            Offset.zero,
          );
        }
        distance += len;
        draw = !draw;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant _BezierChartPainter oldDelegate) {
    return oldDelegate.presentTrend != presentTrend || oldDelegate.lastTrend != lastTrend;
  }
}
