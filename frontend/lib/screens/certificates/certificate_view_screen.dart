import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../core/theme/app_colors.dart';
import '../../models/certificate_model.dart';
import '../../services/certificate_service.dart';
import 'certificate_pdf_builder.dart';

/// View/Download/Print/Share a single certificate. Accepts either a
/// full [certificate] object (from the My Certificates list) or just an
/// [certificateId] to fetch (role-checked server-side either way).
class CertificateViewScreen extends StatefulWidget {
  final CertificateModel? certificate;
  final int? certificateId;

  const CertificateViewScreen({super.key, this.certificate, this.certificateId})
      : assert(certificate != null || certificateId != null);

  @override
  State<CertificateViewScreen> createState() => _CertificateViewScreenState();
}

class _CertificateViewScreenState extends State<CertificateViewScreen> {
  final CertificateService _service = CertificateService();
  CertificateModel? _certificate;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.certificate != null) {
      setState(() {
        _certificate = widget.certificate;
        _loading = false;
      });
      return;
    }
    try {
      _certificate = await _service.fetchById(widget.certificateId!);
    } catch (e) {
      _error = 'Could not load this certificate.';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Certificate')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _certificate == null
                  ? const Center(child: Text('Certificate not found.'))
                  : PdfPreview(
                      build: (format) => CertificatePdfBuilder.build(_certificate!),
                      allowPrinting: true,
                      allowSharing: true,
                      canDebug: false,
                      pdfFileName: '${_certificate!.certificateCode}.pdf',
                      actions: [
                        PdfPreviewAction(
                          icon: const Icon(Icons.download_rounded),
                          onPressed: (context, buildPdf, pageFormat) async {
                            final bytes = await buildPdf(pageFormat);
                            await Printing.sharePdf(bytes: bytes, filename: '${_certificate!.certificateCode}.pdf');
                          },
                        ),
                      ],
                    ),
    );
  }
}
