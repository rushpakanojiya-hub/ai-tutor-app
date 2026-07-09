import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/certificate_model.dart';
import '../../services/certificate_service.dart';
import 'certificate_view_screen.dart';

enum CertificateListMode { mine, teacher, admin }

/// "My Certificates" - also reused (read-only) for the teacher's
/// "students' certificates" view and the admin's "all certificates" view,
/// since the card UI and actions are identical; only the fetch call and
/// title differ.
class MyCertificatesScreen extends StatefulWidget {
  final CertificateListMode mode;

  const MyCertificatesScreen({super.key, this.mode = CertificateListMode.mine});

  @override
  State<MyCertificatesScreen> createState() => _MyCertificatesScreenState();
}

class _MyCertificatesScreenState extends State<MyCertificatesScreen> {
  final CertificateService _service = CertificateService();
  List<CertificateModel> _certificates = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      switch (widget.mode) {
        case CertificateListMode.mine:
          _certificates = await _service.fetchMine();
          break;
        case CertificateListMode.teacher:
          _certificates = await _service.fetchForTeacher();
          break;
        case CertificateListMode.admin:
          _certificates = await _service.fetchAllForAdmin();
          break;
      }
    } catch (e) {
      _error = 'Could not load certificates.';
    }
    if (mounted) setState(() => _loading = false);
  }

  String get _title {
    switch (widget.mode) {
      case CertificateListMode.mine:
        return 'My Certificates';
      case CertificateListMode.teacher:
        return "Students' Certificates";
      case CertificateListMode.admin:
        return 'All Certificates';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _certificates.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _certificates.length,
                        itemBuilder: (context, index) => _certCard(_certificates[index]),
                      ),
                    ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.workspace_premium_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              widget.mode == CertificateListMode.mine ? 'No Certificates Earned Yet.' : 'No Certificates Yet.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (widget.mode == CertificateListMode.mine)
              Text(
                'Complete a course and pass its assessment to earn your first certificate.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _certCard(CertificateModel cert) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.purple.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.workspace_premium_rounded, color: AppColors.purple, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${cert.courseName} \u2022 ${cert.subjectName}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      if (widget.mode != CertificateListMode.mine)
                        Text(cert.studentName, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text(cert.grade, style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Completed on ${cert.completionDate}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CertificateViewScreen(certificate: cert))),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('View'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CertificateViewScreen(certificate: cert))),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.purple),
                    icon: const Icon(Icons.download_rounded, size: 18, color: Colors.white),
                    label: const Text('Download', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
