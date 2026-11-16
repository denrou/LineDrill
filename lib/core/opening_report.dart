import 'package:dartchess/dartchess.dart';

import 'game_record.dart';
import 'opening_tree.dart';
import 'openings.dart';
import 'repertoire.dart';

/// Ce que mes parties disent d'un de mes coups dans une variante.
enum HabitStatus {
  /// Je joue presque toujours le même coup, et c'est celui à retenir.
  known,

  /// Aucun coup ne domine dans mes parties.
  hesitant,

  /// Mon répertoire prévoit un autre coup que celui que je joue le plus.
  offRepertoire,
}

/// Une position d'une variante où c'est à moi de jouer.
class HabitStep {
  const HabitStep({
    required this.node,
    required this.line,
    required this.reached,
    required this.played,
    required this.alternative,
    required this.reference,
    required this.status,
  });

  final PositionNode node;

  /// Coups depuis la position initiale jusqu'à cette position.
  final List<String> line;

  /// Parties qui continuent depuis cette position.
  final int reached;

  /// Mon coup le plus joué ici.
  final MoveStats played;

  /// Mon deuxième coup le plus joué, s'il y en a un.
  final MoveStats? alternative;

  /// Coup à retenir, en SAN : celui du répertoire, sinon mon coup habituel.
  final String reference;

  final HabitStatus status;

  /// Part des parties où j'ai joué [played].
  double get share => played.count / reached;
}

/// Une suite de coups que mes adversaires me font jouer assez souvent.
class OpeningVariant {
  const OpeningVariant({
    required this.line,
    required this.name,
    required this.games,
    required this.score,
    required this.steps,
  });

  /// Coups de la variante depuis la position initiale.
  final List<String> line;

  /// Nom de la position nommée la plus profonde de la variante.
  final OpeningName? name;

  /// Parties passées par la position où la dernière réponse adverse de la
  /// variante m'amène, et mon score dans ces parties.
  final List<GameRecord> games;
  final double score;

  int get count => games.length;

  /// Mes coups dans la variante, dans l'ordre.
  final List<HabitStep> steps;

  /// Nombre de mes coups acquis d'affilée depuis le début.
  int get knownDepth => steps.takeWhile((s) => s.status == HabitStatus.known).length;

  /// Premier coup qui n'est pas acquis, ou `null` si tous le sont.
  HabitStep? get gap => steps.where((s) => s.status != HabitStatus.known).firstOrNull;
}

/// Les variantes d'une même ouverture (« Scandinavian Defense »).
class OpeningFamily {
  OpeningFamily(this.name, this.variants);

  final String name;

  /// De la plus jouée à la moins jouée.
  final List<OpeningVariant> variants;

  /// Parties de la famille, chacune comptée une fois même si deux variantes
  /// se rejoignent par un autre ordre de coups.
  late final Set<GameRecord> games = {for (final v in variants) ...v.games};

  int get count => games.length;

  late final double score = games.fold<double>(0, (sum, g) => sum + g.score) / games.length;
}

/// Mes ouvertures, de la plus jouée à la moins jouée.
class OpeningReport {
  const OpeningReport(this.families, this.minGames);

  final List<OpeningFamily> families;

  /// Nombre de parties à partir duquel une réponse adverse fait une variante.
  final int minGames;
}

/// Famille des variantes qu'aucune position nommée ne traverse.
const unnamedFamily = 'Autres lignes';

/// Seuil de parties d'une variante : 10 comme pour les lignes faibles, moins
/// quand il y a peu de parties (5 au minimum) pour qu'un bilan reste possible
/// après un premier import.
int habitMinGames(int games) => (games / 60).round().clamp(5, 10);

