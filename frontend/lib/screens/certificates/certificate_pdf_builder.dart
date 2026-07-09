import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../models/certificate_model.dart';

/// Builds the actual A4-landscape certificate PDF. Kept separate from
/// the viewer screen so both the on-screen preview (via printing's
/// PdfPreview) and Download/Print/Share all reuse the exact same bytes.
class CertificatePdfBuilder {
  static Future<Uint8List> build(CertificateModel cert) async {
    final doc = pw.Document();

    final purple = PdfColor.fromHex('#6C5CE7');
    final grey = PdfColor.fromHex('#666666');
    final gold = PdfColor.fromHex('#C9A227');

    // "Future verification" URL - doesn't need to resolve to anything
    // real yet, the QR just needs to encode the certificate's unique code.
    final verificationUrl = 'https://aitutor.app/verify/${cert.certificateCode}';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: purple, width: 3),
            ),
            margin: const pw.EdgeInsets.all(12),
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // --- Header: AI Tutor logo mark ---
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: pw.BoxDecoration(color: purple, borderRadius: pw.BorderRadius.circular(6)),
                      child: pw.Text('AI TUTOR', style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
                    ),
                  ],
                ),
                pw.SizedBox(height: 18),
                pw.Text('CERTIFICATE OF COMPLETION', style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: purple, letterSpacing: 2)),
                pw.SizedBox(height: 4),
                pw.Text('This certificate is proudly presented to', style: pw.TextStyle(fontSize: 11, color: grey)),
                pw.SizedBox(height: 16),
                pw.Text(cert.studentName, style: pw.TextStyle(fontSize: 34, fontWeight: pw.FontWeight.bold)),
                pw.Container(margin: const pw.EdgeInsets.symmetric(vertical: 10), width: 220, height: 1.2, color: gold),
                pw.SizedBox(height: 6),
                pw.Text(
                  'for successfully completing the course',
                  style: pw.TextStyle(fontSize: 11, color: grey),
                ),
                pw.SizedBox(height: 4),
                pw.Text('${cert.courseName} \u2022 ${cert.subjectName}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 20),

                // --- Score / Grade / Dates row ---
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  children: [
                    _statBlock('Final Score', '${cert.finalScore.toStringAsFixed(1)}%', grey),
                    _statBlock('Grade', cert.grade, grey),
                    _statBlock('Completion Date', cert.completionDate, grey),
                    _statBlock('Issue Date', '${cert.issueDate.day}/${cert.issueDate.month}/${cert.issueDate.year}', grey),
                  ],
                ),
                pw.Spacer(),

                // --- Footer: signature, QR, instructor, cert ID ---
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Instructor', style: pw.TextStyle(fontSize: 9, color: grey)),
                        pw.Text(cert.instructorName, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: verificationUrl,
                          width: 64,
                          height: 64,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('Scan to verify', style: pw.TextStyle(fontSize: 7, color: grey)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Digitally Signed', style: pw.TextStyle(fontSize: 9, color: grey)),
                        pw.Text('AI Tutor Platform', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: purple)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 14),
                pw.Divider(color: PdfColors.grey300),
                pw.SizedBox(height: 6),
                pw.Text('Certificate ID: ${cert.certificateCode}', style: pw.TextStyle(fontSize: 9, color: grey)),
                pw.SizedBox(height: 2),
                pw.Text('This certificate is digitally generated by the AI Tutor Platform.', style: pw.TextStyle(fontSize: 8, color: grey, fontStyle: pw.FontStyle.italic)),
              ],
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _statBlock(String label, String value, PdfColor labelColor) {
    return pw.Column(
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 9, color: labelColor)),
        pw.SizedBox(height: 3),
        pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }
}
