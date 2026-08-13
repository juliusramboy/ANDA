import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/borrower.dart';
import '../models/payment.dart';

class PdfService {
  static String _toTagalogDate(String dateStr) {
    try {
      DateTime dt;
      if (dateStr.contains('/')) {
        dt = DateFormat('MM/dd/yyyy').parse(dateStr);
      } else {
        dt = DateFormat('MMMM d, yyyy').parse(dateStr);
      }
      final months = [
        'Enero', 'Pebrero', 'Marso', 'Abril', 'Mayo', 'Hunyo',
        'Hulyo', 'Agosto', 'Setyembre', 'Oktubre', 'Nobyembre', 'Disyembre'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      try {
        DateTime dt = DateFormat('MMM d, yyyy').parse(dateStr);
        final months = [
          'Enero', 'Pebrero', 'Marso', 'Abril', 'Mayo', 'Hunyo',
          'Hulyo', 'Agosto', 'Setyembre', 'Oktubre', 'Nobyembre', 'Disyembre'
        ];
        return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
      } catch (_) {
        String result = dateStr;
        final englishMonths = [
          'January', 'February', 'March', 'April', 'May', 'June',
          'July', 'August', 'September', 'October', 'November', 'December'
        ];
        final shortMonths = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        final tagalogMonths = [
          'Enero', 'Pebrero', 'Marso', 'Abril', 'Mayo', 'Hunyo',
          'Hulyo', 'Agosto', 'Setyembre', 'Oktubre', 'Nobyembre', 'Disyembre'
        ];
        for (int i = 0; i < 12; i++) {
          result = result.replaceAll(englishMonths[i], tagalogMonths[i]);
          result = result.replaceAll(shortMonths[i], tagalogMonths[i]);
        }
        return result;
      }
    }
  }

  static pw.Widget _buildHeader({
    required String logoText,
    required String taglineText,
    required String titleText,
    required String refNo,
    required PdfColor orangeColor,
    required PdfColor greyColor,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              logoText,
              style: pw.TextStyle(
                color: orangeColor,
                fontSize: 26,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              taglineText,
              style: pw.TextStyle(
                color: greyColor,
                fontSize: 8,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              titleText,
              style: pw.TextStyle(
                color: PdfColors.black,
                fontSize: 12.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.RichText(
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 9.5),
                children: [
                  pw.TextSpan(text: 'Ref No: ', style: pw.TextStyle(color: greyColor)),
                  pw.TextSpan(
                    text: refNo,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: orangeColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildSectionHeader(String title, PdfColor barColor) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 3.5,
          height: 12,
          decoration: pw.BoxDecoration(
            color: barColor,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1)),
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildContractTableCell(
    String text,
    PdfColor textColor,
    PdfColor bgColor, {
    bool isLabel = false,
    bool isValue = false,
  }) {
    return pw.Container(
      color: bgColor,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      alignment: pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: textColor,
          fontSize: 8.5,
          fontWeight: (isLabel || isValue) ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _buildEnglishTable({
    required String borrowerName,
    required String issueDate,
    required String principalAmount,
    required String interestRate,
    required String repaymentDate,
    required String maturityBalance,
    String? agreedAmount,
    required PdfColor lightYellowBg,
    required PdfColor borderColor,
    required PdfColor labelColor,
    required PdfColor orangeColor,
    required PdfColor greenColor,
  }) {
    final hasAgreed = agreedAmount != null;

    return pw.Table(
      border: pw.TableBorder.all(color: borderColor, width: 0.8),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(1.3),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.3),
      },
      children: [
        // Row 1
        pw.TableRow(
          children: [
            _buildContractTableCell('BORROWER NAME', labelColor, lightYellowBg, isLabel: true),
            _buildContractTableCell(borrowerName, PdfColors.black, PdfColors.white, isValue: true),
            _buildContractTableCell('ISSUE DATE', labelColor, lightYellowBg, isLabel: true),
            _buildContractTableCell(issueDate, PdfColors.black, PdfColors.white, isValue: true),
          ],
        ),
        // Row 2
        pw.TableRow(
          children: [
            _buildContractTableCell('PRINCIPAL AMOUNT', labelColor, lightYellowBg, isLabel: true),
            _buildContractTableCell(principalAmount, orangeColor, PdfColors.white, isValue: true),
            _buildContractTableCell('INTEREST RATE', labelColor, lightYellowBg, isLabel: true),
            _buildContractTableCell(interestRate, PdfColors.black, PdfColors.white, isValue: true),
          ],
        ),
        // Row 3
        pw.TableRow(
          children: [
            if (hasAgreed) ...[
              _buildContractTableCell('AGREED SETUP AMOUNT', labelColor, lightYellowBg, isLabel: true),
              _buildContractTableCell(agreedAmount, greenColor, PdfColors.white, isValue: true),
              _buildContractTableCell('REPAYMENT DATE', labelColor, lightYellowBg, isLabel: true),
              _buildContractTableCell(repaymentDate, PdfColors.black, PdfColors.white, isValue: true),
            ] else ...[
              _buildContractTableCell('REPAYMENT DATE', labelColor, lightYellowBg, isLabel: true),
              _buildContractTableCell(repaymentDate, PdfColors.black, PdfColors.white, isValue: true),
              _buildContractTableCell('MATURITY BALANCE', labelColor, lightYellowBg, isLabel: true),
              _buildContractTableCell(maturityBalance, PdfColors.black, PdfColors.white, isValue: true),
            ]
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTagalogTable({
    required String borrowerName,
    required String issueDate,
    required String principalAmount,
    required String interestRate,
    required String repaymentDate,
    required String maturityBalance,
    String? agreedAmount,
    required PdfColor lightYellowBg,
    required PdfColor borderColor,
    required PdfColor labelColor,
    required PdfColor orangeColor,
    required PdfColor greenColor,
  }) {
    final hasAgreed = agreedAmount != null;

    return pw.Table(
      border: pw.TableBorder.all(color: borderColor, width: 0.8),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(1.3),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.3),
      },
      children: [
        // Row 1
        pw.TableRow(
          children: [
            _buildContractTableCell('PANGALAN NG HUMIRAM', labelColor, lightYellowBg, isLabel: true),
            _buildContractTableCell(borrowerName, PdfColors.black, PdfColors.white, isValue: true),
            _buildContractTableCell('PETSA NG PAGKUHA', labelColor, lightYellowBg, isLabel: true),
            _buildContractTableCell(issueDate, PdfColors.black, PdfColors.white, isValue: true),
          ],
        ),
        // Row 2
        pw.TableRow(
          children: [
            _buildContractTableCell('HALAGA NG INUTANG', labelColor, lightYellowBg, isLabel: true),
            _buildContractTableCell(principalAmount, orangeColor, PdfColors.white, isValue: true),
            _buildContractTableCell('INTERES KADA BUWAN', labelColor, lightYellowBg, isLabel: true),
            _buildContractTableCell(interestRate, PdfColors.black, PdfColors.white, isValue: true),
          ],
        ),
        // Row 3
        pw.TableRow(
          children: [
            if (hasAgreed) ...[
              _buildContractTableCell('PINAGKASUNDUANG HULOG', labelColor, lightYellowBg, isLabel: true),
              _buildContractTableCell(agreedAmount, greenColor, PdfColors.white, isValue: true),
              _buildContractTableCell('PETSA NG KABAYARAN', labelColor, lightYellowBg, isLabel: true),
              _buildContractTableCell(repaymentDate, PdfColors.black, PdfColors.white, isValue: true),
            ] else ...[
              _buildContractTableCell('PETSA NG KABAYARAN', labelColor, lightYellowBg, isLabel: true),
              _buildContractTableCell(repaymentDate, PdfColors.black, PdfColors.white, isValue: true),
              _buildContractTableCell('KABUUANG BABAYARAN', labelColor, lightYellowBg, isLabel: true),
              _buildContractTableCell(maturityBalance, PdfColors.black, PdfColors.white, isValue: true),
            ]
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildSignatureBlock({
    required String borrowerName,
    required String roleLabel,
    pw.Widget? signatureWidget,
    required PdfColor borderColor,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 200,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                height: 50,
                width: 140,
                alignment: pw.Alignment.center,
                decoration: signatureWidget == null
                    ? pw.BoxDecoration(
                        border: pw.Border.all(
                          color: PdfColor.fromHex('#E5E7EB'),
                          width: 1,
                          style: pw.BorderStyle.dashed,
                        ),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      )
                    : null,
                child: signatureWidget ??
                    pw.Text(
                      '[ Uploaded Signature Image ]',
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: PdfColor.fromHex('#9CA3AF'),
                      ),
                    ),
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                height: 1,
                color: PdfColors.black,
                width: 180,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                borrowerName,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
              ),
              pw.Text(
                roleLabel,
                style: pw.TextStyle(
                  fontSize: 8,
                  color: PdfColor.fromHex('#6B7280'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Uint8List? parseSignatureBytes(String? input) {
    if (input == null || input.trim().isEmpty) return null;
    String cleanInput = input.trim();
    if (cleanInput.contains(',')) {
      cleanInput = cleanInput.split(',').last;
    }
    try {
      final decoded = base64Decode(cleanInput);
      if (decoded.isNotEmpty) return decoded;
    } catch (_) {}

    try {
      final file = File(input);
      if (file.existsSync()) {
        return file.readAsBytesSync();
      }
    } catch (_) {}

    return null;
  }

  static Future<pw.Document> generateContract(Borrower borrower) async {
    final pdf = pw.Document();

    // Load fonts to support Unicode symbols like ₱
    final baseFont = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    final italicFont = await PdfGoogleFonts.robotoItalic();

    final myTheme = pw.ThemeData.withFont(
      base: baseFont,
      bold: boldFont,
      italic: italicFont,
    );

    // Format currency amount and interest rate
    final fmt = NumberFormat('#,##0.00');
    const peso = 'Php ';
    final formattedAmount = '$peso${fmt.format(borrower.amountBorrowed)}';
    
    final String formattedRate;
    if (borrower.isOneTimeInterest) {
      formattedRate = '$peso${fmt.format(borrower.interestRate)}';
    } else {
      formattedRate = '${borrower.interestRate.toInt()}%';
    }

    // Calculate Maturity Balance (Principal + Interest)
    final maturityBalanceVal = borrower.calculateMaturityBalance([]);
    final formattedMaturity = '$peso${fmt.format(maturityBalanceVal)}';

    // Optional agreed setup amount
    final hasAgreedAmount = borrower.agreedSetupAmount != null;
    final formattedAgreed = hasAgreedAmount
        ? '$peso${fmt.format(borrower.agreedSetupAmount!)}'
        : '';

    // Resolve signature image if available
    pw.Widget? signatureWidget;
    final sigBytes = parseSignatureBytes(borrower.signatureImagePath);
    if (sigBytes != null && sigBytes.isNotEmpty) {
      try {
        final image = pw.MemoryImage(sigBytes);
        signatureWidget = pw.Image(image, height: 45, fit: pw.BoxFit.contain);
      } catch (e) {
        debugPrint('Error loading signature image: $e');
      }
    }

    // Date calculations for Tagalog
    final tagalogIssueDate = _toTagalogDate(borrower.issueDate);
    final tagalogRepaymentDate = _toTagalogDate(borrower.repaymentDate);

    // Styling colors
    final orangeThemeColor = PdfColor.fromHex('#D97706');
    final greyText = PdfColor.fromHex('#6B7280');
    final lightYellowBg = PdfColor.fromHex('#FFFDF0');
    final lightOrangeBorder = PdfColor.fromHex('#FDE8C4');
    final greenText = PdfColor.fromHex('#10B981');

    // Page 1: English
    pdf.addPage(
      pw.Page(
        theme: myTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(
                logoText: 'ANDA',
                taglineText: 'your favorite friendly neighbor lender',
                titleText: 'PROMISSORY NOTE & LOAN CONTRACT',
                refNo: borrower.loanReference,
                orangeColor: orangeThemeColor,
                greyColor: greyText,
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1.5, color: orangeThemeColor),
              pw.SizedBox(height: 12),

              // Intro Paragraph
              pw.RichText(
                text: pw.TextSpan(
                  style: const pw.TextStyle(color: PdfColors.black, fontSize: 9.5, lineSpacing: 2),
                  children: [
                    const pw.TextSpan(text: 'This Loan Agreement (the "Agreement") is entered into and made effective as of '),
                    pw.TextSpan(text: borrower.issueDate, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    const pw.TextSpan(text: ', by and between the lender, '),
                    pw.TextSpan(text: 'Julius Lorenzo Ramboy (ANDA)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    const pw.TextSpan(text: ', and the undersigned borrower, specified under the covenants detailed below.'),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),

              // Terms Table
              _buildEnglishTable(
                borrowerName: borrower.fullName,
                issueDate: borrower.issueDate,
                principalAmount: formattedAmount,
                interestRate: borrower.isOneTimeInterest ? '$formattedRate One-time' : '$formattedRate Monthly',
                repaymentDate: borrower.repaymentDate,
                maturityBalance: formattedMaturity,
                agreedAmount: hasAgreedAmount ? '$formattedAgreed / month' : null,
                lightYellowBg: lightYellowBg,
                borderColor: lightOrangeBorder,
                labelColor: greyText,
                orangeColor: orangeThemeColor,
                greenColor: greenText,
              ),
              pw.SizedBox(height: 14),

              // Section 1
              _buildSectionHeader(
                borrower.isOneTimeInterest
                    ? '1. PROMISE TO PAY'
                    : '1. PROMISE TO PAY & MONTHLY INTEREST STRUCTURE',
                orangeThemeColor,
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                borrower.isOneTimeInterest
                    ? 'The Borrower promises to pay the amount borrowed (principal) of $formattedAmount, together with interest structured as a one-time agreed amount of $formattedRate.'
                    : 'The Borrower promises to pay the amount borrowed (principal) of $formattedAmount, together with interest structured monthly at a fixed rate of $formattedRate.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.black, lineSpacing: 1.8),
              ),
              pw.SizedBox(height: 12),

              // Section 2
              _buildSectionHeader('2. CONDITIONS FOR REPAYMENT & PENALTIES', orangeThemeColor),
              pw.SizedBox(height: 6),
              pw.Text(
                borrower.isOneTimeInterest
                    ? 'If the Borrower fails to fully pay the outstanding balance on or before the specified Repayment Date, a penalty interest may apply as agreed upon by both parties.'
                    : 'If the Borrower fails to fully pay the outstanding balance on or before the specified Repayment Date, a running monthly interest charge will automatically apply to the remaining balance.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.black, lineSpacing: 1.8),
              ),
              pw.SizedBox(height: 6),
              pw.RichText(
                text: pw.TextSpan(
                  style: const pw.TextStyle(color: PdfColors.black, fontSize: 9, lineSpacing: 2),
                  children: [
                    pw.TextSpan(text: 'Exemption Clause: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    const pw.TextSpan(text: 'If the Borrower successfully makes a partial payment/reduction on their debt based on the '),
                    pw.TextSpan(
                      text: hasAgreedAmount ? 'Agreed Setup Amount' : 'agreed setup amount',
                      style: pw.TextStyle(fontWeight: hasAgreedAmount ? pw.FontWeight.bold : pw.FontWeight.normal),
                    ),
                    pw.TextSpan(
                      text: hasAgreedAmount ? ' (specified in the terms box above)' : '',
                    ),
                    const pw.TextSpan(text: ', '),
                    pw.TextSpan(text: 'no monthly interest', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    const pw.TextSpan(text: ' will be charged or incurred for that specific period.'),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),

              // Section 3
              _buildSectionHeader('3. INTEREST RECALCULATION ON PRINCIPAL REDUCTION', orangeThemeColor),
              pw.SizedBox(height: 6),
              pw.Text(
                'Interest is always computed as a percentage of the current outstanding principal, not the original loan amount. When a borrower makes a payment that reduces the principal, the interest due for the next billing cycle is recalculated based on the new (reduced) principal balance.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.black, lineSpacing: 1.8),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Example: Principal = Php 20,000 at 10% interest/month -> interest due = Php 2,000/month.\nOn the due date, borrower pays Php 2,000 (principal) + Php 2,000 (interest) = Php 4,000 total.\nNew principal balance = Php 18,000.\nNext month\'s interest = 10% of Php 18,000 = Php 1,800 (not Php 2,000).',
                style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#4B5563'), fontStyle: pw.FontStyle.italic, lineSpacing: 1.6),
              ),
              pw.Spacer(),

              // Signature Block
              _buildSignatureBlock(
                borrowerName: borrower.fullName.toUpperCase(),
                roleLabel: 'Borrower Signature',
                signatureWidget: signatureWidget,
                borderColor: orangeThemeColor,
              ),
            ],
          );
        },
      ),
    );

    // Page 2: Tagalog
    pdf.addPage(
      pw.Page(
        theme: myTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(
                logoText: 'ANDA',
                taglineText: 'your favorite friendly neighbor lender',
                titleText: 'KASUNDUAN SA PAGPAPAUTANG',
                refNo: borrower.loanReference,
                orangeColor: orangeThemeColor,
                greyColor: greyText,
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1.5, color: orangeThemeColor),
              pw.SizedBox(height: 12),

              // Intro Paragraph Tagalog
              pw.RichText(
                text: pw.TextSpan(
                  style: const pw.TextStyle(color: PdfColors.black, fontSize: 9.5, lineSpacing: 2),
                  children: [
                    const pw.TextSpan(text: 'Ang Kasunduang ito ay ginawa at ipinatutupad ngayong '),
                    pw.TextSpan(text: tagalogIssueDate, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    const pw.TextSpan(text: ', sa pagitan ng nagpapautang na si '),
                    pw.TextSpan(text: 'Julius Lorenzo Ramboy (ANDA)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    const pw.TextSpan(text: ', at ng hiram na nakalagda sa ibaba, alinsunod sa mga tuntuning nakasaad dito.'),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),

              // Terms Table Tagalog
              _buildTagalogTable(
                borrowerName: borrower.fullName,
                issueDate: tagalogIssueDate,
                principalAmount: formattedAmount,
                interestRate: borrower.isOneTimeInterest ? '$formattedRate (Isang beses)' : '$formattedRate Kada Buwan',
                repaymentDate: tagalogRepaymentDate,
                maturityBalance: formattedMaturity,
                agreedAmount: hasAgreedAmount ? '$formattedAgreed / buwan' : null,
                lightYellowBg: lightYellowBg,
                borderColor: lightOrangeBorder,
                labelColor: greyText,
                orangeColor: orangeThemeColor,
                greenColor: greenText,
              ),
              pw.SizedBox(height: 14),

              // Section 1
              _buildSectionHeader(
                borrower.isOneTimeInterest
                    ? '1. PANGAKONG MAGBAYAD AT INTERES'
                    : '1. PANGAKONG MAGBAYAD AT BUWANANG INTERES',
                orangeThemeColor,
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                borrower.isOneTimeInterest
                    ? 'Ang Humiram ay nangangakong magbayad ng inutang na halaga (principal) na $formattedAmount, kasama ang interes na nakatakda sa na napagkasunduang halaga na $formattedRate.'
                    : 'Ang Humiram ay nangangakong magbayad ng inutang na halaga (principal) na $formattedAmount, kasama ang interes na nakatakda sa $formattedRate kada buwan (monthly interest).',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.black, lineSpacing: 1.8),
              ),
              pw.SizedBox(height: 12),

              // Section 2
              _buildSectionHeader('2. PATAKARAN SA KABAYARAN AT KONDISYON SA INTERES', orangeThemeColor),
              pw.SizedBox(height: 6),
              pw.Text(
                borrower.isOneTimeInterest
                    ? 'Kapag ang Nagkakautang ay hindi nakapagbayad sa takdang Petsa ng Kabayaran (Repayment Date), kaukulang multa o karagdagang interes ay ipapataw ayon sa napagkasunduan.'
                    : 'Kapag ang Nagkakautang ay hindi nakapagbayad sa takdang Petsa ng Kabayaran (Repayment Date), sila ay magbabayad ng kaukulang buwanang interes na ipapataw sa natitirang utang.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.black, lineSpacing: 1.8),
              ),
              pw.SizedBox(height: 6),
              pw.RichText(
                text: pw.TextSpan(
                  style: const pw.TextStyle(color: PdfColors.black, fontSize: 9, lineSpacing: 2),
                  children: [
                    pw.TextSpan(text: 'Kondisyon sa Pagkakaltas (Exemption): ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    const pw.TextSpan(text: 'Kung ang Nagkakautang ay nakapagbawas o nakapagbayad ng kaukulang halaga alinsunod sa '),
                    pw.TextSpan(
                      text: hasAgreedAmount ? 'Pinagkasunduang Hulog' : 'pinagkasunduang "amount"',
                      style: pw.TextStyle(fontWeight: hasAgreedAmount ? pw.FontWeight.bold : pw.FontWeight.normal),
                    ),
                    pw.TextSpan(
                      text: hasAgreedAmount ? ' (nakasaad sa kahon sa itaas)' : '',
                    ),
                    const pw.TextSpan(text: ', '),
                    pw.TextSpan(text: 'hindi sila papatawan ng buwanang interes', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    const pw.TextSpan(text: ' para sa naturang buwan o panahon.'),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),

              // Section 3 Tagalog
              _buildSectionHeader('3. REKULKULASYON NG INTERES SA PAGBAWAS NG PRINSIPAL', orangeThemeColor),
              pw.SizedBox(height: 6),
              pw.Text(
                'Ang interes ay palaging kinukwenta batay sa kasalukuyang natitirang utang (principal), at hindi sa orihinal na halaga ng inutang. Kapag ang humiram ay nagbayad ng halagang nakapagbawas sa principal, ang interes para sa susunod na buwan ay muling kukwentahin batay sa bago at nabawasang principal balance.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.black, lineSpacing: 1.8),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Halimbawa: Principal = Php 20,000 sa 10% interes/buwan -> interes = Php 2,000/buwan.\nSa takdang petsa, ang humiram ay nagbayad ng Php 2,000 (principal) + Php 2,000 (interes) = Php 4,000 kabuuan.\nAng bagong principal balance = Php 18,000.\nAng interes sa susunod na buwan = 10% ng Php 18,000 = Php 1,800 (hindi na Php 2,000).',
                style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#4B5563'), fontStyle: pw.FontStyle.italic, lineSpacing: 1.6),
              ),
              pw.Spacer(),

              // Signature Block Tagalog
              _buildSignatureBlock(
                borrowerName: borrower.fullName.toUpperCase(),
                roleLabel: 'Lagda ng Humiram',
                signatureWidget: signatureWidget,
                borderColor: orangeThemeColor,
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  static Future<void> savePdfToDownloads(
      BuildContext context, String fileName, List<int> bytes) async {
    try {
      if (Platform.isAndroid) {
        final dir = Directory('/storage/emulated/0/Download');
        if (await dir.exists()) {
          final file = File('${dir.path}/$fileName');
          await file.writeAsBytes(bytes);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Saved to Downloads: $fileName'),
                backgroundColor: Colors.green,
              ),
            );
          }
          return;
        }
      }
      
      // Fallback for iOS or non-standard Android
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: fileName,
      );
    } catch (e) {
      try {
        await Printing.sharePdf(
          bytes: Uint8List.fromList(bytes),
          filename: fileName,
        );
      } catch (err) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save or share PDF: $err')),
          );
        }
      }
    }
  }

  static Future<void> downloadContract(
      BuildContext context, Borrower borrower) async {
    try {
      final doc = await generateContract(borrower);
      final bytes = await doc.save();
      final fileName = '${borrower.fullName.replaceAll(' ', '_')}_Contract.pdf';
      await savePdfToDownloads(context, fileName, bytes);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
      }
    }
  }

  static Future<void> downloadPaymentHistory(
      BuildContext context, Borrower borrower, List<Payment> payments) async {
    try {
      final doc = await generatePaymentHistory(borrower, payments);
      final bytes = await doc.save();
      final fileName = '${borrower.fullName.replaceAll(' ', '_')}_Payment_History.pdf';
      await savePdfToDownloads(context, fileName, bytes);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
      }
    }
  }

  static Future<void> viewContract(
      BuildContext context, Borrower borrower) async {
    try {
      final doc = await generateContract(borrower);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: '${borrower.fullName.replaceAll(' ', '_')}_Contract.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
      }
    }
  }

  static Future<void> shareContract(
      BuildContext context, Borrower borrower) async {
    try {
      final doc = await generateContract(borrower);
      final pdfBytes = await doc.save();
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: '${borrower.fullName.replaceAll(' ', '_')}_Contract.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share PDF: $e')),
        );
      }
    }
  }

  static Future<pw.Document> generatePaymentHistory(
      Borrower borrower, List<Payment> payments) async {
    final pdf = pw.Document();

    // Load fonts to support Unicode symbols like ₱
    final baseFont = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    final italicFont = await PdfGoogleFonts.robotoItalic();

    final myTheme = pw.ThemeData.withFont(
      base: baseFont,
      bold: boldFont,
      italic: italicFont,
    );

    final fmt = NumberFormat('#,##0.00');

    // Calculations
    final totalPrincipal = borrower.amountBorrowed;
    final totalObligation = borrower.calculateMaturityBalance(payments);

    final totalPaid = payments
        .where((p) => p.status == 'paid')
        .fold<double>(0.0, (sum, p) => sum + p.amount);

    final remainingBalance = max(0.0, totalObligation - totalPaid);

    final generatedDate = DateFormat('MMMM d, yyyy').format(DateTime.now());
    final accRef = '#ACC-${(borrower.id ?? 1) + 99400}';

    pdf.addPage(
      pw.Page(
        theme: myTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header section
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'ANDA',
                        style: pw.TextStyle(
                          color: PdfColor.fromHex('#D97706'),
                          fontSize: 26,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'YOUR FAVORITE FRIENDLY NEIGHBOR LENDER',
                        style: pw.TextStyle(
                          color: PdfColor.fromHex('#6B7280'),
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'PAYMENT HISTORY',
                        style: pw.TextStyle(
                          color: PdfColor.fromHex('#111827'),
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Generated on: $generatedDate',
                        style: pw.TextStyle(
                          color: PdfColor.fromHex('#4B5563'),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(thickness: 0.8, color: PdfColor.fromHex('#E5E7EB')),
              pw.SizedBox(height: 16),

              // Metadata columns
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'BORROWER ACCOUNT',
                          style: pw.TextStyle(
                            color: PdfColor.fromHex('#9CA3AF'),
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          borrower.fullName,
                          style: pw.TextStyle(
                            color: PdfColor.fromHex('#111827'),
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Account Ref: $accRef',
                          style: pw.TextStyle(
                            color: PdfColor.fromHex('#4B5563'),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'LOAN SPECIFICATIONS',
                          style: pw.TextStyle(
                            color: PdfColor.fromHex('#9CA3AF'),
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.RichText(
                          text: pw.TextSpan(
                            style: pw.TextStyle(
                                color: PdfColor.fromHex('#4B5563'),
                                fontSize: 10),
                            children: [
                              const pw.TextSpan(text: 'Loan Reference: '),
                              pw.TextSpan(
                                text: borrower.loanReference,
                                style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.black),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Total Loan Principal: Php ${fmt.format(totalPrincipal)}',
                          style: pw.TextStyle(
                            color: PdfColor.fromHex('#4B5563'),
                            fontSize: 10,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          borrower.isOneTimeInterest 
                              ? 'Interest Matrix: Php ${fmt.format(borrower.interestRate)} One-time' 
                              : 'Interest Matrix: ${borrower.interestRate.toInt()}% Monthly',
                          style: pw.TextStyle(
                            color: PdfColor.fromHex('#4B5563'),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 24),

              // Status Summary Cards Row
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: _buildSummaryCard(
                      'TOTAL OBLIGATION',
                      'Php ${fmt.format(totalObligation)}',
                      PdfColor.fromHex('#6B7280'),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: _buildSummaryCard(
                      'TOTAL PAID TO DATE',
                      'Php ${fmt.format(totalPaid)}',
                      PdfColor.fromHex('#10B981'),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: _buildSummaryCard(
                      'REMAINING BALANCE',
                      'Php ${fmt.format(remainingBalance)}',
                      PdfColor.fromHex('#D97706'),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 24),

              // Transaction Table
              pw.Table(
                columnWidths: const {
                  0: pw.FlexColumnWidth(1.2),
                  1: pw.FlexColumnWidth(2),
                  2: pw.FlexColumnWidth(1.2),
                },
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#D97706'),
                    ),
                    children: [
                      _buildTableHeaderCell('TRANSACTION ID'),
                      _buildTableHeaderCell('PAYMENT DATE'),
                      _buildTableHeaderCell('AMOUNT PAID', alignRight: true),
                    ],
                  ),
                  // Table Rows
                  ...payments.asMap().entries.map((entry) {
                    final index = entry.key;
                    final p = entry.value;
                    final isEven = index % 2 == 0;
                    final rowColor =
                        isEven ? PdfColor.fromHex('#FFFDF0') : PdfColors.white;

                    final txnId =
                        '#TXN-${(p.id ?? index + 1).toString().padLeft(3, '0')}';
                    final isCredit = p.status == 'credited';
                    final formattedAmount =
                        '${isCredit ? '-' : ''}Php ${fmt.format(p.amount)}';

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: rowColor),
                      children: [
                        _buildTableCell(txnId),
                        _buildTableCell(p.paymentDate),
                        _buildTableCell(formattedAmount, alignRight: true),
                      ],
                    );
                  }).toList(),
                ],
              ),
              pw.SizedBox(height: 35),

              // Verification Note / Footer
              pw.Divider(thickness: 0.8, color: PdfColor.fromHex('#E5E7EB')),
              pw.SizedBox(height: 12),
              pw.Text(
                'VERIFICATION NOTE',
                style: pw.TextStyle(
                  color: PdfColor.fromHex('#9CA3AF'),
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'This statement details the transaction ledger tracks relative to your reference contract ${borrower.loanReference}. All completed transactions reflect real-time updates cleared by financial processing partners. If you spot discrepancies, please file an account challenge inside the Anda application profile dashboard.',
                style: pw.TextStyle(
                  color: PdfColor.fromHex('#6B7280'),
                  fontSize: 9,
                  lineSpacing: 2,
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  static pw.Widget _buildSummaryCard(
      String label, String value, PdfColor accentColor) {
    return pw.Container(
      height: 52,
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F9FAFB'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(width: 0.5, color: PdfColor.fromHex('#E5E7EB')),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            width: 4,
            decoration: pw.BoxDecoration(
              color: accentColor,
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(5),
                bottomLeft: pw.Radius.circular(5),
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    label,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#6B7280'),
                      letterSpacing: 0.5,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    value,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#111827'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTableHeaderCell(String text,
      {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: pw.Align(
        alignment:
            alignRight ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
            fontSize: 9,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  static pw.Widget _buildTableCell(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: pw.Align(
        alignment:
            alignRight ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: const pw.TextStyle(
            fontSize: 9,
            color: PdfColors.grey800,
          ),
        ),
      ),
    );
  }

  static Future<void> viewPaymentHistory(
      BuildContext context, Borrower borrower, List<Payment> payments) async {
    try {
      final doc = await generatePaymentHistory(borrower, payments);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: '${borrower.fullName.replaceAll(' ', '_')}_Payment_History.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
      }
    }
  }

  static Future<void> sharePaymentHistory(
      BuildContext context, Borrower borrower, List<Payment> payments) async {
    try {
      final doc = await generatePaymentHistory(borrower, payments);
      final pdfBytes = await doc.save();
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename:
            '${borrower.fullName.replaceAll(' ', '_')}_Payment_History.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share PDF: $e')),
        );
      }
    }
  }
}
