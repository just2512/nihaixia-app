/// 医案来源账本。内部序号只用于 App 数据定位，不得充当原始文献页码或病例编号。
///
/// verificationStatus 表示网页/原文内容核验；bibliographicLocatorStatus
/// 单独表示纸本/影印本版本、卷次、页码核验。两者不得互相推导。
class MedicalCaseSourceLedger {
  const MedicalCaseSourceLedger({
    this.sourceTitle = 'MISSING',
    this.edition = 'MISSING',
    this.volume = 'MISSING',
    this.page = 'MISSING',
    this.passage = 'MISSING',
    this.originalExcerpt = 'MISSING',
    this.applicability = 'MISSING',
    this.variant = 'MISSING',
    this.verificationStatus = 'MISSING',
    this.bibliographicLocatorStatus = 'MISSING',
  });

  final String sourceTitle;
  final String edition;
  final String volume;
  final String page;
  final String passage;
  final String originalExcerpt;
  final String applicability;
  final String variant;

  /// 网页/原文内容核验状态：MISSING / PENDING / VERIFIED。
  final String verificationStatus;

  /// 纸本/影印本版本、卷次、页码核验状态：MISSING / PENDING / VERIFIED。
  final String bibliographicLocatorStatus;

  static const missing = MedicalCaseSourceLedger();

  static const requiredSourceFields = <String>[
    'sourceTitle',
    'edition',
    'volume',
    'page',
    'passage',
    'originalExcerpt',
    'applicability',
  ];

  bool _hasValue(String value) {
    final normalized = value.trim();
    return normalized.isNotEmpty && normalized != 'MISSING';
  }

  bool get hasCompleteSourceLocator =>
      requiredSourceFields.every((field) => _hasValue(valueOf(field)));

  /// 兼容旧调用方：旧字段完整性只代表来源记录字段齐全，不代表纸本定位已核验。
  bool get hasCompleteLocator => hasCompleteSourceLocator;

  bool get isSourceVerified =>
      verificationStatus == 'VERIFIED' && hasCompleteSourceLocator;

  bool get hasCompleteBibliographicLocator =>
      _hasValue(sourceTitle) &&
      _hasValue(edition) &&
      !edition.contains('网页') &&
      _hasValue(volume) &&
      !volume.contains('不适用') &&
      _hasValue(page) &&
      !RegExp(r'^https?://', caseSensitive: false).hasMatch(page.trim()) &&
      _hasValue(passage) &&
      _hasValue(originalExcerpt) &&
      _hasValue(applicability);

  bool get isBibliographicLocatorVerified =>
      bibliographicLocatorStatus == 'VERIFIED' &&
      hasCompleteBibliographicLocator;

  /// 安全兼容旧调用方：isVerified 始终表示纸本/影印本定位已核验。
  bool get isVerified => isBibliographicLocatorVerified;

  String valueOf(String field) => switch (field) {
        'sourceTitle' => sourceTitle,
        'edition' => edition,
        'volume' => volume,
        'page' => page,
        'passage' => passage,
        'originalExcerpt' => originalExcerpt,
        'applicability' => applicability,
        'variant' => variant,
        _ => 'MISSING',
      };

  List<String> get missingFields => [
        if (!_hasValue(sourceTitle)) '原始书名/病例来源',
        if (!_hasValue(edition) || edition.contains('网页')) '纸本版本/底本',
        if (!_hasValue(volume) || volume.contains('不适用')) '纸本卷次',
        if (!_hasValue(page) ||
            RegExp(r'^https?://', caseSensitive: false).hasMatch(page.trim()))
          '纸本页码',
        if (!_hasValue(passage)) '篇章/病例标题',
        if (!_hasValue(originalExcerpt)) '原文片段',
        if (!_hasValue(applicability)) '适用条件',
      ];

  /// 纸本定位状态；网页原文 VERIFIED 不会自动升级为纸本 VERIFIED。
  String get status => !hasCompleteBibliographicLocator
      ? 'MISSING'
      : isVerified
          ? 'VERIFIED'
          : bibliographicLocatorStatus == 'PENDING'
              ? 'PENDING'
              : 'MISSING';

  /// 网页/原文内容核验状态；来源字段或适用条件缺失时必须保持 MISSING。
  String get sourceStatus => !hasCompleteSourceLocator
      ? 'MISSING'
      : isSourceVerified
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
        '原文片段：$originalExcerpt',
        '适用条件：$applicability',
        '异文记录：$variant',
        '核验状态：原文 $sourceStatus；纸本版本/卷页 $status',
        if (missingFields.isNotEmpty) '缺失字段：${missingFields.join('、')}',
        '说明：内部医案序号不等于原始来源定位。',
      ].join('\n');

  Map<String, String> toJson() => {
        'sourceTitle': sourceTitle,
        'edition': edition,
        'volume': volume,
        'page': page,
        'passage': passage,
        'originalExcerpt': originalExcerpt,
        'applicability': applicability,
        'variant': variant,
        'verificationStatus': sourceStatus,
        'bibliographicLocatorStatus': status,
      };

  factory MedicalCaseSourceLedger.fromJson(Map<String, dynamic> json) {
    String read(String key) {
      final value = json[key]?.toString().trim();
      return value == null || value.isEmpty ? 'MISSING' : value;
    }

    final sourceTitle = read('sourceTitle');
    final edition = read('edition');
    final volume = read('volume');
    final page = read('page');
    final passage = read('passage');
    final originalExcerpt = read('originalExcerpt');
    final applicability = read('applicability');
    final variant = read('variant');
    final requestedSourceStatus = read('verificationStatus');
    final requestedLocatorStatus = read('bibliographicLocatorStatus');

    final provisional = MedicalCaseSourceLedger(
      sourceTitle: sourceTitle,
      edition: edition,
      volume: volume,
      page: page,
      passage: passage,
      originalExcerpt: originalExcerpt,
      applicability: applicability,
      variant: variant,
      verificationStatus: requestedSourceStatus,
      bibliographicLocatorStatus: requestedLocatorStatus,
    );

    final sourceStatus = provisional.hasCompleteSourceLocator &&
            (requestedSourceStatus == 'VERIFIED' ||
                requestedSourceStatus == 'PENDING')
        ? requestedSourceStatus
        : 'MISSING';
    final locatorStatus = provisional.hasCompleteBibliographicLocator &&
            (requestedLocatorStatus == 'VERIFIED' ||
                requestedLocatorStatus == 'PENDING')
        ? requestedLocatorStatus
        : 'MISSING';

    return MedicalCaseSourceLedger(
      sourceTitle: sourceTitle,
      edition: edition,
      volume: volume,
      page: page,
      passage: passage,
      originalExcerpt: originalExcerpt,
      applicability: applicability,
      variant: variant,
      verificationStatus: sourceStatus,
      bibliographicLocatorStatus: locatorStatus,
    );
  }
}
