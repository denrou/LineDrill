import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/opening_report.dart';
import '../core/training.dart';
import 'play_controller.dart';
import 'providers.dart';

/// Profondeur d'analyse pour juger mes coups habituels, comme en partie corrigée.
const _depth = 12;

class HabitCheckState {
  const HabitCheckState({this.running = false, this.done = 0, this.total = 0, this.error});

  final bool running;

  /// Coups jugés depuis le lancement, sur [total] connus pour l'instant.
  final int done;
  final int total;

  /// Pourquoi la vérification s'est arrêtée avant la fin.
  final String? error;
}

/// Fait juger par Stockfish mes coups habituels du bilan des ouvertures.
class HabitCheckController extends Notifier<HabitCheckState> {
  @override
  HabitCheckState build() => const HabitCheckState();

  /// Juge les coups du bilan affiché qui ne l'ont pas encore été.
  Future<void> start() async {
    if (state.running) return;
    state = const HabitCheckState(running: true);
    var done = 0;
    try {
      final engine = await ref.read(engineProvider.future);
      await ref.read(habitChecksProvider.future);
      // Corriger un coup change la suite de sa variante : on repasse tant
      // que le bilan demande des avis. [asked] garantit que ça s'arrête.
      final asked = <String>{};
      while (true) {
        final todo = [
          for (final habit in ref.read(openingReportProvider)?.unchecked ?? const <UncheckedHabit>[])
            if (asked.add(habit.key)) habit,
        ];
        if (todo.isEmpty) break;
        final total = done + todo.length;
        state = HabitCheckState(running: true, done: done, total: total);
        final found = <String, HabitCheck>{};
        for (final habit in todo) {
          final verdict = await judgeMove(engine, habit.node.position, habit.move.move, depth: _depth);
          if (!ref.mounted) return;
          found[habit.key] = HabitCheck(verdict.quality, better: verdict.better);
          state = HabitCheckState(running: true, done: ++done, total: total);
        }
        await ref.read(habitChecksProvider.notifier).addAll(found);
        if (!ref.mounted) return;
      }
      state = HabitCheckState(done: done, total: done);
    } catch (e) {
      if (ref.mounted) state = HabitCheckState(done: done, total: done, error: '$e');
    }
  }
}

final habitCheckProvider = NotifierProvider<HabitCheckController, HabitCheckState>(HabitCheckController.new);
