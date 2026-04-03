import 'package:flutter_test/flutter_test.dart';
import 'package:nomade_mobile/models/turn_timeline.dart';

void main() {
  test('timeline merges started, delta and completed command execution', () {
    final timeline = TurnTimeline(turnId: 'turn-1');
    final item = timeline.upsertItem(
      itemId: 'cmd-1',
      itemType: 'commandExecution',
    );

    item.applyStarted(
      itemType: 'commandExecution',
      payload: {
        'command': 'npm run build',
        'status': 'inProgress',
      },
    );
    item.mergeDelta(stream: 'commandExecution', delta: 'building...\n');
    item.applyCompleted(
      itemType: 'commandExecution',
      payload: {
        'status': 'completed',
        'exitCode': 0,
      },
    );

    expect(item.status, TurnTimelineItemStatus.completed);
    expect(item.command, 'npm run build');
    expect(item.exitCode, 0);
    expect(item.aggregatedOutput, contains('building...'));
  });

  test('timeline status parser supports declined and failed', () {
    expect(
      timelineStatusFromRaw('declined'),
      TurnTimelineItemStatus.declined,
    );
    expect(
      timelineStatusFromRaw('error'),
      TurnTimelineItemStatus.failed,
    );
    expect(
      timelineStatusFromRaw('inProgress'),
      TurnTimelineItemStatus.inProgress,
    );
  });
}
