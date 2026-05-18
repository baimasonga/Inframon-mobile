import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../main.dart';

const _mapProjects = [
  {
    'name': 'Highway Renovation A1',
    'lat': 34.0522,
    'lng': -118.2437,
    'status': 'active',
    'issues': 2,
    'phase': 'Phase 2: Structural Framing',
  },
  {
    'name': 'City Hall Extension',
    'lat': 34.0400,
    'lng': -118.2500,
    'status': 'planned',
    'issues': 1,
    'phase': 'Phase 1: Site Preparation',
  },
];

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  void _showProjectSheet(BuildContext context, Map<String, dynamic> project) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: project['status'] == 'active' ? AppColors.blueSoft : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.domain,
                    color: project['status'] == 'active' ? AppColors.blue : AppColors.textSecondary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(project['name'],
                          style: GoogleFonts.inter(
                              fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      Text(project['phase'],
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _SheetChip(
                  label: project['status'] == 'active' ? '● Active' : 'Planned',
                  color: project['status'] == 'active' ? AppColors.blue : AppColors.textSecondary,
                  bg: project['status'] == 'active' ? AppColors.blueSoft : const Color(0xFFF1F5F9),
                ),
                const SizedBox(width: 10),
                _SheetChip(
                  label: '${project['issues']} Open Issues',
                  color: (project['issues'] as int) > 0 ? AppColors.danger : AppColors.success,
                  bg: (project['issues'] as int) > 0
                      ? const Color(0xFFFEF2F2)
                      : const Color(0xFFECFDF5),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${(project['lat'] as double).toStringAsFixed(4)}, ${(project['lng'] as double).toStringAsFixed(4)}',
                  style: GoogleFonts.robotoMono(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Field Map View')),
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(34.0461, -118.2469),
          initialZoom: 13.5,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.inframon',
          ),
          MarkerLayer(
            markers: _mapProjects.map((proj) {
              final isActive = proj['status'] == 'active';
              return Marker(
                point: LatLng(proj['lat'] as double, proj['lng'] as double),
                width: 48,
                height: 48,
                child: GestureDetector(
                  onTap: () => _showProjectSheet(context, proj),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.blue : AppColors.textSecondary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: (isActive ? AppColors.blue : AppColors.textSecondary).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: const Icon(Icons.domain, color: Colors.white, size: 22),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SheetChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _SheetChip({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
    );
  }
}
