import 'package:dartchess/dartchess.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/opening_report.dart';
import '../core/pgn_import.dart';
import 'format.dart';

/// Bilan de mes ouvertures : ce que je joue le plus, variante par variante,
/// et jusqu'où mes coups sont une habitude.
class OpeningsScreen extends ConsumerWidget {
  const OpeningsScreen({super.key, required this.onOpenInTree});

  /// Appelé après avoir placé l'arbre sur la ligne choisie.
  final VoidCallback onOpenInTree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = ref.watch(filterProvider).color;
    final report = ref.watch(openingReportProvider);
    final theme = Theme.of(context);

    void open(List<String> line) {
      ref.read(lineProvider.notifier).set(line);
      Navigator.of(context).pop();
      onOpenInTree();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mes ouvertures')),
      body: report == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SegmentedButton<Side>(
                    segments: const [
                      ButtonSegment(value: Side.white, label: Text('Blancs')),
                      ButtonSegment(value: Side.black, label: Text('Noirs')),
                    ],
                    selected: {color},
                    onSelectionChanged: (s) => ref.read(filterProvider.notifier).setColor(s.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    report.families.isEmpty
                        ? 'Pas encore assez de parties avec cette couleur : une variante compte '
                            'à partir de ${report.minGames} parties. Importe plus de mois.'
                        : 'Tes ouvertures, de la plus jouée à la moins jouée. Une variante compte à partir '
                            'de ${report.minGames} parties ; un coup est connu quand tu le joues au moins 6 fois sur 10.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                for (final (i, family) in report.families.indexed)
                  _FamilyCard(family: family, initiallyExpanded: i == 0, onOpen: open),
              ],
            ),
    );
  }
}

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({required this.family, required this.initiallyExpanded, required this.onOpen});

  final OpeningFamily family;
  final bool initiallyExpanded;
  final ValueChanged<List<String>> onOpen;

  @override
  Widget build(BuildContext context) {
    final depths = [for (final v in family.variants) v.knownDepth]..sort();
    final depth = depths.first == depths.last
        ? _known(depths.first)
        : 'de ${depths.first} à ${_known(depths.last)} selon la variante';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // Sans clé, l'état ouvert ou fermé suivrait la place de la carte
        // quand la couleur change.
        key: PageStorageKey(family.name),
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(family.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text.rich(TextSpan(children: [
          TextSpan(text: '${family.count} parties · '),
          TextSpan(
            text: percent(family.score),
            style: TextStyle(color: scoreColor(context, family.score), fontWeight: FontWeight.w600),
          ),
          TextSpan(text: ' · $depth'),
        ])),
        children: [
          for (final variant in family.variants) ...[
            const Divider(height: 1),
            _VariantTile(variant: variant, onOpen: onOpen),
          ],
        ],
      ),
    );
  }
}

class _VariantTile extends StatelessWidget {
  const _VariantTile({required this.variant, required this.onOpen});

  final OpeningVariant variant;
  final ValueChanged<List<String>> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gap = variant.gap;
    final known = variant.knownDepth;
    final total = variant.steps.length;
    final line = variant.line.isEmpty ? 'Position initiale' : lineLabel(variant.line);
    final title = variant.name == null ? line : variant.name!.variation ?? 'Ligne principale';
    return InkWell(
      // La position où mon habitude s'arrête, sinon la fin de la variante.
      onTap: () => onOpen(gap?.line ?? variant.line),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                const SizedBox(width: 8),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${variant.count} parties · '),
                    TextSpan(
                      text: percent(variant.score),
                      style: TextStyle(color: scoreColor(context, variant.score), fontWeight: FontWeight.w600),
                    ),
                  ]),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (variant.name != null) ...[
              const SizedBox(height: 2),
              Text(line, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : known / total,
                      minHeight: 4,
                      color: Colors.green.shade600,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  known < total ? '${_known(known)} sur $total' : _known(known),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_gapText(variant), style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// « 1 coup connu », « 4 coups connus ».
String _known(int n) => switch (n) {
      0 => 'aucun coup connu',
      1 => '1 coup connu',
      _ => '$n coups connus',
    };

/// Pourquoi mes coups acquis s'arrêtent là.
String _gapText(OpeningVariant variant) {
  final gap = variant.gap;
  if (gap == null) {
    return variant.line.length >= maxPlies
        ? 'Connue jusqu\'au bout des ${maxPlies ~/ 2} coups suivis par l\'arbre.'
        : 'Au-delà, pas assez de parties pour juger.';
  }
  final ply = gap.line.length;
  final played = '${moveLabel(ply, gap.played.san)} (${percent(gap.share)})';
  switch (gap.status) {
    case HabitStatus.offRepertoire:
      return 'Ton répertoire prévoit ${moveLabel(ply, gap.reference)}, tu joues surtout $played.';
    case HabitStatus.hesitant:
      final other = gap.alternative;
      return other == null
          ? 'Ensuite tu hésites : $played.'
          : 'Ensuite tu hésites : $played ou '
              '${moveLabel(ply, other.san)} (${percent(other.count / gap.reached)}).';
    case HabitStatus.known:
      return '';
  }
}
