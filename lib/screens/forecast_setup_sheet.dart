import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result of [showForecastSetupSheet]:
///   • `null`  → cancelled, no change
///   • `''`    → remove the existing key (disable forecast)
///   • other   → save this key (enable forecast)
Future<String?> showForecastSetupSheet(
  BuildContext context, {
  String initialKey = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ForecastSetupSheet(initialKey: initialKey),
  );
}

class _ForecastSetupSheet extends StatefulWidget {
  const _ForecastSetupSheet({required this.initialKey});

  final String initialKey;

  @override
  State<_ForecastSetupSheet> createState() => _ForecastSetupSheetState();
}

class _ForecastSetupSheetState extends State<_ForecastSetupSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialKey,
  );

  static final Uri _keysUrl = Uri.parse(
    'https://app.tomorrow.io/development/keys',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openTomorrowIo() async {
    try {
      await launchUrl(_keysUrl, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the browser.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasExistingKey = widget.initialKey.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161E33).withValues(alpha: 0.96),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.satellite_alt_rounded,
                          color: Color(0xFFFFC15E),
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Forecast radar',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'See up to 6 hours of predicted rain and snow on the map. '
                      "It's free — you just need your own Tomorrow.io API key.",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _step(1, 'Tap “Get a free key” and sign up (it’s free).'),
                    _step(
                      2,
                      'In the dashboard, open Development → API Keys and copy your key.',
                    ),
                    _step(3, 'Paste it below and tap Save.'),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _openTomorrowIo,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Get a free key'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _controller,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Tomorrow.io API key',
                        labelStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        hintText: 'Paste your key',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFFFC15E),
                          ),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Stored only on this device.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        if (hasExistingKey)
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(''),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(
                                  0xFFE3415E,
                                ).withValues(alpha: 0.95),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              child: const Text('Remove'),
                            ),
                          ),
                        if (hasExistingKey) const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _controller.text.trim().isEmpty
                                ? null
                                : () => Navigator.of(
                                    context,
                                  ).pop(_controller.text.trim()),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFFC15E),
                              foregroundColor: const Color(0xFF1A1300),
                              disabledBackgroundColor: Colors.white.withValues(
                                alpha: 0.12,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              hasExistingKey ? 'Save' : 'Save & enable',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _step(int n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFFC15E).withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFFC15E).withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              '$n',
              style: const TextStyle(
                color: Color(0xFFFFC15E),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
