import 'dart:io';

enum ScheduleKind { record, remind }

/// A recording or a reminder planned from the guide.
class ScheduledItem {
  final String id;
  final ScheduleKind kind;
  final String channelId, channelName, source, title;
  final String url; // stored without credentials; AppState restores them on load
  final DateTime start, stop;
  const ScheduledItem({
    required this.id,
    required this.kind,
    required this.channelId,
    required this.channelName,
    required this.source,
    required this.url,
    required this.title,
    required this.start,
    required this.stop,
  });

  ScheduledItem copyWith({String? url}) => ScheduledItem(
        id: id,
        kind: kind,
        channelId: channelId,
        channelName: channelName,
        source: source,
        url: url ?? this.url,
        title: title,
        start: start,
        stop: stop,
      );

  Map<String, dynamic> toJson({String Function(String url)? scrub}) => {
        'id': id,
        'kind': kind.index,
        'ch': channelId,
        'chName': channelName,
        'src': source,
        'url': scrub != null ? scrub(url) : url,
        'title': title,
        'start': start.millisecondsSinceEpoch,
        'stop': stop.millisecondsSinceEpoch,
      };

  factory ScheduledItem.fromJson(Map<String, dynamic> j) => ScheduledItem(
        id: j['id'] as String,
        kind: ScheduleKind.values[j['kind'] as int],
        channelId: j['ch'] as String,
        channelName: j['chName'] as String,
        source: j['src'] as String? ?? '',
        url: j['url'] as String,
        title: j['title'] as String,
        start: DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
        stop: DateTime.fromMillisecondsSinceEpoch(j['stop'] as int),
      );
}

/// What to do right now about the scheduled items.
class SchedulePlan {
  final List<ScheduledItem> startRecording = [], stopRecording = [], remind = [], expired = [];
  bool get isEmpty => startRecording.isEmpty && stopRecording.isEmpty && remind.isEmpty && expired.isEmpty;
}

const kRecordLeadIn = Duration(minutes: 1); // start a bit early
const kRecordLeadOut = Duration(minutes: 2); // and finish a bit late: guides are never exact
const kRemindBefore = Duration(minutes: 2);
const kRemindGrace = Duration(minutes: 5);

/// Pure decision function (no I/O), so the timing rules can be tested.
/// [recording] and [notified] hold the ids already started / already announced.
SchedulePlan planSchedule(List<ScheduledItem> items, DateTime now, {required Set<String> recording, required Set<String> notified}) {
  final plan = SchedulePlan();
  for (final it in items) {
    if (it.kind == ScheduleKind.record) {
      final from = it.start.subtract(kRecordLeadIn), to = it.stop.add(kRecordLeadOut);
      if (recording.contains(it.id)) {
        if (!now.isBefore(to)) plan.stopRecording.add(it);
      } else if (!now.isBefore(to)) {
        plan.expired.add(it); // app was closed / missed it
      } else if (!now.isBefore(from)) {
        plan.startRecording.add(it);
      }
    } else {
      if (!now.isBefore(it.start.add(kRemindGrace)) || !now.isBefore(it.stop)) {
        plan.expired.add(it);
      } else if (!notified.contains(it.id) && !now.isBefore(it.start.subtract(kRemindBefore))) {
        plan.remind.add(it);
      }
    }
  }
  return plan;
}

abstract class Recorder {
  String? get path;
  Future<void> start(String url, String outPath);
  Future<void> stop();
}

/// Where a recording is saved: Videos\Lumora Recordings\(channel)_(title)_(yyyymmdd_hhmm).ts
String recordingFileFor(String channel, String title, DateTime start) {
  String safe(String s) => s.replaceAll(RegExp(r'[^\w\- ]+', unicode: true), '_').trim();
  final home = Platform.environment['USERPROFILE'] ?? Directory.current.path;
  final dir = Directory('$home${Platform.pathSeparator}Videos${Platform.pathSeparator}Lumora Recordings');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${start.year}${two(start.month)}${two(start.day)}_${two(start.hour)}${two(start.minute)}';
  return '${dir.path}${Platform.pathSeparator}${safe(channel)}_${safe(title)}_$stamp.ts';
}