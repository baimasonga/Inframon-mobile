import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../main.dart';
import 'issue_report_screen.dart';
import 'issue_discussion_screen.dart';

class IssuesListScreen extends StatelessWidget {
  const IssuesListScreen({super.key});

  final List<Map<String, dynamic>> _mockIssues = const [
    {
      'id': '1',
      'title': 'Quality Issue: Sub-base material',
      'project': 'Freetown Ring Road',
      'status': 'Under Review',
      'severity': 'high',
      'replies': 3,
      'date': '2 hours ago',
    },
    {
      'id': '2',
      'title': 'Delay Concern - Heavy Rainfall',
      'project': 'Bo-Kenema Highway',
      'status': 'Open',
      'severity': 'medium',
      'replies': 1,
      'date': '5 hours ago',
    },
    {
      'id': '3',
      'title': 'Pump Efficiency Validation',
      'project': 'Kenema Solar Well',
      'status': 'Resolved',
      'severity': 'low',
      'replies': 0,
      'date': '1 day ago',
    }
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('My Reported Issues', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.blue,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _mockIssues.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final issue = _mockIssues[i];
          return GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => IssueDiscussionScreen(
                  issueId: issue['id'],
                  title: issue['title'],
                  project: issue['project'],
                ),
              ));
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                       Text(issue['project'], style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1.2).copyWith(height: 1)),
                       Text(issue['date'], style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
                     ],
                   ),
                   const SizedBox(height: 8),
                   Text(issue['title'], style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                   const SizedBox(height: 12),
                   Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                       Container(
                         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                         decoration: BoxDecoration(
                           color: issue['severity'] == 'high' ? AppColors.danger.withValues(alpha: 0.1) : AppColors.amber.withValues(alpha: 0.1),
                           borderRadius: BorderRadius.circular(12),
                         ),
                         child: Text(
                           issue['severity'].toUpperCase(),
                           style: GoogleFonts.inter(
                             fontSize: 10,
                             fontWeight: FontWeight.bold,
                             color: issue['severity'] == 'high' ? AppColors.danger : AppColors.amber,
                           ),
                         ),
                       ),
                       Row(
                         children: [
                           const Icon(Icons.forum_outlined, size: 14, color: AppColors.blue),
                           const SizedBox(width: 4),
                           Text('${issue['replies']} Replies', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.blue)),
                         ],
                       )
                     ],
                   )
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.danger,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Report Issue', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const IssueReportScreen(projectId: 'all')));
        },
      ),
    );
  }
}
