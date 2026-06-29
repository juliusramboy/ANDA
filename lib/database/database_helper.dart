import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import '../models/borrower.dart';
import '../models/payment.dart';
import '../models/expense.dart';
import '../models/saved_stop.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('vault.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);
    return await openDatabase(
      path,
      version: 9,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE borrowers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loanReference TEXT NOT NULL,
        fullName TEXT NOT NULL,
        amountBorrowed REAL NOT NULL,
        interestRate REAL NOT NULL,
        repaymentDate TEXT NOT NULL,
        issueDate TEXT NOT NULL,
        signatureImagePath TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        billingCycle TEXT NOT NULL DEFAULT 'Monthly',
        agreedSetupAmount REAL,
        dismissedWiggleDate TEXT,
        isOneTimeInterest INTEGER NOT NULL DEFAULT 0,
        waivedPenaltyDates TEXT,
        customPenaltyAmounts TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        borrowerId INTEGER NOT NULL,
        amount REAL NOT NULL,
        paymentType TEXT NOT NULL,
        paymentDate TEXT NOT NULL,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'paid',
        FOREIGN KEY (borrowerId) REFERENCES borrowers (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        date TEXT NOT NULL,
        notes TEXT,
        type TEXT NOT NULL DEFAULT 'expense',
        status TEXT NOT NULL DEFAULT 'completed',
        isUrgent INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE saved_stops (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        address TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        positionOrder INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE borrowers ADD COLUMN agreedSetupAmount REAL');
      } catch (e) {
        // Handle duplicate column exception gracefully if it already exists
        debugPrint('Database upgrade warning: $e');
      }
    }
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE borrowers ADD COLUMN dismissedWiggleDate TEXT');
      } catch (e) {
        debugPrint('Database upgrade warning: $e');
      }
    }
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE borrowers ADD COLUMN isOneTimeInterest INTEGER DEFAULT 0');
      } catch (e) {
        debugPrint('Database upgrade warning: $e');
      }
    }
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE borrowers ADD COLUMN waivedPenaltyDates TEXT');
      } catch (e) {
        debugPrint('Database upgrade warning: $e');
      }
    }
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE borrowers ADD COLUMN customPenaltyAmounts TEXT');
      } catch (e) {
        debugPrint('Database upgrade warning: $e');
      }
    }
    if (oldVersion < 7) {
      try {
        await db.execute('''
          CREATE TABLE expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            amount REAL NOT NULL,
            category TEXT NOT NULL,
            date TEXT NOT NULL,
            notes TEXT,
            type TEXT NOT NULL DEFAULT 'expense',
            status TEXT NOT NULL DEFAULT 'completed',
            isUrgent INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (e) {
        debugPrint('Database upgrade warning version 7: $e');
      }
    }
    if (oldVersion < 8) {
      try {
        await db.execute('DELETE FROM expenses');
      } catch (e) {
        debugPrint('Database upgrade warning version 8: $e');
      }
    }
    if (oldVersion < 9) {
      try {
        await db.execute('''
          CREATE TABLE saved_stops (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            address TEXT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            positionOrder INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (e) {
        debugPrint('Database upgrade warning version 9: $e');
      }
    }
  }

  // ─── BORROWER CRUD ───────────────────────────────────────────

  Future<int> insertBorrower(Borrower borrower) async {
    final db = await database;
    return await db.insert('borrowers', borrower.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Borrower>> getAllBorrowers() async {
    final db = await database;
    final maps = await db.query('borrowers', orderBy: 'id DESC');
    return maps.map((m) => Borrower.fromMap(m)).toList();
  }

  Future<Borrower?> getBorrowerById(int id) async {
    final db = await database;
    final maps =
        await db.query('borrowers', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Borrower.fromMap(maps.first);
  }

  Future<int> updateBorrower(Borrower borrower) async {
    final db = await database;
    return await db.update('borrowers', borrower.toMap(),
        where: 'id = ?', whereArgs: [borrower.id]);
  }

  Future<int> deleteBorrower(int id) async {
    final db = await database;
    return await db
        .delete('borrowers', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getTotalBorrowers() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as count FROM borrowers');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getActiveBorrowers() async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT COUNT(*) as count FROM borrowers WHERE status = 'active'");
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getFullyPaidCount() async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT COUNT(*) as count FROM borrowers WHERE status = 'fully_paid'");
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Borrower>> getFullyPaidBorrowers() async {
    final db = await database;
    final maps = await db.query('borrowers',
        where: "status = ?",
        whereArgs: ['fully_paid'],
        orderBy: 'id DESC');
    return maps.map((m) => Borrower.fromMap(m)).toList();
  }

  Future<String> generateLoanReference() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as count FROM borrowers');
    final count = (Sqflite.firstIntValue(result) ?? 0) + 1;
    final year = DateTime.now().year;
    return '#LN-$year-${count.toString().padLeft(3, '0')}';
  }

  // ─── PAYMENT CRUD ────────────────────────────────────────────

  Future<int> insertPayment(Payment payment) async {
    final db = await database;
    final id = await db.insert('payments', payment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await updateBorrowerStatusIfNeeded(payment.borrowerId);
    return id;
  }

  Future<List<Payment>> getPaymentsByBorrower(int borrowerId) async {
    final db = await database;
    final maps = await db.query('payments',
        where: 'borrowerId = ?',
        whereArgs: [borrowerId],
        orderBy: 'paymentDate DESC');
    return maps.map((m) => Payment.fromMap(m)).toList();
  }

  Future<double> getTotalPaidByBorrower(int borrowerId) async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT SUM(amount) as total FROM payments WHERE borrowerId = ? AND status = 'paid'",
        [borrowerId]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<int> getPaymentCountByBorrower(int borrowerId) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM payments WHERE borrowerId = ?',
        [borrowerId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> updatePayment(Payment payment) async {
    final db = await database;
    final res = await db.update('payments', payment.toMap(),
        where: 'id = ?', whereArgs: [payment.id]);
    await updateBorrowerStatusIfNeeded(payment.borrowerId);
    return res;
  }

  Future<int> deletePayment(int id) async {
    final db = await database;
    final maps = await db.query('payments', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      final payment = Payment.fromMap(maps.first);
      final res = await db.delete('payments', where: 'id = ?', whereArgs: [id]);
      await updateBorrowerStatusIfNeeded(payment.borrowerId);
      return res;
    }
    return 0;
  }

  Future<void> updateBorrowerStatusIfNeeded(int borrowerId) async {
    final db = await database;
    final bMap = await db.query('borrowers', where: 'id = ?', whereArgs: [borrowerId]);
    if (bMap.isEmpty) return;
    final borrower = Borrower.fromMap(bMap.first);
    
    final payments = await getPaymentsByBorrower(borrowerId);
    final totalPaid = payments
        .where((p) => p.status == 'paid')
        .fold<double>(0.0, (sum, p) => sum + p.amount);
        
    final maturityBalance = borrower.calculateMaturityBalance(payments);
    
    String newStatus = borrower.status;
    if (totalPaid >= maturityBalance) {
      newStatus = 'fully_paid';
    } else {
      if (borrower.status == 'fully_paid') {
        newStatus = 'active';
      }
    }
    
    if (newStatus != borrower.status) {
      await db.update(
        'borrowers',
        {'status': newStatus},
        where: 'id = ?',
        whereArgs: [borrowerId],
      );
    }
  }

  // ─── DASHBOARD STATS ─────────────────────────────────────────

  DateTime _parsePaymentDate(String dateStr) {
    try {
      return DateFormat('MM/dd/yyyy').parse(dateStr.trim());
    } catch (_) {
      try {
        return DateTime.parse(dateStr.trim());
      } catch (_) {
        return DateTime(2000);
      }
    }
  }

  Future<double> getTotalCollected() async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT SUM(amount) as total FROM payments WHERE status = 'paid'");
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getThisMonthCollected() async {
    final db = await database;
    final now = DateTime.now();
    final monthStr = now.month.toString().padLeft(2, '0');
    final yearStr = now.year.toString();
    final monthLike = '$monthStr/%/$yearStr';

    // 1. Profit collected this month: Interest and Late Fee payments
    final profitResult = await db.rawQuery(
        "SELECT SUM(amount) as total FROM payments WHERE status = 'paid' AND paymentType IN ('Interest', 'Late Fee') AND paymentDate LIKE ?",
        [monthLike]);
    double profitThisMonth = (profitResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // 2. Principal collected this month from borrowers who reached fully_paid status in this month
    final borrowers = await getAllBorrowers();
    double principalThisMonth = 0.0;

    for (final b in borrowers) {
      if (b.status == 'fully_paid') {
        final payments = await getPaymentsByBorrower(b.id!);
        if (payments.isNotEmpty) {
          // Sort payments by date to find the last payment date
          final sortedPayments = List<Payment>.from(payments);
          sortedPayments.sort((a, b) {
            final dateA = _parsePaymentDate(a.paymentDate);
            final dateB = _parsePaymentDate(b.paymentDate);
            return dateA.compareTo(dateB);
          });
          final lastPayment = sortedPayments.last;
          final lastPaymentDate = _parsePaymentDate(lastPayment.paymentDate);
          if (lastPaymentDate.month == now.month && lastPaymentDate.year == now.year) {
            // This borrower was fully paid in this month!
            // Add all principal payments collected from this borrower in this month
            final thisMonthPrincipal = payments
                .where((p) => p.paymentType == 'Loan Principal' && p.status == 'paid')
                .where((p) {
                  final pDate = _parsePaymentDate(p.paymentDate);
                  return pDate.month == now.month && pDate.year == now.year;
                })
                .fold<double>(0.0, (sum, p) => sum + p.amount);
            principalThisMonth += thisMonthPrincipal;
          }
        }
      }
    }

    return profitThisMonth + principalThisMonth;
  }

  Future<double> getTotalLoanValue() async {
    final db = await database;
    final result = await db
        .rawQuery('SELECT SUM(amountBorrowed) as total FROM borrowers');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTotalRemainingPrincipal() async {
    final db = await database;
    final tvResult = await db.rawQuery('SELECT SUM(amountBorrowed) as total FROM borrowers');
    final totalValue = (tvResult.first['total'] as num?)?.toDouble() ?? 0.0;
    
    final paidResult = await db.rawQuery(
      "SELECT SUM(amount) as total FROM payments WHERE paymentType = 'Loan Principal' AND status = 'paid'"
    );
    final totalPrincipalPaid = (paidResult.first['total'] as num?)?.toDouble() ?? 0.0;
    
    return totalValue - totalPrincipalPaid;
  }

  Future<double> getTotalYield() async {
    final db = await database;
    final paymentsResult = await db.rawQuery(
      "SELECT SUM(amount) as total FROM payments WHERE status = 'paid' AND paymentType IN ('Interest', 'Late Fee')"
    );
    double totalPaymentsInterest = (paymentsResult.first['total'] as num?)?.toDouble() ?? 0.0;
    
    double totalIncome = 0.0;
    try {
      final result = await db.rawQuery("SELECT SUM(amount) as total FROM expenses WHERE type = 'income'");
      totalIncome = (result.first['total'] as num?)?.toDouble() ?? 0.0;
    } catch (_) {}
    
    return totalPaymentsInterest + totalIncome;
  }

  Future<List<Borrower>> getUpcomingDueBorrowers() async {
    final db = await database;
    final maps = await db.query('borrowers',
        where: "status = 'active'", orderBy: 'repaymentDate ASC', limit: 3);
    return maps.map((m) => Borrower.fromMap(m)).toList();
  }

  Future<int> getDueThisMonthCount() async {
    final db = await database;
    final all = await db.query('borrowers', where: "status = 'active'");
    final now = DateTime.now();
    int count = 0;
    for (final map in all) {
      final dateStr = map['repaymentDate'] as String?;
      if (dateStr != null) {
        try {
          final parts = dateStr.split('/');
          if (parts.length == 3) {
            final month = int.parse(parts[0]);
            final year = int.parse(parts[2]);
            if (month == now.month && year == now.year) {
              count++;
            }
          }
        } catch (_) {}
      }
    }
    return count;
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<String> getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'vault.db');
  }

  Future<bool> importDatabase(String backupPath) async {
    try {
      // Validate schema first
      final testDb = await openDatabase(backupPath);
      // Try to query required tables to check schema
      await testDb.rawQuery('SELECT count(*) FROM borrowers');
      await testDb.rawQuery('SELECT count(*) FROM payments');
      await testDb.close();

      // Close current connection
      await close();

      // Overwrite the database file
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'vault.db');
      final file = File(backupPath);
      await file.copy(path);

      // Reopen database
      _database = await _initDB('vault.db');
      return true;
    } catch (e) {
      debugPrint('Error importing database: $e');
      return false;
    }
  }

  // ─── EXPENSES CRUD ───────────────────────────────────────────

  Future<int> insertExpense(Expense expense) async {
    final db = await database;
    return await db.insert('expenses', expense.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateExpense(Expense expense) async {
    final db = await database;
    return await db.update('expenses', expense.toMap(),
        where: 'id = ?', whereArgs: [expense.id]);
  }

  Future<List<Expense>> getAllExpenses() async {
    final db = await database;
    final maps = await db.query('expenses', orderBy: 'date DESC, id DESC');
    return maps.map((m) => Expense.fromMap(m)).toList();
  }

  Future<List<Expense>> getExpensesForMonth(int year, int month) async {
    final db = await database;
    final monthStr = month.toString().padLeft(2, '0');
    final yearStr = year.toString();
    final maps = await db.query(
      'expenses',
      where: "date LIKE ?",
      whereArgs: ['$monthStr/%/$yearStr'],
      orderBy: 'date DESC, id DESC',
    );
    return maps.map((m) => Expense.fromMap(m)).toList();
  }

  Future<int> deleteExpense(int id) async {
    final db = await database;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, double>> getMonthlyProfitAndExpenses(int year, int month) async {
    final db = await database;
    final monthStr = month.toString().padLeft(2, '0');
    final yearStr = year.toString();
    final monthLike = '$monthStr/%/$yearStr';

    // 1. Get loan payment profit (Interest and Late Fees paid)
    final paymentsResult = await db.rawQuery(
        "SELECT SUM(amount) as total FROM payments WHERE status = 'paid' AND paymentType IN ('Interest', 'Late Fee') AND paymentDate LIKE ?",
        [monthLike]);
    final loanProfit = (paymentsResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // 2. Get other income from expenses table
    final incomeResult = await db.rawQuery(
        "SELECT SUM(amount) as total FROM expenses WHERE date LIKE ? AND type = 'income'",
        [monthLike]);
    final otherIncome = (incomeResult.first['total'] as num?)?.toDouble() ?? 0.0;

    final profit = loanProfit + otherIncome;

    // 3. Get expenses
    final expenseResult = await db.rawQuery(
        "SELECT SUM(amount) as total FROM expenses WHERE date LIKE ? AND type = 'expense'",
        [monthLike]);
    final expenses = (expenseResult.first['total'] as num?)?.toDouble() ?? 0.0;

    return {
      'profit': profit,
      'expenses': expenses,
    };
  }

  Future<List<double>> getWeeklyProfitTrends(int year, int month) async {
    final db = await database;
    final monthStr = month.toString().padLeft(2, '0');
    final yearStr = year.toString();
    final monthLike = '$monthStr/%/$yearStr';

    final weeklySums = [0.0, 0.0, 0.0, 0.0];

    // Get loan payments profit (Interest and Late Fee payments)
    final loanPayments = await db.rawQuery(
        "SELECT amount, paymentDate FROM payments WHERE status = 'paid' AND paymentType IN ('Interest', 'Late Fee') AND paymentDate LIKE ?",
        [monthLike]);
    for (final p in loanPayments) {
      final dateStr = p['paymentDate'] as String;
      final amount = (p['amount'] as num).toDouble();
      try {
        final parts = dateStr.split('/');
        final day = int.parse(parts[1]);
        if (day <= 7) {
          weeklySums[0] += amount;
        } else if (day <= 14) {
          weeklySums[1] += amount;
        } else if (day <= 21) {
          weeklySums[2] += amount;
        } else {
          weeklySums[3] += amount;
        }
      } catch (_) {}
    }

    // Get expenses income
    final otherIncomes = await db.rawQuery(
        "SELECT amount, date FROM expenses WHERE type = 'income' AND date LIKE ?",
        [monthLike]);
    for (final inc in otherIncomes) {
      final dateStr = inc['date'] as String;
      final amount = (inc['amount'] as num).toDouble();
      try {
        final parts = dateStr.split('/');
        final day = int.parse(parts[1]);
        if (day <= 7) {
          weeklySums[0] += amount;
        } else if (day <= 14) {
          weeklySums[1] += amount;
        } else if (day <= 21) {
          weeklySums[2] += amount;
        } else {
          weeklySums[3] += amount;
        }
      } catch (_) {}
    }

    final cumulative = <double>[];
    double sum = 0.0;
    for (final w in weeklySums) {
      sum += w;
      cumulative.add(sum);
    }
    return cumulative;
  }

  // ─── SAVED STOPS CRUD ─────────────────────────────────────────

  Future<int> insertSavedStop(SavedStop stop) async {
    final db = await database;
    return await db.insert('saved_stops', stop.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SavedStop>> getAllSavedStops() async {
    final db = await database;
    final maps = await db.query('saved_stops', orderBy: 'positionOrder ASC, id ASC');
    return maps.map((m) => SavedStop.fromMap(m)).toList();
  }

  Future<int> deleteSavedStop(int id) async {
    final db = await database;
    return await db.delete('saved_stops', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateSavedStopsOrder(List<SavedStop> stops) async {
    final db = await database;
    final batch = db.batch();
    for (int i = 0; i < stops.length; i++) {
      batch.update(
        'saved_stops',
        {'positionOrder': i},
        where: 'id = ?',
        whereArgs: [stops[i].id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> clearAllSavedStops() async {
    final db = await database;
    await db.delete('saved_stops');
  }
}
