import 'ziwuliuzhu_engine.dart' as eng;

/// Shared deterministic result composer for the legacy ZiWuLiuZhu page and
/// the unified assistant. All GanZhi/open-point calculations remain in the
/// existing ziwuliuzhu_engine; this class only combines its outputs with the
/// page's established NaZi reference tables.
class ZiWuLiuZhuCalculationResult {
  const ZiWuLiuZhuCalculationResult({
    required this.at,
    required this.dayGanZhi,
    required this.hourGanZhi,
    required this.shichen,
    required this.timeRange,
    required this.meridian,
    required this.benXue,
    required this.dayOrgan,
    required this.wuMenInfo,
    required this.najiaText,
    required this.lingguiText,
    required this.feitengText,
    required this.values,
    required this.summary,
  });

  final DateTime at;
  final String dayGanZhi;
  final String hourGanZhi;
  final String shichen;
  final String timeRange;
  final String meridian;
  final String benXue;
  final String dayOrgan;
  final String wuMenInfo;
  final String najiaText;
  final String lingguiText;
  final String feitengText;
  final Map<String, String> values;
  final String summary;
}

class ZiWuLiuZhuCalculationService {
  static const tianGan = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
  static const diZhi = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];

  static const ganToOrgan = {
    '甲': '胆', '乙': '肝', '丙': '小肠', '丁': '心', '戊': '胃',
    '己': '脾', '庚': '大肠', '辛': '肺', '壬': '膀胱', '癸': '肾',
  };

  static const zhiToMeridian = {
    '子': ('胆经', '23:00–01:00'),
    '丑': ('肝经', '01:00–03:00'),
    '寅': ('肺经', '03:00–05:00'),
    '卯': ('大肠经', '05:00–07:00'),
    '辰': ('胃经', '07:00–09:00'),
    '巳': ('脾经', '09:00–11:00'),
    '午': ('心经', '11:00–13:00'),
    '未': ('小肠经', '13:00–15:00'),
    '申': ('膀胱经', '15:00–17:00'),
    '酉': ('肾经', '17:00–19:00'),
    '戌': ('心包经', '19:00–21:00'),
    '亥': ('三焦经', '21:00–23:00'),
  };

  // Preserve the exact NaZi tables and wording used by the legacy screen.
  static const benXueByMeridian = {
    '胆经': '临泣', '肝经': '大敦', '小肠经': '阳谷', '心经': '少府',
    '胃经': '足三里', '脾经': '太白', '大肠经': '商阳', '肺经': '经渠',
    '膀胱经': '通谷', '肾经': '阴谷', '心包经': '劳宫', '三焦经': '支沟',
  };

  static const wuMen = [
    ('甲', '己', '土', '临泣+太白'),
    ('乙', '庚', '金', '大敦+商阳'),
    ('丙', '辛', '水', '阳谷+经渠'),
    ('丁', '壬', '木', '少府+通谷'),
    ('戊', '癸', '火', '足三里+阴谷'),
  ];

  static String formatLocalAt(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-${two(value.month)}-${two(value.day)}T${two(value.hour)}:${two(value.minute)}';
  }

  /// Strictly accepts a local wall-clock timestamp, without an offset or Z.
  /// The App supplies this value; the executor never guesses a time zone.
  static DateTime? parseLocalAt(String value) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$',
    ).firstMatch(value);
    if (match == null) return null;
    final parts = List<int>.generate(
      5,
      (index) => int.parse(match.group(index + 1)!),
    );
    final year = parts[0], month = parts[1], day = parts[2];
    final hour = parts[3], minute = parts[4];
    if (year < 1900 || year > 2100 ||
        month < 1 || month > 12 ||
        day < 1 || hour < 0 || hour > 23 ||
        minute < 0 || minute > 59) {
      return null;
    }
    final parsed = DateTime(year, month, day, hour, minute);
    if (parsed.year != year ||
        parsed.month != month ||
        parsed.day != day ||
        parsed.hour != hour ||
        parsed.minute != minute ||
        parsed.isUtc) {
      return null;
    }
    return parsed;
  }

  static int shichenIndex(DateTime value) {
    final minutes = value.hour * 60 + value.minute;
    if (minutes >= 1380 || minutes < 60) return 0;
    if (minutes < 180) return 1;
    if (minutes < 300) return 2;
    if (minutes < 420) return 3;
    if (minutes < 540) return 4;
    if (minutes < 660) return 5;
    if (minutes < 780) return 6;
    if (minutes < 900) return 7;
    if (minutes < 1020) return 8;
    if (minutes < 1140) return 9;
    if (minutes < 1260) return 10;
    return 11;
  }

  static String benXue(String meridian) => benXueByMeridian[meridian] ?? '';

  static String wuMenInfo(String gan) {
    for (final (a, b, element, acupoints) in wuMen) {
      if (gan == a || gan == b) return '$a$b合化$element（$acupoints）';
    }
    return '';
  }

  static ZiWuLiuZhuCalculationResult calculate(DateTime at) {
    if (at.isUtc || at.year < 1900 || at.year > 2100) {
      throw ArgumentError('计算时间必须是 App 设备本地时间，范围为 1900–2100 年。');
    }

    final gz = eng.calcDayGanZhi(at);
    final hour = eng.calcHourGanZhi(gz.dayGan, at.hour, at.minute);
    final dayGan = eng.ganName(gz.dayGan);
    final dayZhi = eng.zhiName(gz.dayZhi);
    final hourGan = eng.ganName(hour.hourGan);
    final hourZhi = eng.zhiName(hour.hourZhi);
    final shichen = diZhi[hour.hourZhi];
    final meridianInfo = zhiToMeridian[shichen];
    if (meridianInfo == null) {
      throw StateError('子午流注时辰经络映射缺失：$shichen');
    }
    final (meridian, timeRange) = meridianInfo;
    final point = benXue(meridian);
    final organ = ganToOrgan[dayGan];
    if (point.isEmpty || organ == null) {
      throw StateError('子午流注纳子法参考数据不完整。');
    }
    final fiveChange = wuMenInfo(dayGan);

    final open = eng.najiaOpen(gz.dayGan, hour.hourGan, hour.hourZhi);
    final isHeRi = open == null;
    final najia = open ?? eng.najiaHeRi(gz.dayGan, hour.hourGan, hour.hourZhi);
    final najiaText = najia == null
        ? '当前时间无正开穴，也无合日互用取穴。'
        : '${najia['point'] ?? 'MISSING'}，${najia['meridian'] ?? 'MISSING'}，'
            '${najia['type'] ?? 'MISSING'}'
            '${najia['yuan'] == null ? '' : '；返本还原取原穴 ${najia['yuan']}'}。';

    final linggui = eng.lingguiOpen(
      gz.dayGan,
      gz.dayZhi,
      hour.hourGan,
      hour.hourZhi,
    );
    final rawGua = linggui['gua'];
    if (rawGua is! List<String> || rawGua.length != 3 ||
        linggui['peidui'] is! String ||
        linggui['peiduiMai'] is! String) {
      throw StateError('灵龟八法返回结构不完整。');
    }
    final gua = rawGua;
    final lingguiNote = linggui['note'] is String &&
            (linggui['note'] as String).isNotEmpty
        ? linggui['note'] as String
        : '无特殊处理';
    final lingguiText = '${gua[0]}卦，主穴 ${gua[1]}（${gua[2]}），'
        '配穴 ${linggui['peidui']}（${linggui['peiduiMai']}）；'
        '$lingguiNote。';

    final feiteng = eng.feitengOpen(hour.hourGan);
    final feitengText = feiteng == null
        ? '当前时干无对应飞腾八法取穴。'
        : '${feiteng[0]}卦，开穴 ${feiteng[1]}。';

    String two(int n) => n.toString().padLeft(2, '0');
    final dateText = '${at.year.toString().padLeft(4, '0')}-${two(at.month)}-${two(at.day)}';
    final timeText = '${two(at.hour)}:${two(at.minute)}';
    final dayGanZhi = '$dayGan$dayZhi';
    final hourGanZhi = '$hourGan$hourZhi';
    final naZi = '时辰 $shichen（$timeRange），对应$meridian，本穴 $point；'
        '日干 $dayGan 对应$organ，$fiveChange。';
    final najiaMethodText = najia == null
        ? '无正开穴，也无合日互用取穴。'
        : '${isHeRi ? '合日互用' : '纳甲正开穴'}：$najiaText';

    final summary = [
      '中医时辰开穴计算结果',
      '计算时间：$dateText $timeText（设备本地时间）',
      '日干支：$dayGanZhi；时干支：$hourGanZhi。',
      '纳子法：$naZi',
      '纳甲法：$najiaText',
      '灵龟八法：$lingguiText',
      '飞腾八法：$feitengText',
      '计算口径：使用 App 内置子午流注计算引擎；日干支默认经纬度 120E/30N，子时按 23:00 换日。结果为计算输出，不代表个体诊疗建议。',
    ].join('\n');

    final values = <String, String>{
      '计算时间': '$dateText $timeText（设备本地时间）',
      '日干支': dayGanZhi,
      '时干支': hourGanZhi,
      '时辰': shichen,
      '时辰时间范围': timeRange,
      '对应经络': meridian,
      '纳子法本穴': point,
      '日干对应脏腑': '$dayGan → $organ',
      '五门十变': fiveChange,
      '纳甲法': najiaMethodText,
      if (najia != null) '纳甲穴位': najia['point'] ?? 'MISSING',
      if (najia != null) '纳甲经络': najia['meridian'] ?? 'MISSING',
      if (najia != null) '纳甲穴性': najia['type'] ?? 'MISSING',
      if (najia?['yuan'] != null) '返本还原原穴': najia!['yuan']!,
      '灵龟八法': lingguiText,
      '灵龟卦': gua[0],
      '灵龟主穴': gua[1],
      '灵龟主脉': gua[2],
      '灵龟配穴': linggui['peidui'] as String,
      '灵龟配脉': linggui['peiduiMai'] as String,
      '灵龟计算步骤': linggui['step'] as String? ?? '',
      '飞腾八法': feitengText,
      if (feiteng != null) '飞腾卦': feiteng[0],
      if (feiteng != null) '飞腾开穴': feiteng[1],
      '计算口径': '本地设备时间；默认经度 120E/纬度 30N；子时 23:00 换日；未启用真太阳时。',
      '结果性质': '传统子午流注时辰开穴计算输出，不是个体诊断或治疗建议。',
    };

    return ZiWuLiuZhuCalculationResult(
      at: at,
      dayGanZhi: dayGanZhi,
      hourGanZhi: hourGanZhi,
      shichen: shichen,
      timeRange: timeRange,
      meridian: meridian,
      benXue: point,
      dayOrgan: '$dayGan → $organ',
      wuMenInfo: fiveChange,
      najiaText: najiaText,
      lingguiText: lingguiText,
      feitengText: feitengText,
      values: Map.unmodifiable(values),
      summary: summary,
    );
  }
}
