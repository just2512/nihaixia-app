/// 医案原始来源账本。内部序号只用于 App 数据定位，不得充当原始文献页码或病例编号。
///
/// 未经纸本/影印本核对的字段统一为 MISSING；不能从病例摘要、讲稿或文件行号推断出处。
class MedicalCaseSourceLedger {
  const MedicalCaseSourceLedger({
    this.sourceTitle = 'MISSING',
    this.edition = 'MISSING',
    this.volume = 'MISSING',
    this.page = 'MISSING',
    this.passage = 'MISSING',
    this.variant = 'MISSING',
    this.verificationStatus = 'MISSING',
  });

  final String sourceTitle;
  final String edition;
  final String volume;
  final String page;
  final String passage;
  final String variant;

  /// 仅允许 MISSING / PENDING / VERIFIED；VERIFIED 仍须满足完整定位字段。
  final String verificationStatus;

  static const missing = MedicalCaseSourceLedger();

  static const requiredLocatorFields = <String>[
    'sourceTitle',
    'edition',
    'volume',
    'page',
    'passage',
  ];

  bool get hasCompleteLocator =>
      requiredLocatorFields.every((field) => valueOf(field) != 'MISSING');

  bool get isVerified =>
      verificationStatus == 'VERIFIED' && hasCompleteLocator;

  String valueOf(String field) => switch (field) {
        'sourceTitle' => sourceTitle,
        'edition' => edition,
        'volume' => volume,
        'page' => page,
        'passage' => passage,
        'variant' => variant,
        _ => 'MISSING',
      };

  List<String> get missingFields => [
        if (sourceTitle == 'MISSING') '原始书名/病例来源',
        if (edition == 'MISSING') '版本/底本',
        if (volume == 'MISSING') '卷次',
        if (page == 'MISSING') '页码',
        if (passage == 'MISSING') '篇章/病例标题',
      ];

  String get status => isVerified
      ? 'VERIFIED'
      : verificationStatus == 'PENDING'
          ? 'PENDING'
          : 'MISSING';

  String toDisplayText() => [
        '原始书名/病例来源：$sourceTitle',
        '版本/底本：$edition',
        '卷次：$volume',
        '页码：$page',
        '篇章/病例标题：$passage',
        '异文记录：$variant',
        '核验状态：$status',
        if (missingFields.isNotEmpty) '缺失字段：${missingFields.join('、')}',
        '说明：内部医案序号不等于原始来源定位。',
      ].join('\\n');

  Map<String, String> toJson() => {
        'sourceTitle': sourceTitle,
        'edition': edition,
        'volume': volume,
        'page': page,
        'passage': passage,
        'variant': variant,
        'verificationStatus': status,
      };

  factory MedicalCaseSourceLedger.fromJson(Map<String, dynamic> json) {
    String read(String key) {
      final value = json[key]?.toString().trim();
      return value == null || value.isEmpty ? 'MISSING' : value;
    }

    final requestedStatus = read('verificationStatus');
    return MedicalCaseSourceLedger(
      sourceTitle: read('sourceTitle'),
      edition: read('edition'),
      volume: read('volume'),
      page: read('page'),
      passage: read('passage'),
      variant: read('variant'),
      verificationStatus: requestedStatus == 'VERIFIED' ||
              requestedStatus == 'PENDING'
          ? requestedStatus
          : 'MISSING',
    );
  }
}
