import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../services/scheduler.dart';
import '../theme.dart';

class ScheduledScreen extends StatelessWidget {
  const ScheduledScreen({super.key});

  String _when(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(context.tr('scheduled'))),
      body: Container(
        decoration: const BoxDecoration(gradient: kBackdrop),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(context.tr('scheduled_hint'), style: const TextStyle(color: kMuted)),
              ),
              Expanded(
                child: s.scheduled.isEmpty
                    ? Center(child: Text(context.tr('scheduled_empty'), style: const TextStyle(color: kMuted)))
                    : ListView(children: [
                        for (final it in s.scheduled)
                          Card(
                            child: ListTile(
                              leading: Icon(
                                s.isRecordingNow(it.id)
                                    ? Icons.fiber_manual_record
                                    : (it.kind == ScheduleKind.record ? Icons.videocam : Icons.notifications_active),
                                color: s.isRecordingNow(it.id) ? Colors.redAccent : kEmerald,
                              ),
                              title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${it.channelName} · ${_when(it.start)} – ${_when(it.stop)} · '
                                  '${context.tr(s.isRecordingNow(it.id) ? 'sched_recording' : (it.kind == ScheduleKind.record ? 'sched_kind_record' : 'sched_kind_remind'))}'),
                              trailing: IconButton(
                                tooltip: context.tr('sched_remove'),
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => s.removeScheduled(it.id),
                              ),
                            ),
                          ),
                      ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
