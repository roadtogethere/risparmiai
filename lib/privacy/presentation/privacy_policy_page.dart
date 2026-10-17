import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/privacy_repository.dart';

class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key, required this.repository});
  final PrivacyRepository repository;
  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  String? _language;
  Future<String>? _document;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_language != null) return;
    _language = Localizations.localeOf(context).languageCode == 'en'
        ? 'en'
        : 'it';
    _document = widget.repository.loadNotice(_language!);
  }

  Future<void> _openLink(String? href) async {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null || !['https', 'mailto'].contains(uri.scheme)) return;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      /* Display an actionable error below. */
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _language == 'en'
              ? 'Unable to open the link. Try again.'
              : 'Impossibile aprire il collegamento. Riprova.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_language == 'en' ? 'Privacy notice' : 'Informativa privacy'),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'it', label: Text('Italiano')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {_language!},
              onSelectionChanged: (selection) => setState(() {
                _language = selection.single;
                _document = widget.repository.loadNotice(_language!);
              }),
            ),
          ),
          Expanded(
            child: FutureBuilder<String>(
              future: _document,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: () => setState(() {
                        _document = widget.repository.loadNotice(_language!);
                      }),
                      child: Text(
                        _language == 'en'
                            ? 'Unable to load. Retry'
                            : 'Caricamento non riuscito. Riprova',
                      ),
                    ),
                  );
                }
                return Markdown(
                  key: ValueKey(_language),
                  data: snapshot.data!,
                  selectable: true,
                  padding: const EdgeInsets.all(20),
                  onTapLink: (_, href, _) => _openLink(href),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
