import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../database/database_helper.dart';

class ChatMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        role: json['role'] ?? 'assistant',
        content: json['content'] ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
            : DateTime.now(),
      );
}

class AiChatService {
  static final AiChatService instance = AiChatService._init();
  AiChatService._init() {
    loadPinnedChat();
  }

  static const String groqBaseUrl = 'https://api.groq.com/openai';
  static const String groqModel = 'openai/gpt-oss-120b';

  static const List<String> groqApiKeys = [
    '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',
    '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',
  ];

  final List<ChatMessage> _messages = [];
  bool isPinned = false;
  bool isGenerating = false;
  HttpClientRequest? _activeRequest;

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  Future<File> get _pinnedFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pinned_chat.json');
  }

  Future<void> loadPinnedChat() async {
    try {
      final file = await _pinnedFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _messages.clear();
        for (final item in jsonList) {
          _messages.add(ChatMessage.fromJson(item));
        }
        isPinned = true;
      }
    } catch (_) {}
  }

  Future<void> _persistIfPinned() async {
    try {
      final file = await _pinnedFile;
      if (isPinned && _messages.isNotEmpty) {
        final data = jsonEncode(_messages.map((m) => m.toJson()).toList());
        await file.writeAsString(data);
      } else {
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {}
  }

  String? get currentTopic {
    for (final msg in _messages) {
      if (msg.role == 'user') {
        return msg.content;
      }
    }
    return null;
  }

  void togglePin() {
    isPinned = !isPinned;
    _persistIfPinned();
  }

  void clearIfUnpinned() {
    if (!isPinned) {
      _messages.clear();
      _persistIfPinned();
    }
  }

  void startNewChat() {
    _messages.clear();
    isPinned = false;
    _persistIfPinned();
  }

  void stopGeneration() {
    if (isGenerating && _activeRequest != null) {
      try {
        _activeRequest?.abort();
      } catch (_) {}
      _activeRequest = null;
      isGenerating = false;
    }
  }

  /// Builds a comprehensive, read-only snapshot of the local database for the AI
  Future<String> _buildDatabaseContext() async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final dateFmt = DateFormat('MMMM d, yyyy (EEEE)');
    final numFmt = NumberFormat('#,##0.00');

    final buffer = StringBuffer();
    buffer.writeln('=== CURRENT APP DATE: ${dateFmt.format(now)} ===');
    buffer.writeln('APP: ANDA Vault Loan Management & Personal Ledger\n');

    try {
      final totalProfit = await db.getTotalYield();
      final totalRemainingPrincipal = await db.getTotalRemainingPrincipal();
      final activeBorrowersCount = await db.getActiveBorrowers();
      final dueThisMonthCount = await db.getDueThisMonthCount();

      buffer.writeln('--- FINANCIAL SUMMARY ---');
      buffer.writeln('Total Profit / Yield Collected: Php ${numFmt.format(totalProfit)}');
      buffer.writeln('Total Remaining Principal Outstanding: Php ${numFmt.format(totalRemainingPrincipal)}');
      buffer.writeln('Active Borrowers Count: $activeBorrowersCount');
      buffer.writeln('Due This Month Count: $dueThisMonthCount\n');

      final allBorrowers = await db.getAllBorrowers();
      buffer.writeln('--- BORROWERS LIST (${allBorrowers.length} total) ---');

      for (final b in allBorrowers) {
        final payments = await db.getPaymentsByBorrower(b.id!);
        final totalPaid = payments
            .where((p) => p.status == 'paid')
            .fold<double>(0.0, (sum, p) => sum + p.amount);
        final maturityBalance = b.calculateMaturityBalance(payments);
        final remainingBal = maturityBalance - totalPaid;

        // Parse repayment date to calculate days difference
        String dueInfo = b.repaymentDate;
        try {
          final parts = b.repaymentDate.split('/');
          if (parts.length == 3) {
            final dueMonth = int.parse(parts[0]);
            final dueDay = int.parse(parts[1]);
            final dueYear = int.parse(parts[2]);
            final dueDate = DateTime(dueYear, dueMonth, dueDay);
            final diffDays = dueDate.difference(DateTime(now.year, now.month, now.day)).inDays;
            if (diffDays == 0) {
              dueInfo += ' (DUE TODAY!)';
            } else if (diffDays > 0) {
              dueInfo += ' (Due in $diffDays days)';
            } else {
              dueInfo += ' (OVERDUE by ${-diffDays} days!)';
            }
          }
        } catch (_) {}

        buffer.writeln('- Name: ${b.fullName}');
        buffer.writeln('  Loan Ref: ${b.loanReference}');
        buffer.writeln('  Status: ${b.status.toUpperCase()}');
        buffer.writeln('  Principal Borrowed: Php ${numFmt.format(b.amountBorrowed)}');
        buffer.writeln('  Interest Rate: ${b.interestRate}% (${b.billingCycle})');
        buffer.writeln('  Repayment Date: $dueInfo');
        buffer.writeln('  Issue Date: ${b.issueDate}');
        buffer.writeln('  Total Paid So Far: Php ${numFmt.format(totalPaid)}');
        buffer.writeln('  Remaining Balance to Settle: Php ${numFmt.format(remainingBal > 0 ? remainingBal : 0)}');
        buffer.writeln('  Payments Count: ${payments.length}');
        if (payments.isNotEmpty) {
          final recent = payments.take(3).map((p) => '${p.paymentDate}: Php ${numFmt.format(p.amount)} (${p.paymentType})').join(', ');
          buffer.writeln('  Recent Payments: $recent');
        }
        buffer.writeln('');
      }

      // Recent Expenses
      final expenses = await db.getAllExpenses();
      if (expenses.isNotEmpty) {
        buffer.writeln('--- RECENT EXPENSES / INCOME ---');
        for (final exp in expenses.take(5)) {
          buffer.writeln('- ${exp.date}: ${exp.name} - Php ${numFmt.format(exp.amount)} [${exp.category}] (${exp.type})');
        }
      }
    } catch (e) {
      buffer.writeln('Error reading some database tables: $e');
    }

    return buffer.toString();
  }

  /// Sends user message to Groq API with failover between API keys
  Future<String> sendMessage(String userMessage) async {
    final userMsgObj = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: userMessage,
    );
    _messages.add(userMsgObj);

    isGenerating = true;

    try {
      final dbContext = await _buildDatabaseContext();

      final systemPrompt = '''
You are ANDA, a helpful, intelligent, and human-like AI lending assistant embedded in the ANDA Vault Loan Management & Personal Ledger app.

CONVERSATION & MEMORY GUIDELINES:
- You maintain active memory of this ongoing conversation. Always preserve context from earlier questions and answers (e.g. if the user refers to "him", "her", "that borrower", or asks follow-up questions like "what about the other one?" or "summarize our chat", you remember what was discussed previously like a real human assistant).
- Communicate naturally, politely, and warmly, acting as an expert, supportive personal lending partner.
- Answer follow-up questions intuitively, connecting the dots between previous discussion points and the user's loan data.

STRICT OUTPUT FORMATTING RULES:
- DO NOT USE MARKDOWN ASTERISKS (** or *). NEVER write **bold** or *bullets*.
- DO NOT USE MARKDOWN HASHTAGS (### or ##).
- If the user asks for a list, ALWAYS format as clean numbered points:
  1. First item or borrower name - ₱Amount (Details)
  2. Second item or borrower name - ₱Amount (Details)
- If the user asks for structured borrower info or table-like data, format in clean clear column rows:
  Borrower: Full Name
  Amount: ₱0,000.00
  Due Date: Month Day, Year
  Status: Active / Overdue / Paid
- Format all currency figures cleanly in Philippine Pesos (₱ or Php #,##0.00).
- When discussing due dates, clearly specify whether an account is overdue, due today, or due in upcoming days.

IMPORTANT RESTRICTION:
- You have READ-ONLY access to the current database state provided below.
- You CANNOT modify, update, insert, or delete any information in the database.
- Use the provided database information to accurately answer questions regarding borrowers, payment logs, overdue accounts, interest breakdown, profit summaries, and route collection stops.

=== LIVE DATABASE CONTEXT (READ-ONLY) ===
$dbContext
''';

      final List<Map<String, String>> apiMessages = [
        {'role': 'system', 'content': systemPrompt},
      ];

      // Add conversation history with active memory context
      final recentHistory = _messages.length > 24
          ? _messages.sublist(_messages.length - 24)
          : _messages;

      for (final msg in recentHistory) {
        apiMessages.add({
          'role': msg.role,
          'content': msg.content,
        });
      }

      String? responseText;
      Exception? lastException;

      // Try API keys with automatic failover
      for (int i = 0; i < groqApiKeys.length; i++) {
        final key = groqApiKeys[i];
        try {
          responseText = await _callGroqChatCompletions(key, apiMessages);
          if (responseText != null && responseText.isNotEmpty) {
            break; // Success!
          }
        } catch (e) {
          debugPrint('Groq API Key $i failed: $e. Trying fallback key if available.');
          lastException = e is Exception ? e : Exception(e.toString());
        }
      }

      isGenerating = false;

      if (responseText != null && responseText.isNotEmpty) {
        final assistantMsgObj = ChatMessage(
          id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
          role: 'assistant',
          content: responseText.trim(),
        );
        _messages.add(assistantMsgObj);
        _persistIfPinned();
        return responseText.trim();
      } else {
        final errorMsg = lastException?.toString() ?? 'No response received from AI service.';
        final fallbackMsg = ChatMessage(
          id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
          role: 'assistant',
          content: 'Sorry, I could not complete your request. Please check your internet connection or try again.\n\nDetails: $errorMsg',
        );
        _messages.add(fallbackMsg);
        _persistIfPinned();
        return fallbackMsg.content;
      }
    } catch (e) {
      isGenerating = false;
      final errorMsg = 'An unexpected error occurred: $e';
      final fallbackMsg = ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: 'assistant',
        content: errorMsg,
      );
      _messages.add(fallbackMsg);
      _persistIfPinned();
      return errorMsg;
    }
  }

  Future<String?> _callGroqChatCompletions(
    String apiKey,
    List<Map<String, String>> messages,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    try {
      final uri = Uri.parse('$groqBaseUrl/v1/chat/completions');
      final request = await client.postUrl(uri);
      _activeRequest = request;

      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $apiKey');

      final requestBody = jsonEncode({
        'model': groqModel,
        'messages': messages,
        'temperature': 0.6,
        'max_tokens': 1024,
      });

      request.write(requestBody);
      final response = await request.close();

      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(responseBody);
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final message = choices.first['message'];
          if (message != null && message['content'] != null) {
            return message['content'].toString();
          }
        }
        return null;
      } else {
        throw Exception('Groq API Error (${response.statusCode}): $responseBody');
      }
    } finally {
      client.close();
      _activeRequest = null;
    }
  }
}
