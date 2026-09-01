import 'package:flutter/material.dart';
import '../services/ai_chat_service.dart';
import '../theme/app_theme.dart';
import '../widgets/vault_toast.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> with TickerProviderStateMixin {
  final _chatService = AiChatService.instance;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  String _selectedModel = 'ANDA 1.4';
  late AnimationController _dotsController;

  @override
  void initState() {
    super.initState();
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 250), _scrollToBottom);
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendMessage([String? predefinedText]) async {
    final text = predefinedText ?? _inputController.text.trim();
    if (text.isEmpty || _chatService.isGenerating) return;

    _inputController.clear();
    setState(() {});
    _scrollToBottom();

    await _chatService.sendMessage(text);

    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _handleStopGenerate() {
    setState(() {
      _chatService.stopGeneration();
    });
  }

  void _togglePin() {
    setState(() {
      _chatService.togglePin();
    });
    VaultToast.showInfo(
      context,
      _chatService.isPinned
          ? 'Chat pinned: Conversation will not vanish when navigating.'
          : 'Chat unpinned.',
    );
  }

  String _cleanMessageText(String text) {
    var cleaned = text.replaceAll('**', '').replaceAll('__', '');
    cleaned = cleaned.replaceAll(RegExp(r'^\s*\*\s+', multiLine: true), '• ');
    cleaned = cleaned.replaceAll(RegExp(r'^\s*#{1,6}\s+', multiLine: true), '');
    return cleaned.trim();
  }

  void _showModelSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select AI Model',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.navy,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ANDA 1.4 (gpt-oss-120b)', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Groq high-speed 120B reasoning engine', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
              trailing: _selectedModel == 'ANDA 1.4' ? const Icon(Icons.check_circle, color: AppTheme.navy) : null,
              onTap: () {
                setState(() => _selectedModel = 'ANDA 1.4');
                Navigator.pop(ctx);
              },
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Clear / New Conversation', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.red)),
              subtitle: const Text('Reset chat messages and start fresh', style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
              leading: const Icon(Icons.delete_outline, color: AppTheme.red),
              onTap: () {
                setState(() {
                  _chatService.startNewChat();
                });
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallLogo({double size = 18}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.asset(
        'assets/logo.jpg',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleText = _chatService.currentTopic ?? 'ANDA AI\nAssistant';

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _chatService.clearIfUnpinned();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.cream,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top Navigation Bar ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back Button
                    GestureDetector(
                      onTap: () {
                        _chatService.clearIfUnpinned();
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1E1E24),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),

                    // Model Selector Pill
                    GestureDetector(
                      onTap: _showModelSelector,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black26, width: 1.2),
                          borderRadius: BorderRadius.circular(24),
                          color: Colors.transparent,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedModel,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E1E24),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.keyboard_arrow_down,
                              size: 16,
                              color: Color(0xFF1E1E24),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Pin Action Button
                    GestureDetector(
                      onTap: _togglePin,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _chatService.isPinned
                              ? Colors.transparent
                              : const Color(0xFF1E1E24),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _chatService.isPinned
                                ? Colors.black38
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          _chatService.isPinned
                              ? Icons.push_pin
                              : Icons.edit_outlined,
                          color: _chatService.isPinned
                              ? const Color(0xFF1E1E24)
                              : Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Header Title (Current Topic / Prompt) ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text(
                  titleText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E1E24),
                    height: 1.2,
                    letterSpacing: -0.5,
                  ),
                ),
              ),

              // ── Dark Chat Container Panel ──
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22221E),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Messages List
                      Expanded(
                        child: _chatService.messages.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                                itemCount: _chatService.messages.length,
                                itemBuilder: (context, index) {
                                  final msg = _chatService.messages[index];
                                  if (msg.role == 'user') {
                                    return _buildUserMessage(msg);
                                  } else {
                                    return _buildAssistantMessage(msg);
                                  }
                                },
                              ),
                      ),

                      // Generating Indicator & Stop Generate Button (Label: ANSWERING with small logo)
                      if (_chatService.isGenerating)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  _buildSmallLogo(size: 16),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'ANSWERING',
                                    style: TextStyle(
                                      color: Color(0xFFFFCC00),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildAnimatedDots(),
                                ],
                              ),
                              ElevatedButton.icon(
                                onPressed: _handleStopGenerate,
                                icon: const Icon(Icons.stop_circle, size: 16),
                                label: const Text(
                                  'STOP GENERATE',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFC700),
                                  foregroundColor: const Color(0xFF1E1E24),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Input Bar
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                        color: const Color(0xFF22221E),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7F2EA),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: TextField(
                                  controller: _inputController,
                                  focusNode: _focusNode,
                                  style: const TextStyle(
                                    color: Color(0xFF1E1E24),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: 'Type here...',
                                    hintStyle: TextStyle(
                                      color: Color(0xFF888888),
                                      fontSize: 14,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  onSubmitted: (val) => _handleSendMessage(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () => _handleSendMessage(),
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF00A86B),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty State with Quick Prompts ──
  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF33332D),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              "Hi, I'm ANDA your lending assistant. Ask me about your borrowers, upcoming due dates, or your overall financial summary anytime.",
              style: TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'SUGGESTIONS',
            style: TextStyle(
              color: Color(0xFF888880),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          _buildPromptChip('Who has overdue payments?'),
          _buildPromptChip('Show upcoming due dates this week'),
          _buildPromptChip('What is my total lending summary and profit?'),
          _buildPromptChip('List all active borrowers with balances'),
        ],
      ),
    );
  }

  Widget _buildPromptChip(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _handleSendMessage(text),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF3E3E36)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ── Assistant Message Card (Matches Dark Theme Bubbles with Small Logo beside ANDA) ──
  Widget _buildAssistantMessage(ChatMessage msg) {
    final cleanedFull = _cleanMessageText(msg.content);
    final paragraphs = cleanedFull
        .split('\n\n')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Small Logo beside ANDA badge
          Row(
            children: [
              _buildSmallLogo(size: 16),
              const SizedBox(width: 8),
              const Text(
                'ANDA',
                style: TextStyle(
                  color: Color(0xFFFFCC00),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...paragraphs.map((paragraph) {
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF33332D),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                paragraph,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── User Message Card (Right Aligned White Pill) ──
  Widget _buildUserMessage(ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ME tag with Avatar
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text(
                'ME',
                style: TextStyle(
                  color: Color(0xFF888880),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Color(0xFFE2DDD5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person,
                  size: 14,
                  color: Color(0xFF1E1E24),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              msg.content,
              style: const TextStyle(
                color: Color(0xFF1E1E24),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedDots() {
    return AnimatedBuilder(
      animation: _dotsController,
      builder: (context, child) {
        final val = (_dotsController.value * 3).floor();
        return Row(
          children: List.generate(3, (i) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: val == i ? const Color(0xFFFFCC00) : Colors.white24,
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
