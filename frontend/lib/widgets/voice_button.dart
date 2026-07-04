import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../core/theme/app_colors.dart';

/// Basic speech-to-text mic button: tap to start listening, tap again (or
/// pause) to stop. Converts speech to text and hands it to [onResult] â€”
/// there is no text-to-speech or streaming voice assistant, per the "basic
/// voice input only" scope.
///
/// If the device denies microphone permission or speech recognition isn't
/// available, the button disables itself instead of crashing â€” this
/// package needs RECORD_AUDIO permission declared in AndroidManifest.xml
/// (see setup notes).
class VoiceButton extends StatefulWidget {
  final void Function(String text) onResult;

  const VoiceButton({super.key, required this.onResult});

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _isAvailable = true;
  bool _checked = false;

  Future<void> _ensureInitialized() async {
    if (_checked) return;
    _checked = true;
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (error) {
          if (mounted) setState(() => _isListening = false);
        },
      );
      if (mounted) setState(() => _isAvailable = available);
    } catch (_) {
      if (mounted) setState(() => _isAvailable = false);
    }
  }

  Future<void> _toggleListening() async {
    await _ensureInitialized();
    if (!_isAvailable) return;

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    setState(() => _isListening = true);
    try {
      await _speech.listen(
        onResult: (result) {
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            widget.onResult(result.recognizedWords);
          }
        },
      );
    } catch (_) {
      if (mounted) setState(() => _isListening = false);
    }
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _isAvailable ? _toggleListening : null,
      tooltip: _isAvailable ? 'Voice input' : 'Voice input unavailable',
      icon: Icon(
        _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
        color: _isListening ? AppColors.error : (_isAvailable ? AppColors.purple : AppColors.textSecondary),
      ),
    );
  }
}
