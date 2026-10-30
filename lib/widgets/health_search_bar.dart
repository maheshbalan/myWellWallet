import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../theme/app_palette.dart';

/// Search field with a microphone. Spoken words are written into [controller].
class HealthSearchBar extends StatefulWidget {
  const HealthSearchBar({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  State<HealthSearchBar> createState() => _HealthSearchBarState();
}

class _HealthSearchBarState extends State<HealthSearchBar> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;
  Timer? _noSpeechTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _noSpeechTimer?.cancel();
    _speech.stop();
    super.dispose();
  }

  Future<void> _ensureSpeech() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    var speech = await Permission.speech.status;
    if (!speech.isGranted) speech = await Permission.speech.request();
    var mic = await Permission.microphone.status;
    if (!mic.isGranted) mic = await Permission.microphone.request();
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    _speechAvailable = available && mic.isGranted && speech.isGranted;
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      _stop();
      return;
    }
    if (!_speechAvailable) {
      await _ensureSpeech();
    }
    if (!_speechAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Allow the microphone and speech recognition to search by voice.'),
        ),
      );
      return;
    }
    setState(() => _listening = true);
    _noSpeechTimer?.cancel();
    _noSpeechTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _listening && widget.controller.text.trim().isEmpty) {
        _stop();
      }
    });
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        if (result.recognizedWords.isNotEmpty) {
          _noSpeechTimer?.cancel();
        }
        widget.controller.value = TextEditingValue(
          text: result.recognizedWords,
          selection: TextSelection.collapsed(offset: result.recognizedWords.length),
        );
        widget.onChanged?.call(result.recognizedWords);
        if (result.finalResult) _stop();
      },
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
    );
  }

  void _stop() {
    _noSpeechTimer?.cancel();
    _speech.stop();
    if (mounted) setState(() => _listening = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              onChanged: widget.onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.search, color: AppPalette.muted),
                suffixIcon: widget.controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          widget.controller.clear();
                          widget.onChanged?.call('');
                        },
                        icon: const Icon(Icons.close, color: AppPalette.muted),
                      ),
                filled: true,
                fillColor: AppPalette.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: const BorderSide(color: AppPalette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: const BorderSide(color: AppPalette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: const BorderSide(color: AppPalette.gold, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: _listening ? AppPalette.gold : AppPalette.creamWarm,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _toggleMic,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  _listening ? Icons.mic : Icons.mic_none,
                  color: AppPalette.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
