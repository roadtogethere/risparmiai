import 'package:flutter/material.dart';

import '../../data/datasources/category_reference_store.dart';
import '../../data/models/category_reference_model.dart';

class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  final CategoryReferenceStore _store = const CategoryReferenceStore();
  late Future<List<CategoryReferenceModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _store.loadCustomCategories();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _store.loadCustomCategories();
    });
  }

  Future<void> _removeCategory(String key) async {
    await _store.removeCategory(key);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: Colors.white,
        title: const Text(
          'Archivio',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: FutureBuilder<List<CategoryReferenceModel>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text('Impossibile leggere archivio. Riprova.'),
              );
            }

            final categories =
                snapshot.data ?? const <CategoryReferenceModel>[];

            if (categories.isEmpty) {
              return _EmptyArchiveState();
            }

            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return _ArchiveEntryCard(
                    category: category,
                    onDelete: () => _removeCategory(category.key),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyArchiveState extends StatelessWidget {
  const _EmptyArchiveState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Nessun prodotto salvato',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Analizza un prodotto in chat e i risultati compariranno qui.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveEntryCard extends StatelessWidget {
  const _ArchiveEntryCard({required this.category, required this.onDelete});

  final CategoryReferenceModel category;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey<String>(category.key),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFBE9E7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Color(0xFFC62828)),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE9ECEF)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Expanded(
                  child: Text(
                    category.displayName.isNotEmpty
                        ? category.displayName
                        : category.key,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F4EA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const <Widget>[
                      Icon(
                        Icons.stars_rounded,
                        size: 14,
                        color: Color(0xFF137333),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Più economico',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF137333),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            RichText(
              text: TextSpan(
                style: const TextStyle(color: Color(0xFF495057), fontSize: 14),
                children: <InlineSpan>[
                  const TextSpan(text: 'Prezzo migliore: '),
                  TextSpan(
                    text: '€${category.averageUnitCost.toStringAsFixed(4)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF137333),
                    ),
                  ),
                  TextSpan(text: ' / ${category.primaryUnit}'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              category.entriesCount > 1
                  ? 'Media su ${category.entriesCount} rilevazioni: €${category.averageOfAllEntries.toStringAsFixed(4)} / ${category.primaryUnit}'
                  : 'Prima rilevazione salvata per questa categoria.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF868E96)),
            ),
            if (category.requiredAttributes.isNotEmpty) ...<Widget>[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: Color(0xFFF1F3F5)),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: category.requiredAttributes.map((attribute) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE9ECEF)),
                    ),
                    child: Text(
                      attribute.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF495057),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