/// Bilan de mes ouvertures avec [color] : ce que je joue, variante par
/// variante, et jusqu'où mes coups sont une habitude.
///
/// Depuis la position initiale, mon coup à retenir est suivi (celui du
/// [repertoire], sinon le plus joué) et chaque réponse adverse vue dans au
/// moins [minGames] parties ouvre une branche. Une variante s'arrête quand
/// les parties deviennent trop rares ; deux ordres de coups qui se rejoignent
/// ne font qu'une variante, celle du plus joué. Un de mes coups est acquis
/// s'il est joué dans au moins [minShare] des parties (au pour cent près,
/// comme à l'affichage) et s'accorde avec le répertoire.
OpeningReport openingReport(
  OpeningTree tree, {
  required Side color,
  OpeningBook book = OpeningBook.empty,
  Repertoire? repertoire,
  int? minGames,
  double minShare = 0.6,
}) {
  final threshold = minGames ?? habitMinGames(tree.games.length);
  final variants = <OpeningVariant>[];

  // Parties passées par chaque position, quel que soit l'ordre des coups.
  final reaching = <String, Set<GameRecord>>{};
  for (final game in tree.games) {
    var node = tree.root;
    for (final san in game.sans) {
      final move = node.move(san);
      if (move == null) break;
      reaching.putIfAbsent(move.childKey, () => {}).add(game);
      node = tree.node(move.childKey)!;
    }
  }
  final ended = <String>{};

  // [via] : dernière réponse adverse suivie (à défaut, mon premier coup) ;
  // la position qu'elle atteint donne les parties de la variante. [path] : positions déjà
  // traversées, une répétition de coups ne doit pas faire tourner en rond.
  void walk(
    PositionNode node,
    List<String> line,
    List<HabitStep> steps,
    MoveStats? via,
    OpeningName? name,
    Set<String> path,
  ) {
    name = book.nameOf(node.key) ?? name;
    void end(List<HabitStep> steps) {
      // Réponses adverses les plus jouées d'abord : le premier chemin qui
      // mène à la position de [via] est le plus fréquent, les suivants le
      // rejoignent par un autre ordre de coups.
      if (via == null || !ended.add(via.childKey)) return;
      final games = reaching[via.childKey]!.toList();
      final score = games.fold<double>(0, (sum, g) => sum + g.score) / games.length;
      variants.add(OpeningVariant(line: line, name: name, games: games, score: score, steps: steps));
    }

    final moves = node.moves;
    if (node.position.turn != color) {
      final replies = moves.where((m) => m.count >= threshold && !path.contains(m.childKey)).toList();
      if (replies.isEmpty) return end(steps);
      for (final reply in replies) {
        walk(tree.node(reply.childKey)!, [...line, reply.san], steps, reply, name, {...path, reply.childKey});
      }
      return;
    }

    final reached = moves.fold<int>(0, (sum, m) => sum + m.count);
    if (reached < threshold) return end(steps);
    final played = moves.first;
    final star = repertoire?.lookup(color, node.key)?.san;
    final reference = star ?? played.san;
    final step = HabitStep(
      node: node,
      line: line,
      reached: reached,
      played: played,
      alternative: moves.length > 1 ? moves[1] : null,
      reference: reference,
      status: reference != played.san
          ? HabitStatus.offRepertoire
          : (played.count * 100 / reached).round() < (minShare * 100).round()
              ? HabitStatus.hesitant
              : HabitStatus.known,
    );
    final next = node.move(reference);
    if (next == null || path.contains(next.childKey)) return end([...steps, step]);
    walk(
      tree.node(next.childKey)!,
      [...line, reference],
      [...steps, step],
      via ?? next,
      name,
      {...path, next.childKey},
    );
  }

  walk(tree.root, const [], const [], null, null, {tree.rootKey});

  final byFamily = <String, List<OpeningVariant>>{};
  for (final variant in variants) {
    byFamily.putIfAbsent(variant.name?.family ?? unnamedFamily, () => []).add(variant);
  }
  final families = [
    for (final entry in byFamily.entries)
      OpeningFamily(entry.key, entry.value..sort((a, b) => b.count.compareTo(a.count))),
  ]..sort((a, b) => b.count.compareTo(a.count));
  return OpeningReport(families, threshold);
}
