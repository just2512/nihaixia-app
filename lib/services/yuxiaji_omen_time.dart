/// Shared App-local time-slot calculation for the Yu Xia Ji folk-text lookup.
/// This is a calendar lookup, not a medical detector or a health assessment.
int shiChenIndexOf(DateTime localTime) =>
    ((localTime.hour + 1) ~/ 2) % 12;

/// Time-slot label used by both the existing screen and the assistant executor.
String shiChenLabel(int index) {
  const names = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
  final start = (index * 2 + 23) % 24;
  final startLabel = '$start:00'.padLeft(5, '0');
  final endHour = (start + 2) % 24;
  final endLabel = endHour == 1 ? '00:59' : '${endHour - 1}:59';
  return '${names[index]}时 $startLabel–$endLabel';
}
