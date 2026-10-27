String fmtTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String fmtDuration(Duration d) {
  if (d.inMinutes >= 60) return '${d.inHours}時間${d.inMinutes % 60}分';
  return '${d.inMinutes}分';
}
