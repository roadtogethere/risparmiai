import 'package:flutter/material.dart';
import '../domain/privacy_repository.dart';
import 'privacy_policy_page.dart';

/// Acknowledgement of an information notice, never advertising consent.
class PrivacyNoticeGate extends StatefulWidget {
  const PrivacyNoticeGate({
    super.key,
    required this.repository,
    required this.child,
    this.onReady,
  });
  final PrivacyRepository repository;
  final Widget child;
  final VoidCallback? onReady;
  @override
  State<PrivacyNoticeGate> createState() => _PrivacyNoticeGateState();
}

class _PrivacyNoticeGateState extends State<PrivacyNoticeGate> {
  bool _loading = true;
  bool _viewed = false;
  bool _saving = false;
  bool _error = false;
  bool _notified = false;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final viewed = await widget.repository.hasViewedCurrentNotice();
      if (!mounted) return;
      setState(() {
        _viewed = viewed;
        _loading = false;
      });
      if (viewed) _ready();
    } catch (_) {
      // A failed read must not silently bypass the notice.
      if (mounted) setState(() => _loading = false);
    }
  }

  void _ready() {
    if (_notified) return;
    _notified = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady?.call();
    });
  }

  Future<void> _continue() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = false;
    });
    try {
      await widget.repository.markCurrentNoticeViewed();
      if (!mounted) return;
      setState(() {
        _viewed = true;
        _saving = false;
      });
      _ready();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_viewed) return widget.child;
    final english = Localizations.localeOf(context).languageCode == 'en';
    return Scaffold(
      appBar: AppBar(title: const Text('RisparmiAi')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.privacy_tip_outlined, size: 48),
                const SizedBox(height: 20),
                Text(
                  english
                      ? 'Your privacy, at a glance'
                      : 'La tua privacy, in breve',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  english
                      ? 'No account required. Saved prices and custom categories stay on your device.\n\nOnline analysis sends your chat text and necessary context to OpenAI or Google Gemini. Do not enter personal or confidential data.\n\nGoogle AdMob may process device and interaction data for ads. Advertising choices will be managed separately.'
                      : 'Non serve un account. I prezzi salvati e le categorie personalizzate restano sul dispositivo.\n\nLe analisi online inviano il testo della chat e il contesto necessario a OpenAI o Google Gemini. Non inserire dati personali o riservati.\n\nGoogle AdMob può trattare dati del dispositivo e delle interazioni per gli annunci. Le scelte pubblicitarie sono gestite separatamente.',
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PrivacyPolicyPage(repository: widget.repository),
                    ),
                  ),
                  child: Text(
                    english
                        ? 'Read the full notice · IT / EN'
                        : 'Leggi l’informativa completa · IT / EN',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  english
                      ? 'Continuing acknowledges this notice; it does not give advertising consent.'
                      : 'Continuando confermi la presa visione dell’informativa, non il consenso pubblicitario.',
                ),
                if (_error)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      english
                          ? 'Unable to save your acknowledgement. Please retry.'
                          : 'Impossibile salvare la presa visione. Riprova.',
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _continue,
                  child: Text(
                    _saving
                        ? (english ? 'Saving…' : 'Salvataggio…')
                        : (english
                              ? "I've read it, continue"
                              : 'Ho letto, continua'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
