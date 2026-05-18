import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../main.dart';

class IssueDiscussionScreen extends StatefulWidget {
  final String issueId;
  final String title;
  final String project;

  const IssueDiscussionScreen({
    super.key,
    required this.issueId,
    required this.title,
    required this.project,
  });

  @override
  State<IssueDiscussionScreen> createState() => _IssueDiscussionScreenState();
}

class _IssueDiscussionScreenState extends State<IssueDiscussionScreen> {
  final _replyController = TextEditingController();
  
  final List<Map<String, dynamic>> _messages = [
    {
      'id': 101,
      'author': 'Jane Smith',
      'role': 'M&E Unit',
      'time': '2 hours ago',
      'text': '@Engineer Please review the latest material test results. It seems the aggregate size is out of spec based on the latest BOQ requirements for the sub-base layer. Can we pause dumping until this is sorted?',
      'isSelf': false,
    },
    {
      'id': 102,
      'author': 'Samuel Kamara',
      'role': 'Engineer',
      'time': '1 hour ago',
      'text': 'I am heading to the site now to verify. I\'ll instruct the Clerk of Works to halt offloading until my visual inspection is complete.',
      'isSelf': false,
    }
  ];

  void _sendReply() {
    if (_replyController.text.trim().isEmpty) return;
    
    setState(() {
      _messages.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'author': 'John Doe',
        'role': 'Clerk of Works',
        'time': 'Just now',
        'text': _replyController.text.trim(),
        'isSelf': true,
      });
    });
    
    _replyController.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Issue Discussion', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(widget.project, style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: AppColors.blue,
      ),
      body: Column(
        children: [
          // Original Issue Context
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ISSUE TOPIC', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text(widget.title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ],
            ),
          ),
          
          // Messages Thread
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, i) {
                final msg = _messages[i];
                final isSelf = msg['isSelf'] == true;
                
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
                  children: [
                    if (!isSelf)
                      Container(
                        width: 36,
                        height: 36,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: AppColors.blue.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(msg['author'].substring(0, 1), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.blue)),
                        ),
                      ),
                      
                    Flexible(
                      child: Column(
                        crossAxisAlignment: isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(isSelf ? 'You' : msg['author'], style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                              const SizedBox(width: 8),
                              if (!isSelf) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(4)),
                                  child: Text(msg['role'], style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Text(msg['time'], style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelf ? AppColors.blue : Colors.white,
                              borderRadius: BorderRadius.circular(16).copyWith(
                                topLeft: isSelf ? const Radius.circular(16) : Radius.zero,
                                topRight: isSelf ? Radius.zero : const Radius.circular(16),
                              ),
                              border: isSelf ? null : Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              msg['text'],
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: isSelf ? Colors.white : AppColors.textPrimary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          
          // Reply Input Box
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4)),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    decoration: InputDecoration(
                      hintText: 'Type a reply to the dashboard...',
                      hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.blue)),
                      filled: true,
                      fillColor: AppColors.surface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _sendReply,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
                    child: const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
