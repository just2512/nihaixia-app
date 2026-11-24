import '../models/ai_context_ref.dart';
import '../models/acupoint_detail.dart';
import '../models/acupuncture.dart';
import '../models/formula.dart';
import '../models/herb.dart';
import '../data/formula_repository.dart';
import '../data/herb_repository.dart';
import '../data/acupoint_repository.dart';
import '../data/acupuncture_repository.dart';
import '../data/medical_case_data.dart';
import '../data/neijing_entries.dart';
import '../engine/diagnostic_rules.dart';
import 'ai_tool_result_snapshot.dart';
import 'assistant_chart_result_formatter.dart';
import 'ziwei_engine.dart';
import 'yunqi_tool_service.dart';
import 'almanac_tool_service.dart';
import 'bazi_context_snapshot.dart';
import 'yijing_tool_service.dart';
import 'meihua_tool_service.dart';
import 'xiaoliuren_tool_service.dart';
import 'huangdi_siji_result_context_executor.dart';
import 'huangdi_siji_tool_service.dart';
import 'yuxiaji_omen_result_context_executor.dart';
import 'yuxiaji_omen_tool_service.dart';
import 'chenggu_result_context_executor.dart';
import 'chenggu_tool_service.dart';
import 'shousheng_debt_result_context_executor.dart';
import 'shousheng_debt_tool_service.dart';
import 'sanshan_lingqian_result_context_executor.dart';
import 'sanshan_lingqian_tool_service.dart';
import 'dosage_result_context_executor.dart';
import 'dosage_tool_service.dart';
import 'dream_result_context_executor.dart';
import 'dream_tool_service.dart';
import 'guansha_result_context_executor.dart';
import 'guansha_tool_service.dart';
import 'solar_term_result_context_executor.dart';
import 'solar_term_tool_service.dart';
import 'ziwuliuzhu_tool_service.dart';
import 'ziwuliuzhu_calculation_service.dart';

/// Explicit resolution outcomes; only RESOLVED may be converted into a model prompt.
enum AiContextResolutionStatus {
  resolved,
  missing,
  unknown,
  stale,
  denied,
}

class AiContextResolution<T> {
  const AiContextResolution({
    required this.status,
    this.value,
    this.reason,
  });

  final AiContextResolutionStatus status;
  final T? value;
  final String? reason;

  bool get isResolved =>
      status == AiContextResolutionStatus.resolved && value != null;
}

/// Verified full tool result resolved from an immutable structured snapshot.
class AiResolvedToolResult {
  const AiResolvedToolResult._({
    required this.ref,
    required this.structuredSnapshot,
  });

  final AiContextRef ref;
  final Map<String, Object?> structuredSnapshot;
}

/// Verified field data resolved from one immutable structured tool snapshot.
class AiResolvedToolField {
  const AiResolvedToolField._({
    required this.ref,
    required this.fieldLabel,
    required this.fieldScope,
    required this.fieldValue,
    required this.fieldUnit,
    required this.structuredSnapshot,
  });

  final AiContextRef ref;
  final String fieldLabel;
  final Map<String, Object?> fieldScope;
  final List<Map<String, Object?>> fieldValue;
  final String fieldUnit;
  final Map<String, Object?> structuredSnapshot;
}

/// Resolves app-controlled field paths against a real engine result and
/// verifies that the full structured snapshot digest still matches its data.
/// Verified local knowledge entry resolved from the bundled deterministic data.
class AiResolvedKnowledgeEntry {
  const AiResolvedKnowledgeEntry._({
    required this.ref,
    required this.title,
    required this.content,
  });

  final AiContextRef ref;
  final String title;
  final Map<String, Object?> content;
}

class AiContextResolver {
  const AiContextResolver._();


  static const xiaoliurenModuleId = 'xiaoliuren';

  /// Re-resolves persisted knowledge-page anchors against the currently
  /// bundled deterministic source. Unsupported context kinds deliberately
  /// return UNKNOWN; a stored prompt is not treated as proof that its source
  /// is still current.
  static Future<AiContextResolution<AiResolvedKnowledgeEntry>>
      resolveKnowledgeReference({required AiContextRef ref}) async {
    switch (ref.kind) {
      case AiContextKind.formula:
        return resolveFormula(ref: ref);
      case AiContextKind.herb:
        return resolveHerb(ref: ref);
      case AiContextKind.caseRecord:
        return resolveMedicalCase(ref: ref);
      case AiContextKind.knowledgeEntry:
        if (ref.moduleId == meridianModuleId) {
          return resolveMeridianKnowledgeEntry(ref: ref);
        }
        if (ref.moduleId == acupointModuleId) {
          return resolveAcupoint(ref: ref);
        }
        if (ref.moduleId == acupunctureModuleId) {
          return resolveAcupunctureEntry(ref: ref);
        }
        break;
      case AiContextKind.classic:
        if (ref.moduleId == neijingModuleId) {
          return resolveNeijingEntry(ref: ref);
        }
        break;
      case AiContextKind.toolResult:
      case AiContextKind.fieldValue:
        break;
    }
    return const AiContextResolution<AiResolvedKnowledgeEntry>(
      status: AiContextResolutionStatus.unknown,
      reason: 'The persisted context kind or module has no current local source resolver.',
    );
  }

  static AiContextRef buildXiaoliurenResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final ruleVersion = structuredSnapshot['ruleVersion'];
    final input = structuredSnapshot['input'];
    final sourceIds = structuredSnapshot['sourceIds'];
    final arguments = input is Map ? input['arguments'] : null;
    final date = arguments is Map ? arguments['date'] : null;
    final hour = arguments is Map ? arguments['hour'] : null;
    final rule = arguments is Map ? arguments['rule'] : null;

    if (snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ruleVersion != XiaoliurenToolService.ruleVersion ||
        structuredSnapshot['capabilityId'] != xiaoliurenModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            XiaoliurenToolService.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'time' ||
        input['executionDate'] is! String ||
        arguments is! Map ||
        arguments.length != 3 ||
        date is! String ||
        hour is! String ||
        rule is! String ||
        !XiaoliurenToolService.hourBranches.contains(hour) ||
        !const {'common', 'duoneng'}.contains(rule) ||
        sourceIds is! List ||
        !sourceIds.contains(XiaoliurenToolService.sourceId) ||
        !sourceIds.contains(XiaoliurenToolService.ruleDataSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A Xiaoliuren context reference requires a complete, source-bound successful snapshot.',
      );
    }

    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: xiaoliurenModuleId,
      anchorId:
          'xiaoliuren:result:$snapshotId:date=$date:hour=$hour:rule=$rule',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion as String,
      sourceId: XiaoliurenToolService.sourceId,
      title: '小六壬起课结果（$rule）',
    );
  }

  static AiContextResolution<AiResolvedToolResult> resolveXiaoliurenToolResult({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != xiaoliurenModuleId ||
        ref.sourceId != XiaoliurenToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Xiaoliuren reference is incomplete or does not identify the local Xiaoliuren engine.',
      );
    }
    if (ref.ruleVersion != XiaoliurenToolService.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The Xiaoliuren engine, rule data or calendar conversion version no longer matches this result.',
      );
    }

    final anchorMatch = RegExp(
      r'^xiaoliuren:result:([0-9a-f]{64}):date=(\d{4}-\d{2}-\d{2}):hour=([^:]+):rule=(common|duoneng)$',
    ).firstMatch(ref.anchorId);
    final snapshotId = ref.snapshotId;
    if (anchorMatch == null ||
        snapshotId == null ||
        ref.anchorVersion != snapshotId ||
        anchorMatch.group(1) != snapshotId ||
        !XiaoliurenToolService.hourBranches.contains(anchorMatch.group(3))) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Xiaoliuren result anchor and snapshot identity do not agree.',
      );
    }

    final date = anchorMatch.group(2)!;
    final hour = anchorMatch.group(3)!;
    final rule = anchorMatch.group(4)!;
    if (ref.title != null && ref.title != '小六壬起课结果（$rule）') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Xiaoliuren result title does not match its selected rule.',
      );
    }

    final input = structuredSnapshot['input'];
    final argumentsValue = input is Map ? input['arguments'] : null;
    final executionDateValue = input is Map ? input['executionDate'] : null;
    final sourceIds = structuredSnapshot['sourceIds'];
    if (input is! Map ||
        input['method'] != 'time' ||
        argumentsValue is! Map ||
        argumentsValue.length != 3 ||
        argumentsValue.entries.any(
          (entry) => entry.key is! String || entry.value is! String,
        ) ||
        executionDateValue is! String ||
        structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['ruleVersion'] != XiaoliurenToolService.ruleVersion ||
        structuredSnapshot['resultSchemaVersion'] !=
            XiaoliurenToolService.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        structuredSnapshot['capabilityId'] != xiaoliurenModuleId ||
        sourceIds is! List ||
        !sourceIds.contains(XiaoliurenToolService.sourceId) ||
        !sourceIds.contains(XiaoliurenToolService.ruleDataSourceId)) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Xiaoliuren reference is not bound to a complete recorded execution input.',
      );
    }

    final arguments = <String, String>{
      for (final entry in argumentsValue.entries)
        entry.key as String: entry.value as String,
    };
    if (arguments['date'] != date ||
        arguments['hour'] != hour ||
        arguments['rule'] != rule) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The recorded Xiaoliuren arguments do not match the immutable result anchor.',
      );
    }

    final executionDate = DateTime.tryParse(executionDateValue);
    final normalizedExecutionDate = executionDate == null
        ? ''
        : '${executionDate.year.toString().padLeft(4, '0')}-'
            '${executionDate.month.toString().padLeft(2, '0')}-'
            '${executionDate.day.toString().padLeft(2, '0')}';
    if (normalizedExecutionDate != executionDateValue) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Xiaoliuren snapshot does not preserve a valid execution date.',
      );
    }

    try {
      final suppliedDigest =
          AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot);
      if (suppliedDigest != snapshotId) {
        return const AiContextResolution(
          status: AiContextResolutionStatus.stale,
          reason: 'The supplied Xiaoliuren result no longer matches its immutable snapshot digest.',
        );
      }

      final reconstructed = XiaoliurenToolService.executeWithSnapshot(
        arguments,
        now: executionDate,
      );
      final reconstructedSnapshot = reconstructed.structuredSnapshot;
      if (!reconstructed.succeeded ||
          reconstructedSnapshot == null ||
          reconstructedSnapshot['snapshotId'] != snapshotId) {
        return const AiContextResolution(
          status: AiContextResolutionStatus.stale,
          reason: 'The local Xiaoliuren engine reconstruction no longer matches this result.',
        );
      }

      return AiContextResolution(
        status: AiContextResolutionStatus.resolved,
        value: AiResolvedToolResult._(
          ref: ref,
          structuredSnapshot: reconstructedSnapshot,
        ),
      );
    } catch (_) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Xiaoliuren result could not be reconstructed and verified from the local engine.',
      );
    }
  }

  static const almanacModuleId = 'almanac';

  static AiContextRef buildAlmanacResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final ruleVersion = structuredSnapshot['ruleVersion'];
    final input = structuredSnapshot['input'];
    final sourceIds = structuredSnapshot['sourceIds'];
    if (snapshotId is! String ||
        snapshotId.isEmpty ||
        ruleVersion != AlmanacToolService.ruleVersion ||
        structuredSnapshot['capabilityId'] != almanacModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            AlmanacToolService.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['date'] is! String ||
        sourceIds is! List ||
        !sourceIds.contains(AlmanacToolService.sourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'An almanac context reference requires a complete, source-bound successful snapshot.',
      );
    }
    final date = input['date'] as String;
    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: almanacModuleId,
      anchorId: 'almanac:result:$snapshotId:date=$date',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion as String,
      sourceId: AlmanacToolService.sourceId,
      title: '每日黄历结果（$date）',
    );
  }

  static AiContextResolution<AiResolvedToolResult> resolveAlmanacToolResult({
    required AiContextRef ref,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != almanacModuleId ||
        ref.sourceId != AlmanacToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The almanac reference is incomplete or does not identify the local almanac engine.',
      );
    }
    if (ref.ruleVersion != AlmanacToolService.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The almanac engine, calendar package or local festival data version no longer matches this result.',
      );
    }

    const anchorPrefix = 'almanac:result:';
    final anchorRest = ref.anchorId.startsWith(anchorPrefix)
        ? ref.anchorId.substring(anchorPrefix.length)
        : '';
    final anchorParts = anchorRest.split(':date=');
    final snapshotId = ref.snapshotId;
    const hexDigits = '0123456789abcdef';
    if (anchorParts.length != 2 ||
        snapshotId == null ||
        snapshotId.length != 64 ||
        !snapshotId.split('').every(hexDigits.contains) ||
        ref.anchorVersion != snapshotId ||
        anchorParts[0] != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The almanac result anchor and snapshot identity do not agree.',
      );
    }

    final rawDate = anchorParts[1];
    final date = DateTime.tryParse(rawDate);
    final normalizedDate = date == null
        ? ''
        : [
            date.year.toString().padLeft(4, '0'),
            date.month.toString().padLeft(2, '0'),
            date.day.toString().padLeft(2, '0'),
          ].join('-');
    if (normalizedDate != rawDate) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The almanac result anchor does not contain a valid calendar date.',
      );
    }

    final expectedTitle = '每日黄历结果（$rawDate）';
    if (ref.title != null && ref.title != expectedTitle) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The almanac result title does not match its date anchor.',
      );
    }

    try {
      final snapshot = AlmanacToolService.createStructuredSnapshot(date!);
      if (snapshot['snapshotId'] != snapshotId) {
        return const AiContextResolution(
          status: AiContextResolutionStatus.stale,
          reason: 'The reconstructed almanac result no longer matches its immutable snapshot digest.',
        );
      }
      return AiContextResolution(
        status: AiContextResolutionStatus.resolved,
        value: AiResolvedToolResult._(
          ref: ref,
          structuredSnapshot: snapshot,
        ),
      );
    } catch (_) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The almanac result could not be reconstructed and verified from the local engine.',
      );
    }
  }

  static const ziWuLiuZhuModuleId = 'ziwu_liuzhu';

  static AiContextRef buildZiWuLiuZhuResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final ruleVersion = structuredSnapshot['ruleVersion'];
    final input = structuredSnapshot['input'];
    final sourceIds = structuredSnapshot['sourceIds'];
    final arguments = input is Map ? input['arguments'] : null;
    final at = arguments is Map ? arguments['at'] : null;

    if (snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ruleVersion != ZiWuLiuZhuToolService.ruleVersion ||
        structuredSnapshot['capabilityId'] != ziWuLiuZhuModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            ZiWuLiuZhuToolService.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'deviceLocalDateTime' ||
        arguments is! Map ||
        arguments.length != 1 ||
        at is! String ||
        sourceIds is! List ||
        !sourceIds.contains(ZiWuLiuZhuToolService.sourceId) ||
        !sourceIds.contains(ZiWuLiuZhuToolService.referenceSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A ZiWuLiuZhu context reference requires a complete, source-bound successful snapshot.',
      );
    }

    final execution = ZiWuLiuZhuToolService.executeWithSnapshot({'at': at});
    if (!execution.succeeded ||
        execution.structuredSnapshot?['snapshotId'] != snapshotId) {
      throw ArgumentError(
        'The ZiWuLiuZhu snapshot cannot be reproduced from its recorded local timestamp.',
      );
    }

    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ziWuLiuZhuModuleId,
      anchorId: 'ziwuliuzhu:result:$snapshotId:at=$at',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion as String,
      sourceId: ZiWuLiuZhuToolService.sourceId,
      title: '子午流注时辰开穴结果（$at）',
    );
  }

  static AiContextResolution<AiResolvedToolResult>
      resolveZiWuLiuZhuToolResult({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != ziWuLiuZhuModuleId ||
        ref.sourceId != ZiWuLiuZhuToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The ZiWuLiuZhu reference is incomplete or does not identify the local calculation engine.',
      );
    }
    if (ref.ruleVersion != ZiWuLiuZhuToolService.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The ZiWuLiuZhu engine, calculation tables or locked calendar dependency version no longer matches this result.',
      );
    }

    final match = RegExp(
      r'^ziwuliuzhu:result:([0-9a-f]{64}):at=(\d{4}-\d{2}-\d{2}T\d{2}:\d{2})$',
    ).firstMatch(ref.anchorId);
    final snapshotId = ref.snapshotId;
    if (match == null ||
        snapshotId == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ref.anchorVersion != snapshotId ||
        match.group(1) != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The ZiWuLiuZhu result anchor and snapshot identity do not agree.',
      );
    }

    final at = match.group(2)!;
    if (ZiWuLiuZhuCalculationService.parseLocalAt(at) == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The ZiWuLiuZhu anchor does not contain a valid local wall-clock time.',
      );
    }
    final expectedTitle = '子午流注时辰开穴结果（$at）';
    if (ref.title != null && ref.title != expectedTitle) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The ZiWuLiuZhu result title does not match its local timestamp anchor.',
      );
    }

    final input = structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final sourceIds = structuredSnapshot['sourceIds'];
    if (structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['ruleVersion'] != ZiWuLiuZhuToolService.ruleVersion ||
        structuredSnapshot['resultSchemaVersion'] !=
            ZiWuLiuZhuToolService.resultSchemaVersion ||
        structuredSnapshot['capabilityId'] != ziWuLiuZhuModuleId ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'deviceLocalDateTime' ||
        arguments is! Map ||
        arguments.length != 1 ||
        arguments['at'] != at ||
        sourceIds is! List ||
        !sourceIds.contains(ZiWuLiuZhuToolService.sourceId) ||
        !sourceIds.contains(ZiWuLiuZhuToolService.referenceSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The supplied ZiWuLiuZhu result or its provenance no longer matches the immutable snapshot digest.',
      );
    }

    final execution =
        ZiWuLiuZhuToolService.executeWithSnapshot({'at': at});
    if (!execution.succeeded || execution.structuredSnapshot == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The ZiWuLiuZhu result could not be reconstructed from its recorded local timestamp.',
      );
    }
    if (execution.structuredSnapshot!['snapshotId'] != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The local ZiWuLiuZhu calculation no longer matches this immutable result snapshot.',
      );
    }

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolResult._(
        ref: ref,
        structuredSnapshot: execution.structuredSnapshot!,
      ),
    );
  }


  static const ziWuLiuZhuMethodFields = <String, String>{
    'methods.naZi': 'naZi',
    'methods.naJia': 'naJia',
    'methods.lingGui': 'lingGui',
    'methods.feiTeng': 'feiTeng',
  };

  static const ziWuLiuZhuMethodLabels = <String, String>{
    'methods.naZi': '纳子法',
    'methods.naJia': '纳甲法',
    'methods.lingGui': '灵龟八法',
    'methods.feiTeng': '飞腾八法',
  };

  static const ziWuLiuZhuMethodUnits = <String, String>{
    'methods.naZi': '当前设备本地日期时间对应的纳子法 App 原始计算结果',
    'methods.naJia': '当前设备本地日期时间对应的纳甲法 App 原始计算结果；无适用开穴时保留 NOT_APPLICABLE',
    'methods.lingGui': '当前设备本地日期时间对应的灵龟八法 App 原始计算结果',
    'methods.feiTeng': '当前设备本地日期时间对应的飞腾八法 App 原始计算结果；无适用开穴时保留 NOT_APPLICABLE',
  };

  static AiContextRef buildZiWuLiuZhuResultFieldContextRef({
    required Map<String, Object?> structuredSnapshot,
    required String fieldPath,
  }) {
    final methodKey = ziWuLiuZhuMethodFields[fieldPath];
    final label = ziWuLiuZhuMethodLabels[fieldPath];
    if (methodKey == null || label == null) {
      throw ArgumentError.value(
        fieldPath,
        'fieldPath',
        'The requested ZiWuLiuZhu method field is not allowlisted.',
      );
    }

    // This factory is intentionally a lightweight anchor builder. The
    // complete snapshot integrity check belongs to
    // resolveZiWuLiuZhuResultField(), which the caller must invoke through
    // ContextResolutionGateway after entitlement authorization.
    final result = structuredSnapshot['result'];
    final methods = result is Map ? result['methods'] : null;
    final methodValue = methods is Map ? methods[methodKey] : null;
    final snapshotId = structuredSnapshot['snapshotId'];
    final input = structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final at = arguments is Map ? arguments['at'] : null;
    if (methodValue is! Map ||
        snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        arguments is! Map ||
        at is! String ||
        at.trim().isEmpty) {
      throw ArgumentError(
        'The ZiWuLiuZhu method anchor is missing its allowlisted field or stable snapshot identifiers.',
      );
    }
    return AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: ziWuLiuZhuModuleId,
      anchorId: 'ziwuliuzhu:result:$snapshotId:at=$at:field=$fieldPath',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ZiWuLiuZhuToolService.ruleVersion,
      sourceId: ZiWuLiuZhuToolService.sourceId,
      fieldPath: fieldPath,
      title: '子午流注 · $label',
    );
  }
  static AiContextResolution<AiResolvedToolField>
      resolveZiWuLiuZhuResultField({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.fieldValue ||
        normalized.isEmpty ||
        ref.moduleId != ziWuLiuZhuModuleId ||
        ref.sourceId != ZiWuLiuZhuToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The ZiWuLiuZhu field reference is incomplete or does not identify the local calculation engine.',
      );
    }
    if (ref.ruleVersion != ZiWuLiuZhuToolService.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The ZiWuLiuZhu engine or reference-table version no longer matches this method field.',
      );
    }

    final fieldPath = ref.fieldPath;
    final methodKey = fieldPath == null
        ? null
        : ziWuLiuZhuMethodFields[fieldPath];
    final label = fieldPath == null
        ? null
        : ziWuLiuZhuMethodLabels[fieldPath];
    final unit = fieldPath == null
        ? null
        : ziWuLiuZhuMethodUnits[fieldPath];
    if (fieldPath == null ||
        methodKey == null ||
        label == null ||
        unit == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The requested ZiWuLiuZhu method field is not allowlisted.',
      );
    }

    const anchorPrefix = 'ziwuliuzhu:result:';
    const timestampMarker = ':at=';
    const fieldMarker = ':field=';
    if (!ref.anchorId.startsWith(anchorPrefix) ||
        !ref.anchorId.contains(timestampMarker) ||
        !ref.anchorId.endsWith('$fieldMarker$fieldPath')) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The ZiWuLiuZhu method field anchor is malformed or does not match its allowlisted field path.',
      );
    }
    final timestampStart = ref.anchorId.indexOf(timestampMarker);
    final snapshotId = ref.anchorId.substring(
      anchorPrefix.length,
      timestampStart,
    );
    final at = ref.anchorId.substring(
      timestampStart + timestampMarker.length,
      ref.anchorId.length - fieldMarker.length - fieldPath.length,
    );
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ref.snapshotId != snapshotId ||
        ref.anchorVersion != snapshotId ||
        ref.title != '子午流注 · $label' ||
        ZiWuLiuZhuCalculationService.parseLocalAt(at) == null ||
        ref.anchorId !=
            'ziwuliuzhu:result:$snapshotId:at=$at:field=$fieldPath') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The ZiWuLiuZhu method field anchor, title, timestamp or snapshot identity do not agree.',
      );
    }

    final parentRef = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ziWuLiuZhuModuleId,
      anchorId: 'ziwuliuzhu:result:$snapshotId:at=$at',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: ZiWuLiuZhuToolService.sourceId,
      title: '子午流注时辰开穴结果（$at）',
    );
    final parentResolution = resolveZiWuLiuZhuToolResult(
      ref: parentRef,
      structuredSnapshot: structuredSnapshot,
    );
    final parent = parentResolution.value;
    if (!parentResolution.isResolved || parent == null) {
      return AiContextResolution(
        status: parentResolution.status,
        reason: parentResolution.reason ??
            'The parent ZiWuLiuZhu snapshot could not be verified.',
      );
    }

    final result = parent.structuredSnapshot['result'];
    final methods = result is Map ? result['methods'] : null;
    final methodValue = methods is Map ? methods[methodKey] : null;
    if (methodValue is! Map) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The verified ZiWuLiuZhu result does not contain the requested method data.',
      );
    }
    final input = parent.structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final executionDate = input is Map ? input['executionDate'] : null;
    if (arguments is! Map ||
        arguments['at'] != at ||
        executionDate != at.substring(0, 10)) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The ZiWuLiuZhu method field timestamp no longer matches the verified execution input.',
      );
    }

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolField._(
        ref: ref,
        fieldLabel: label,
        fieldScope: Map<String, Object?>.unmodifiable({
          'at': at,
          'executionDate': executionDate,
          'timeBasis': input is Map ? input['timeBasis'] : 'MISSING',
          'calculationRules': input is Map ? input['rules'] : 'MISSING',
        }),
        fieldValue: [
          Map<String, Object?>.unmodifiable({
            'fieldPath': fieldPath,
            'value': methodValue,
            'unit': unit,
          }),
        ],
        fieldUnit: unit,
        structuredSnapshot: parent.structuredSnapshot,
      ),
    );
  }

  static AiContextRef buildSolarTermResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final input = structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final term = arguments is Map ? arguments['term'] : null;
    final sourceIds = structuredSnapshot['sourceIds'];
    if (snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        structuredSnapshot['capabilityId'] !=
            SolarTermResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            SolarTermResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            SolarTermResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'explicitSolarTerm' ||
        arguments is! Map ||
        arguments.length != 1 ||
        term is! String ||
        !SolarTermToolService.termNames.contains(term) ||
        sourceIds is! List ||
        sourceIds.length != 2 ||
        !sourceIds.contains(SolarTermToolService.sourceId) ||
        !sourceIds.contains(SolarTermToolService.knowledgeSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A solar-term context reference requires a complete, source-bound successful snapshot.',
      );
    }
    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: SolarTermResultContextExecutor.moduleId,
      anchorId: 'solar-term:knowledge:$snapshotId:term=$term',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: SolarTermResultContextExecutor.ruleVersion,
      sourceId: SolarTermToolService.sourceId,
      title: '$term 节气知识条目',
    );
  }

  static Future<AiContextResolution<AiResolvedToolResult>>
      resolveSolarTermToolResult({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) async {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != SolarTermResultContextExecutor.moduleId ||
        ref.sourceId != SolarTermToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The solar-term reference is incomplete or does not identify the local solar-term service.',
      );
    }
    if (ref.ruleVersion != SolarTermResultContextExecutor.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The solar-term service, knowledge asset or locked calendar package version no longer matches this result.',
      );
    }

    final match = RegExp(
      r'^solar-term:knowledge:([0-9a-f]{64}):term=(.+)$',
    ).firstMatch(ref.anchorId);
    final snapshotId = ref.snapshotId;
    if (match == null ||
        snapshotId == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ref.anchorVersion != snapshotId ||
        match.group(1) != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The solar-term anchor and immutable snapshot identity do not agree.',
      );
    }
    final term = match.group(2)!;
    if (!SolarTermToolService.termNames.contains(term) ||
        ref.title != '$term 节气知识条目') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The solar-term anchor does not identify a supported knowledge entry.',
      );
    }

    final input = structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final sources = structuredSnapshot['sourceIds'];
    if (structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['capabilityId'] !=
            SolarTermResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            SolarTermResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            SolarTermResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'explicitSolarTerm' ||
        arguments is! Map ||
        arguments.length != 1 ||
        arguments['term'] != term ||
        sources is! List ||
        sources.length != 2 ||
        !sources.contains(SolarTermToolService.sourceId) ||
        !sources.contains(SolarTermToolService.knowledgeSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The solar-term knowledge snapshot or its provenance no longer matches its immutable digest.',
      );
    }

    final rebuilt = await SolarTermResultContextExecutor.executeWithSnapshot({
      'term': term,
    });
    if (!rebuilt.succeeded || rebuilt.structuredSnapshot == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The local solar-term entry is no longer available for verification.',
      );
    }
    if (rebuilt.structuredSnapshot!['snapshotId'] != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The local solar-term entry no longer matches this immutable snapshot.',
      );
    }

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolResult._(
        ref: ref,
        structuredSnapshot: rebuilt.structuredSnapshot!,
      ),
    );
  }

  static AiContextRef buildHuangdiSijiResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final input = structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final sourceIds = structuredSnapshot['sourceIds'];
    if (snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        structuredSnapshot['capabilityId'] !=
            HuangdiSijiResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            HuangdiSijiResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            HuangdiSijiResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'explicitBirthDateTime' ||
        arguments is! Map ||
        arguments.length != 2 ||
        arguments['birth_date'] is! String ||
        arguments['birth_time'] is! String ||
        sourceIds is! List ||
        sourceIds.length != 2 ||
        !sourceIds.contains(HuangdiSijiToolService.sourceId) ||
        !sourceIds.contains(HuangdiSijiToolService.dataSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A Huangdi Siji context reference requires a complete, source-bound successful snapshot.',
      );
    }
    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: HuangdiSijiResultContextExecutor.moduleId,
      anchorId: 'huangdi-siji:result:$snapshotId',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: HuangdiSijiResultContextExecutor.ruleVersion,
      sourceId: HuangdiSijiToolService.sourceId,
      title: '轩辕黄帝四季歌结果',
    );
  }

  static Future<AiContextResolution<AiResolvedToolResult>>
      resolveHuangdiSijiToolResult({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) async {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != HuangdiSijiResultContextExecutor.moduleId ||
        ref.sourceId != HuangdiSijiToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Huangdi Siji reference is incomplete or does not identify the local calculation source.',
      );
    }
    if (ref.ruleVersion != HuangdiSijiResultContextExecutor.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The Huangdi Siji executor, data asset or locked calendar package version no longer matches this result.',
      );
    }

    final match = RegExp(
      r'^huangdi-siji:result:([0-9a-f]{64})$',
    ).firstMatch(ref.anchorId);
    final snapshotId = ref.snapshotId;
    if (match == null ||
        snapshotId == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ref.anchorVersion != snapshotId ||
        match.group(1) != snapshotId ||
        ref.title != '轩辕黄帝四季歌结果') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Huangdi Siji anchor and immutable snapshot identity do not agree.',
      );
    }

    final input = structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final sources = structuredSnapshot['sourceIds'];
    if (structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['capabilityId'] !=
            HuangdiSijiResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            HuangdiSijiResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            HuangdiSijiResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'explicitBirthDateTime' ||
        arguments is! Map ||
        arguments.length != 2 ||
        arguments['birth_date'] is! String ||
        arguments['birth_time'] is! String ||
        sources is! List ||
        sources.length != 2 ||
        !sources.contains(HuangdiSijiToolService.sourceId) ||
        !sources.contains(HuangdiSijiToolService.dataSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The supplied Huangdi Siji result or its provenance no longer matches the immutable digest.',
      );
    }

    final rebuilt = await HuangdiSijiResultContextExecutor.executeWithSnapshot({
      'birth_date': arguments['birth_date'] as String,
      'birth_time': arguments['birth_time'] as String,
    });
    if (!rebuilt.succeeded || rebuilt.structuredSnapshot == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The local Huangdi Siji result could not be reconstructed from its recorded input.',
      );
    }
    if (rebuilt.structuredSnapshot!['snapshotId'] != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The local Huangdi Siji calculation no longer matches this immutable result.',
      );
    }

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolResult._(
        ref: ref,
        structuredSnapshot: rebuilt.structuredSnapshot!,
      ),
    );
  }

  static AiContextRef buildChengguResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final input = structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final sourceIds = structuredSnapshot['sourceIds'];
    final settings = input is Map ? input['settings'] : null;
    if (snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        structuredSnapshot['capabilityId'] !=
            ChengguResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            ChengguResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            ChengguResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'explicitBirthDateTime' ||
        settings is! Map ||
        settings['useTrueSolarTime'] is! bool ||
        settings['distinguishZiShi'] is! bool ||
        arguments is! Map ||
        arguments.length != 2 ||
        arguments['birth_date'] is! String ||
        arguments['birth_time'] is! String ||
        sourceIds is! List ||
        sourceIds.length != 2 ||
        !sourceIds.contains(ChengguToolService.sourceId) ||
        !sourceIds.contains(ChengguToolService.dataSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A Chenggu context reference requires a complete, source-bound successful snapshot.',
      );
    }
    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ChengguResultContextExecutor.moduleId,
      anchorId: 'chenggu:result:$snapshotId',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ChengguResultContextExecutor.ruleVersion,
      sourceId: ChengguToolService.sourceId,
      title: '袁天罡称骨结果',
    );
  }

  static Future<AiContextResolution<AiResolvedToolResult>>
      resolveChengguToolResult({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) async {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != ChengguResultContextExecutor.moduleId ||
        ref.sourceId != ChengguToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Chenggu reference is incomplete or does not identify the local calculation source.',
      );
    }
    if (ref.ruleVersion != ChengguResultContextExecutor.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The Chenggu executor, data asset or locked calendar package version no longer matches this result.',
      );
    }

    final match = RegExp(
      r'^chenggu:result:([0-9a-f]{64})$',
    ).firstMatch(ref.anchorId);
    final snapshotId = ref.snapshotId;
    if (match == null ||
        snapshotId == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ref.anchorVersion != snapshotId ||
        match.group(1) != snapshotId ||
        ref.title != '袁天罡称骨结果') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Chenggu anchor and immutable snapshot identity do not agree.',
      );
    }

    final input = structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final sources = structuredSnapshot['sourceIds'];
    final settings = input is Map ? input['settings'] : null;
    if (structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['capabilityId'] !=
            ChengguResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            ChengguResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            ChengguResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'explicitBirthDateTime' ||
        settings is! Map ||
        settings['useTrueSolarTime'] is! bool ||
        settings['distinguishZiShi'] is! bool ||
        arguments is! Map ||
        arguments.length != 2 ||
        arguments['birth_date'] is! String ||
        arguments['birth_time'] is! String ||
        sources is! List ||
        sources.length != 2 ||
        !sources.contains(ChengguToolService.sourceId) ||
        !sources.contains(ChengguToolService.dataSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The supplied Chenggu result or its provenance no longer matches the immutable digest.',
      );
    }

    final rebuilt = await ChengguResultContextExecutor.executeWithSnapshot({
      'birth_date': arguments['birth_date'] as String,
      'birth_time': arguments['birth_time'] as String,
    });
    if (!rebuilt.succeeded || rebuilt.structuredSnapshot == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The local Chenggu result could not be reconstructed from its recorded input.',
      );
    }
    if (rebuilt.structuredSnapshot!['snapshotId'] != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The local Chenggu calculation no longer matches this immutable result.',
      );
    }

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolResult._(
        ref: ref,
        structuredSnapshot: rebuilt.structuredSnapshot!,
      ),
    );
  }

  static AiContextRef buildShoushengDebtResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final input = structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final sources = structuredSnapshot['sourceIds'];
    final method = input is Map ? input['method'] : null;
    if (snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        structuredSnapshot['capabilityId'] !=
            ShoushengDebtResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            ShoushengDebtResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            ShoushengDebtResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        method is! String ||
        !ShoushengDebtToolService.methods.contains(method) ||
        arguments is! Map ||
        arguments.length != 3 ||
        arguments['birth_date'] is! String ||
        arguments['birth_time'] is! String ||
        arguments['method'] != method ||
        input['settings'] is! Map ||
        sources is! List ||
        sources.length != 2 ||
        sources[0] != ShoushengDebtToolService.sourceId ||
        sources[1] != (method == 'luku'
            ? ShoushengDebtToolService.lukuDataSourceId
            : ShoushengDebtToolService.wudouDataSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A Shousheng context reference requires a complete, source-bound successful snapshot.',
      );
    }
    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ShoushengDebtResultContextExecutor.moduleId,
      anchorId: 'shousheng-debt:result:$snapshotId:method=$method',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ShoushengDebtResultContextExecutor.ruleVersion,
      sourceId: ShoushengDebtToolService.sourceId,
      title: method == 'luku' ? '禄库受生经查询结果' : '五斗金章受生经查询结果',
    );
  }

  static Future<AiContextResolution<AiResolvedToolResult>>
      resolveShoushengDebtToolResult({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) async {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != ShoushengDebtResultContextExecutor.moduleId ||
        ref.sourceId != ShoushengDebtToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Shousheng reference is incomplete or does not identify the local lookup engine.',
      );
    }
    if (ref.ruleVersion != ShoushengDebtResultContextExecutor.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The Shousheng executor, source assets, Bazi engine, settings repository or locked package versions changed.',
      );
    }

    final match = RegExp(
      r'^shousheng-debt:result:([0-9a-f]{64}):method=(luku|wudou)$',
    ).firstMatch(ref.anchorId);
    final snapshotId = ref.snapshotId;
    if (match == null ||
        snapshotId == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ref.anchorVersion != snapshotId ||
        match.group(1) != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Shousheng anchor and immutable snapshot identity do not agree.',
      );
    }
    final method = match.group(2)!;
    final expectedTitle =
        method == 'luku' ? '禄库受生经查询结果' : '五斗金章受生经查询结果';
    if (ref.title != expectedTitle) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Shousheng title does not match its selected source system.',
      );
    }

    final input = structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final settings = input is Map ? input['settings'] : null;
    final sources = structuredSnapshot['sourceIds'];
    if (structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['capabilityId'] !=
            ShoushengDebtResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            ShoushengDebtResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            ShoushengDebtResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != method ||
        arguments is! Map ||
        arguments.length != 3 ||
        arguments['method'] != method ||
        arguments['birth_date'] is! String ||
        arguments['birth_time'] is! String ||
        settings is! Map ||
        settings['useTrueSolarTime'] is! bool ||
        settings['distinguishZiShi'] is! bool ||
        sources is! List ||
        sources.length != 2 ||
        sources[0] != ShoushengDebtToolService.sourceId ||
        sources[1] != (method == 'luku'
            ? ShoushengDebtToolService.lukuDataSourceId
            : ShoushengDebtToolService.wudouDataSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The supplied Shousheng result, settings or provenance no longer matches the immutable digest.',
      );
    }

    final rebuilt = await ShoushengDebtResultContextExecutor.executeWithSnapshot({
      'birth_date': arguments['birth_date'] as String,
      'birth_time': arguments['birth_time'] as String,
      'method': method,
    });
    if (!rebuilt.succeeded || rebuilt.structuredSnapshot == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The local Shousheng lookup could not be reconstructed from its recorded input.',
      );
    }
    if (rebuilt.structuredSnapshot!['snapshotId'] != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The local Shousheng lookup no longer matches this immutable result.',
      );
    }

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolResult._(
        ref: ref,
        structuredSnapshot: rebuilt.structuredSnapshot!,
      ),
    );
  }

  static AiContextRef buildYuxiajiOmenResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final input = structuredSnapshot['input'];
    final result = structuredSnapshot['result'];
    final at = input is Map ? input['at'] : null;
    final offset = input is Map ? input['utcOffsetMinutes'] : null;
    final arguments = input is Map ? input['arguments'] : null;
    final sources = structuredSnapshot['sourceIds'];
    final title = result is Map ? result['title'] : null;
    if (snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        structuredSnapshot['capabilityId'] !=
            YuxiajiOmenResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            YuxiajiOmenResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            YuxiajiOmenResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'deviceLocalDateTime' ||
        input['clockOwner'] != 'APP_DEVICE_LOCAL' ||
        at is! String ||
        DateTime.tryParse(at) == null ||
        DateTime.parse(at).isUtc ||
        offset is! int ||
        DateTime.parse(at).timeZoneOffset.inMinutes != offset ||
        arguments is! Map ||
        arguments.isNotEmpty ||
        sources is! List ||
        sources.length != 1 ||
        sources.single != YuxiajiOmenToolService.sourceId ||
        title is! String ||
        title.isEmpty ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A Yuxiaji context reference requires a complete device-local time snapshot with verified source provenance.',
      );
    }
    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: YuxiajiOmenResultContextExecutor.moduleId,
      anchorId: 'yuxiaji-omen:result:$snapshotId',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: YuxiajiOmenResultContextExecutor.ruleVersion,
      sourceId: YuxiajiOmenToolService.sourceId,
      title: title,
    );
  }

  static Future<AiContextResolution<AiResolvedToolResult>>
      resolveYuxiajiOmenToolResult({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) async {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != YuxiajiOmenResultContextExecutor.moduleId ||
        ref.sourceId != YuxiajiOmenToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: '玉匣灵兆引用不完整或不属于本地时辰文本来源。',
      );
    }
    if (ref.ruleVersion != YuxiajiOmenResultContextExecutor.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: '玉匣灵兆执行器、数据资产或时辰计算规则版本已变化。',
      );
    }

    final snapshotId = ref.snapshotId;
    if (snapshotId == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ref.anchorId != 'yuxiaji-omen:result:$snapshotId' ||
        ref.anchorVersion != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: '玉匣灵兆锚点与不可变快照身份不一致。',
      );
    }

    final input = structuredSnapshot['input'];
    final at = input is Map ? input['at'] : null;
    final offset = input is Map ? input['utcOffsetMinutes'] : null;
    final arguments = input is Map ? input['arguments'] : null;
    final sources = structuredSnapshot['sourceIds'];
    if (structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['capabilityId'] !=
            YuxiajiOmenResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            YuxiajiOmenResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            YuxiajiOmenResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'deviceLocalDateTime' ||
        input['clockOwner'] != 'APP_DEVICE_LOCAL' ||
        at is! String ||
        DateTime.tryParse(at) == null ||
        DateTime.parse(at).isUtc ||
        offset is! int ||
        arguments is! Map ||
        arguments.isNotEmpty ||
        sources is! List ||
        sources.length != 1 ||
        sources.single != YuxiajiOmenToolService.sourceId ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: '玉匣灵兆输入、来源或摘要与不可变快照不匹配。',
      );
    }

    final observedAt = DateTime.parse(at);
    if (observedAt.timeZoneOffset.inMinutes != offset) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: '设备时区偏移已变化，不能把历史本地时辰解释为当前时区结果。',
      );
    }
    final rebuilt = YuxiajiOmenResultContextExecutor.executeWithSnapshot(
      observedAt: observedAt,
    );
    if (!rebuilt.succeeded || rebuilt.structuredSnapshot == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: '无法按记录的设备本地时间重建玉匣灵兆文本。',
      );
    }
    if (rebuilt.structuredSnapshot!['snapshotId'] != snapshotId ||
        rebuilt.result.title != ref.title) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: '本地时辰重建结果与原始玉匣灵兆快照不一致。',
      );
    }

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolResult._(
        ref: ref,
        structuredSnapshot: rebuilt.structuredSnapshot!,
      ),
    );
  }

  static AiContextRef buildSanshanLingqianResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final input = structuredSnapshot['input'];
    final selectedSignId = input is Map ? input['selectedSignId'] : null;
    final arguments = input is Map ? input['arguments'] : null;
    final sourceIds = structuredSnapshot['sourceIds'];
    if (snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        structuredSnapshot['capabilityId'] !=
            SanshanLingqianResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            SanshanLingqianResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            SanshanLingqianResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'appRandomDraw' ||
        input['selectionOwner'] != 'APP_LOCAL_ONLY' ||
        selectedSignId is! int ||
        selectedSignId < 1 ||
        selectedSignId > 92 ||
        arguments is! Map ||
        arguments.isNotEmpty ||
        sourceIds is! List ||
        sourceIds.length != 1 ||
        sourceIds.single !=
            '${SanshanLingqianToolService.dataSourcePrefix}$selectedSignId' ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A Sanshan Lingqian context reference requires a complete, source-bound App draw snapshot.',
      );
    }
    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: SanshanLingqianResultContextExecutor.moduleId,
      anchorId: 'sanshan-lingqian:result:$snapshotId:sign=$selectedSignId',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: SanshanLingqianResultContextExecutor.ruleVersion,
      sourceId: '${SanshanLingqianToolService.dataSourcePrefix}$selectedSignId',
      title: '三山国王灵签结果（第$selectedSignId签）',
    );
  }

  static Future<AiContextResolution<AiResolvedToolResult>>
      resolveSanshanLingqianToolResult({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) async {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != SanshanLingqianResultContextExecutor.moduleId ||
        !ref.sourceId.startsWith(SanshanLingqianToolService.dataSourcePrefix)) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: '三山灵签引用不完整或不属于本地签谱来源。',
      );
    }
    if (ref.ruleVersion != SanshanLingqianResultContextExecutor.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: '三山灵签抽签执行器或本地签谱数据版本已变化。',
      );
    }

    final match = RegExp(
      r'^sanshan-lingqian:result:([0-9a-f]{64}):sign=(\d{1,2})$',
    ).firstMatch(ref.anchorId);
    final snapshotId = ref.snapshotId;
    final signId = match == null ? null : int.tryParse(match.group(2)!);
    if (match == null ||
        snapshotId == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ref.anchorVersion != snapshotId ||
        match.group(1) != snapshotId ||
        signId == null ||
        signId < 1 ||
        signId > 92 ||
        ref.sourceId !=
            '${SanshanLingqianToolService.dataSourcePrefix}$signId' ||
        ref.title != '三山国王灵签结果（第$signId签）') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: '三山灵签锚点、签号、来源与快照身份不一致。',
      );
    }

    final input = structuredSnapshot['input'];
    final selectedSignId = input is Map ? input['selectedSignId'] : null;
    final arguments = input is Map ? input['arguments'] : null;
    final sourceIds = structuredSnapshot['sourceIds'];
    if (structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['capabilityId'] !=
            SanshanLingqianResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            SanshanLingqianResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            SanshanLingqianResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'appRandomDraw' ||
        input['selectionOwner'] != 'APP_LOCAL_ONLY' ||
        selectedSignId != signId ||
        arguments is! Map ||
        arguments.isNotEmpty ||
        sourceIds is! List ||
        sourceIds.length != 1 ||
        sourceIds.single !=
            '${SanshanLingqianToolService.dataSourcePrefix}$signId' ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: '三山灵签结果、签号、来源或结构化摘要与不可变快照不匹配。',
      );
    }

    final rebuilt =
        await SanshanLingqianResultContextExecutor.executeForSignId(signId);
    if (!rebuilt.succeeded || rebuilt.structuredSnapshot == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: '无法从本地 92 签签谱重建已抽取签文。',
      );
    }
    if (rebuilt.structuredSnapshot!['snapshotId'] != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: '本地签谱重建结果与原始抽签快照不一致。',
      );
    }

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolResult._(
        ref: ref,
        structuredSnapshot: rebuilt.structuredSnapshot!,
      ),
    );
  }


  static AiContextRef buildDosageResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final input = structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final sourceIds = structuredSnapshot['sourceIds'];
    final result = structuredSnapshot['result'];
    final title = result is Map ? result['title'] : null;
    if (snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        structuredSnapshot['capabilityId'] !=
            DosageResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            DosageResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            DosageResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'explicitUnitConversion' ||
        arguments is! Map ||
        arguments.length != 3 ||
        arguments.keys.toSet().difference({'value', 'unit', 'standard'}).isNotEmpty ||
        arguments.values.any((value) => value is! String) ||
        DosageToolService.validateArguments(
          arguments.cast<String, String>(),
        ).isNotEmpty ||
        sourceIds is! List ||
        sourceIds.length != 2 ||
        sourceIds[0] != DosageToolService.sourceId ||
        sourceIds[1] != DosageToolService.factorsSourceId ||
        title != '经方度量衡单位换算' ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A dosage context reference requires a complete, source-bound successful unit-conversion snapshot.',
      );
    }
    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: DosageResultContextExecutor.moduleId,
      anchorId: 'dosage:result:$snapshotId',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: DosageResultContextExecutor.ruleVersion,
      sourceId: DosageToolService.sourceId,
      title: '经方度量衡换算结果',
    );
  }

  static Future<AiContextResolution<AiResolvedToolResult>>
      resolveDosageToolResult({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) async {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != DosageResultContextExecutor.moduleId ||
        ref.sourceId != DosageToolService.sourceId ||
        ref.title != '经方度量衡换算结果') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: '剂量单位换算引用不完整或来源不匹配。',
      );
    }
    if (ref.ruleVersion != DosageResultContextExecutor.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: '经方度量衡换算执行器或换算常数版本已变化。',
      );
    }

    final snapshotId = ref.snapshotId;
    if (snapshotId == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ref.anchorId != 'dosage:result:$snapshotId' ||
        ref.anchorVersion != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: '剂量单位换算锚点与不可变快照身份不一致。',
      );
    }

    final input = structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final sources = structuredSnapshot['sourceIds'];
    if (structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['capabilityId'] !=
            DosageResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            DosageResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            DosageResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'explicitUnitConversion' ||
        arguments is! Map ||
        arguments.length != 3 ||
        arguments.keys.toSet().difference({'value', 'unit', 'standard'}).isNotEmpty ||
        arguments.values.any((value) => value is! String) ||
        sources is! List ||
        sources.length != 2 ||
        sources[0] != DosageToolService.sourceId ||
        sources[1] != DosageToolService.factorsSourceId ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: '剂量换算输入、来源或结构化摘要与不可变快照不匹配。',
      );
    }

    final safeArguments = arguments.cast<String, String>();
    if (DosageToolService.validateArguments(safeArguments).isNotEmpty) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: '剂量换算参数不在 App 当前允许范围内。',
      );
    }
    final rebuilt = DosageResultContextExecutor.executeWithSnapshot(
      arguments: safeArguments,
    );
    if (!rebuilt.succeeded ||
        rebuilt.structuredSnapshot == null ||
        rebuilt.structuredSnapshot!['snapshotId'] != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: '本地单位换算重建结果与原始快照不一致。',
      );
    }

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolResult._(
        ref: ref,
        structuredSnapshot: rebuilt.structuredSnapshot!,
      ),
    );
  }


  static const yunqiModuleId = 'yunqi';

  static AiContextRef buildYunqiResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final ruleVersion = structuredSnapshot['ruleVersion'];
    final input = structuredSnapshot['input'];
    final sourceIds = structuredSnapshot['sourceIds'];
    if (snapshotId is! String ||
        snapshotId.isEmpty ||
        ruleVersion != YunQiToolService.ruleVersion ||
        structuredSnapshot['capabilityId'] != yunqiModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            YunQiToolService.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['date'] is! String ||
        sourceIds is! List ||
        !sourceIds.contains(YunQiToolService.sourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A YunQi context reference requires a complete, source-bound successful snapshot.',
      );
    }
    final date = input['date'] as String;
    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: yunqiModuleId,
      anchorId: 'yunqi:result:$snapshotId:date=$date',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion as String,
      sourceId: YunQiToolService.sourceId,
      title: '五运六气年度推算结果（$date）',
    );
  }

  static AiContextResolution<AiResolvedToolResult> resolveYunqiToolResult({
    required AiContextRef ref,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != yunqiModuleId ||
        ref.sourceId != YunQiToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YunQi reference is incomplete or does not identify the local YunQi engine.',
      );
    }
    if (ref.ruleVersion != YunQiToolService.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The YunQi engine or literature version no longer matches this result reference.',
      );
    }
    final anchorMatch = RegExp(
      r'^yunqi:result:([0-9a-f]{64}):date=(\d{4}-\d{2}-\d{2})$',
    ).firstMatch(ref.anchorId);
    final snapshotId = ref.snapshotId;
    if (anchorMatch == null ||
        snapshotId == null ||
        snapshotId.isEmpty ||
        ref.anchorVersion != snapshotId ||
        anchorMatch.group(1) != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YunQi result anchor and snapshot identity do not agree.',
      );
    }
    final rawDate = anchorMatch.group(2)!;
    final date = DateTime.tryParse(rawDate);
    final normalizedDate = date == null
        ? ''
        : '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
    if (normalizedDate != rawDate) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YunQi result anchor does not contain a valid calendar date.',
      );
    }
    final expectedTitle = '五运六气年度推算结果（$rawDate）';
    if (ref.title != null && ref.title != expectedTitle) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YunQi result title does not match its date anchor.',
      );
    }
    try {
      final snapshot = YunQiToolService.createStructuredSnapshot(date!);
      if (snapshot['snapshotId'] != snapshotId) {
        return const AiContextResolution(
          status: AiContextResolutionStatus.stale,
          reason: 'The reconstructed YunQi result no longer matches its immutable snapshot digest.',
        );
      }
      return AiContextResolution(
        status: AiContextResolutionStatus.resolved,
        value: AiResolvedToolResult._(
          ref: ref,
          structuredSnapshot: snapshot,
        ),
      );
    } catch (_) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YunQi result could not be reconstructed and verified from the local engine.',
      );
    }
  }


  static const _yunqiChartFieldTitles = <String, String>{
    'chart.wuxing': '运气五行图',
    'chart.wuyun': '五运图',
    'chart.liuqi': '六气图',
  };

  static const _yunqiChartFieldPaths = <String>{
    'chart.wuxing',
    'chart.wuyun',
    'chart.liuqi',
  };

  static AiContextRef buildYunqiChartFieldContextRef({
    required Map<String, Object?> structuredSnapshot,
    required String fieldPath,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final ruleVersion = structuredSnapshot['ruleVersion'];
    final input = structuredSnapshot['input'];
    final sourceIds = structuredSnapshot['sourceIds'];
    final result = structuredSnapshot['result'];
    final annualData = result is Map ? result['annualData'] : null;
    final selectedDateContext =
        result is Map ? result['selectedDateContext'] : null;
    if (snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ruleVersion != YunQiToolService.ruleVersion ||
        structuredSnapshot['capabilityId'] != yunqiModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            YunQiToolService.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['date'] is! String ||
        sourceIds is! List ||
        !sourceIds.contains(YunQiToolService.sourceId) ||
        annualData is! Map ||
        selectedDateContext is! Map ||
        !_yunqiChartFieldPaths.contains(fieldPath) ||
        _yunqiChartFieldValue(
              fieldPath: fieldPath,
              annualData: annualData,
              selectedDateContext: selectedDateContext,
            ) ==
            null ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A YunQi chart field reference requires a complete successful annual snapshot and an allowlisted chart path.',
      );
    }

    final date = input['date'] as String;
    return AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: yunqiModuleId,
      anchorId: 'yunqi:result:' +
          snapshotId +
          ':date=' +
          date +
          ':field:' +
          fieldPath,
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion as String,
      sourceId: YunQiToolService.sourceId,
      fieldPath: fieldPath,
      title: _yunqiChartFieldTitles[fieldPath],
    );
  }

  static AiContextResolution<AiResolvedToolField> resolveYunqiChartField({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.fieldValue ||
        normalized.isEmpty ||
        ref.moduleId != yunqiModuleId ||
        ref.sourceId != YunQiToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YunQi chart field reference is incomplete or does not identify the local YunQi engine.',
      );
    }
    if (ref.ruleVersion != YunQiToolService.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The YunQi engine or literature version no longer matches this chart field.',
      );
    }

    final fieldPath = ref.fieldPath;
    final snapshotId = ref.snapshotId;
    if (fieldPath == null ||
        !_yunqiChartFieldPaths.contains(fieldPath) ||
        snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ref.anchorVersion != snapshotId ||
        ref.anchorId !=
            'yunqi:result:' +
                snapshotId +
                ':date=' +
                ((structuredSnapshot['input'] is Map)
                    ? ((structuredSnapshot['input'] as Map)['date']?.toString() ?? '')
                    : '') +
                ':field:' +
                fieldPath ||
        ref.title != _yunqiChartFieldTitles[fieldPath]) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YunQi chart field path, title, anchor and immutable snapshot identity do not agree.',
      );
    }

    if (structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['capabilityId'] != yunqiModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            YunQiToolService.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        structuredSnapshot['ruleVersion'] != YunQiToolService.ruleVersion ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The supplied YunQi annual snapshot is stale, incomplete or has been modified.',
      );
    }

    final input = structuredSnapshot['input'];
    final sourceIds = structuredSnapshot['sourceIds'];
    final result = structuredSnapshot['result'];
    final annualData = result is Map ? result['annualData'] : null;
    final selectedDateContext =
        result is Map ? result['selectedDateContext'] : null;
    if (input is! Map ||
        input['date'] is! String ||
        result is! Map ||
        annualData is! Map ||
        selectedDateContext is! Map ||
        sourceIds is! List ||
        !sourceIds.contains(YunQiToolService.sourceId)) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The verified YunQi snapshot does not contain the required chart data or source.',
      );
    }

    final parentRef = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: yunqiModuleId,
      anchorId: 'yunqi:result:' +
          snapshotId +
          ':date=' +
          (input['date'] as String),
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: '五运六气年度推算结果（' + (input['date'] as String) + '）',
    );
    final parentResolution = resolveYunqiToolResult(ref: parentRef);
    final parent = parentResolution.value;
    if (!parentResolution.isResolved || parent == null) {
      return AiContextResolution(
        status: parentResolution.status,
        reason: parentResolution.reason,
      );
    }
    if (parent.structuredSnapshot['snapshotId'] != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The locally reconstructed YunQi annual result no longer matches this chart field snapshot.',
      );
    }

    final verifiedResult = parent.structuredSnapshot['result'];
    final verifiedAnnualData =
        verifiedResult is Map ? verifiedResult['annualData'] : null;
    final verifiedSelectedDateContext =
        verifiedResult is Map ? verifiedResult['selectedDateContext'] : null;
    if (verifiedAnnualData is! Map ||
        verifiedSelectedDateContext is! Map) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The reconstructed YunQi result does not contain its annual chart data.',
      );
    }
    final fieldValue = _yunqiChartFieldValue(
      fieldPath: fieldPath,
      annualData: verifiedAnnualData,
      selectedDateContext: verifiedSelectedDateContext,
    );
    if (fieldValue == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The requested YunQi chart group is missing from the verified annual result.',
      );
    }

    final fieldScope = Map<String, Object?>.unmodifiable({
      'year': verifiedAnnualData['year'] ?? 'MISSING',
      'ganZhi': verifiedAnnualData['ganZhi'] ?? 'MISSING',
      'calendarYear': verifiedSelectedDateContext['calendarYear'] ?? 'MISSING',
      'selectedDate': verifiedSelectedDateContext['date'] ?? 'MISSING',
      'yearConvention': '当前 App 页面采用公历年口径',
    });
    final fieldUnit = switch (fieldPath) {
      'chart.wuxing' => '五行关系与运气结构图数据；按 App 快照原值解释',
      'chart.wuyun' => '五运主运/客运五步结构；步骤索引从 0 开始',
      'chart.liuqi' => '六气主气/客气六步与主客加临关系；步骤索引从 0 开始',
      _ => 'MISSING',
    };
    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolField._(
        ref: ref,
        fieldLabel: _yunqiChartFieldTitles[fieldPath]!,
        fieldScope: fieldScope,
        fieldValue: [
          Map<String, Object?>.unmodifiable({
            'fieldPath': fieldPath,
            'value': fieldValue,
            'unit': fieldUnit,
          }),
        ],
        fieldUnit: fieldUnit,
        structuredSnapshot: parent.structuredSnapshot,
      ),
    );
  }

  static Map<String, Object?>? _yunqiChartFieldValue({
    required String fieldPath,
    required Map annualData,
    required Map selectedDateContext,
  }) {
    final mainYun = annualData['mainYun'];
    final guestYun = annualData['guestYun'];
    final mainQi = annualData['mainQi'];
    final guestQi = annualData['guestQi'];
    final relations = annualData['hostGuestRelations'];
    switch (fieldPath) {
      case 'chart.wuxing':
        final yearProperties = <String, Object?>{
          'yun': annualData['yun'],
          'taiGuo': annualData['taiGuo'],
          'siTian': annualData['siTian'],
          'siTianWx': annualData['siTianWx'],
          'zaiQuan': annualData['zaiQuan'],
          'shengXiao': annualData['shengXiao'],
        };
        final selectedMainYun = selectedDateContext['mainYun'];
        final selectedGuestYun = selectedDateContext['guestYun'];
        final selectedMainQi = selectedDateContext['mainQi'];
        final selectedGuestQi = selectedDateContext['guestQi'];
        if (yearProperties.values.any((value) => value == null) ||
            mainYun is! List ||
            mainYun.length != 5 ||
            guestYun is! List ||
            guestYun.length != 5 ||
            mainQi is! List ||
            mainQi.length != 6 ||
            guestQi is! List ||
            guestQi.length != 6 ||
            relations is! List ||
            relations.length != 6 ||
            selectedDateContext['yunStepIndex'] is! int ||
            selectedDateContext['qiStepIndex'] is! int ||
            selectedMainYun is! Map ||
            selectedGuestYun is! Map ||
            selectedMainQi is! Map ||
            selectedGuestQi is! String) {
          return null;
        }
        return <String, Object?>{
          'yearProperties': yearProperties,
          'mainYun': mainYun,
          'guestYun': guestYun,
          'mainQi': mainQi,
          'guestQi': guestQi,
          'hostGuestRelations': relations,
          'selectedStep': {
            'yunStepIndex': selectedDateContext['yunStepIndex'],
            'qiStepIndex': selectedDateContext['qiStepIndex'],
            'mainYun': selectedMainYun,
            'guestYun': selectedGuestYun,
            'mainQi': selectedMainQi,
            'guestQi': selectedGuestQi,
          },
        };
      case 'chart.wuyun':
        final yunStep = selectedDateContext['yunStepIndex'];
        final selectedMainYun = selectedDateContext['mainYun'];
        final selectedGuestYun = selectedDateContext['guestYun'];
        final yunBounds = selectedDateContext['yunStepBounds'];
        if (mainYun is! List ||
            mainYun.length != 5 ||
            guestYun is! List ||
            guestYun.length != 5 ||
            yunStep is! int ||
            yunStep < 0 ||
            yunStep >= 5 ||
            selectedMainYun is! Map ||
            selectedGuestYun is! Map ||
            yunBounds is! List ||
            yunBounds.length != 5) {
          return null;
        }
        return <String, Object?>{
          'mainYun': mainYun,
          'guestYun': guestYun,
          'selectedStep': {
            'index': yunStep,
            'mainYun': selectedMainYun,
            'guestYun': selectedGuestYun,
            'bounds': yunBounds,
          },
        };
      case 'chart.liuqi':
        final qiStep = selectedDateContext['qiStepIndex'];
        final selectedMainQi = selectedDateContext['mainQi'];
        final selectedGuestQi = selectedDateContext['guestQi'];
        final qiBounds = selectedDateContext['qiStepBounds'];
        if (mainQi is! List ||
            mainQi.length != 6 ||
            guestQi is! List ||
            guestQi.length != 6 ||
            relations is! List ||
            relations.length != 6 ||
            qiStep is! int ||
            qiStep < 0 ||
            qiStep >= 6 ||
            selectedMainQi is! Map ||
            selectedGuestQi is! String ||
            qiBounds is! List ||
            qiBounds.length != 6) {
          return null;
        }
        return <String, Object?>{
          'mainQi': mainQi,
          'guestQi': guestQi,
          'hostGuestRelations': relations,
          'selectedStep': {
            'index': qiStep,
            'mainQi': selectedMainQi,
            'guestQi': selectedGuestQi,
            'bounds': qiBounds,
          },
        };
      default:
        return null;
    }
  }

  static const yijingModuleId = 'yijing';

  static AiContextRef buildYiJingResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final ruleVersion = structuredSnapshot['ruleVersion'];
    final input = structuredSnapshot['input'];
    final sourceIds = structuredSnapshot['sourceIds'];
    if (snapshotId is! String ||
        snapshotId.isEmpty ||
        ruleVersion != YiJingToolService.ruleVersion ||
        structuredSnapshot['capabilityId'] != yijingModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            YiJingToolService.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] is! String ||
        sourceIds is! List ||
        !sourceIds.contains(YiJingToolService.sourceId) ||
        !sourceIds.contains(YiJingToolService.dataSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A YiJing context reference requires a complete, source-bound successful snapshot.',
      );
    }
    final method = input['method'] as String;
    if (!const {'number', 'time', 'manual', 'coins'}.contains(method)) {
      throw ArgumentError('The YiJing snapshot has an unsupported cast method.');
    }
    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: yijingModuleId,
      anchorId: 'yijing:result:$snapshotId:method=$method',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion as String,
      sourceId: YiJingToolService.sourceId,
      title: '易经起卦结果（$method）',
    );
  }

  static AiContextResolution<AiResolvedToolResult> resolveYiJingToolResult({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != yijingModuleId ||
        ref.sourceId != YiJingToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YiJing reference is incomplete or does not identify the local YiJing engine.',
      );
    }
    if (ref.ruleVersion != YiJingToolService.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The YiJing engine or hexagram data version no longer matches this result.',
      );
    }
    final anchorMatch = RegExp(
      r'^yijing:result:([0-9a-f]{64}):method=(number|time|manual|coins)$',
    ).firstMatch(ref.anchorId);
    final snapshotId = ref.snapshotId;
    if (anchorMatch == null ||
        snapshotId == null ||
        ref.anchorVersion != snapshotId ||
        anchorMatch.group(1) != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YiJing result anchor and snapshot identity do not agree.',
      );
    }
    final method = anchorMatch.group(2)!;
    if (ref.title != null && ref.title != '易经起卦结果（$method）') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YiJing result title does not match its cast method anchor.',
      );
    }

    final input = structuredSnapshot['input'];
    final argumentsValue = input is Map ? input['arguments'] : null;
    if (input is! Map ||
        input['method'] != method ||
        argumentsValue is! Map ||
        argumentsValue.entries.any(
          (entry) => entry.key is! String || entry.value is! String,
        ) ||
        structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['ruleVersion'] != YiJingToolService.ruleVersion ||
        structuredSnapshot['resultSchemaVersion'] !=
            YiJingToolService.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        structuredSnapshot['capabilityId'] != yijingModuleId ||
        structuredSnapshot['sourceIds'] is! List ||
        !(structuredSnapshot['sourceIds'] as List)
            .contains(YiJingToolService.sourceId) ||
        !(structuredSnapshot['sourceIds'] as List)
            .contains(YiJingToolService.dataSourceId)) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YiJing reference is not bound to a complete recorded execution input.',
      );
    }
    final arguments = <String, String>{
      for (final entry in argumentsValue.entries)
        entry.key as String: entry.value as String,
    };
    if (arguments['method'] != method) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The recorded YiJing method does not match its context anchor.',
      );
    }
    try {
      final suppliedDigest =
          AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot);
      if (suppliedDigest != snapshotId) {
        return const AiContextResolution(
          status: AiContextResolutionStatus.stale,
          reason: 'The supplied YiJing result no longer matches its immutable snapshot digest.',
        );
      }
      final reconstructed =
          YiJingToolService.createStructuredSnapshot(arguments);
      if (reconstructed['snapshotId'] != snapshotId) {
        return const AiContextResolution(
          status: AiContextResolutionStatus.stale,
          reason: 'The local YiJing engine reconstruction no longer matches this result.',
        );
      }
      return AiContextResolution(
        status: AiContextResolutionStatus.resolved,
        value: AiResolvedToolResult._(
          ref: ref,
          structuredSnapshot: reconstructed,
        ),
      );
    } catch (_) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YiJing result could not be reconstructed and verified from the local engine.',
      );
    }
  }

  static const _supportedYiJingFieldPath =
      r'^result\.(?:primary\.(?:seq|name|judgement)|moving|movingTexts\.[0-5]|changed\.(?:seq|name|judgement)|nuclear\.(?:seq|name|judgement))$';

  static AiContextRef buildYiJingFieldContextRef({
    required AiContextRef resultRef,
    required String fieldPath,
    required String fieldLabel,
  }) {
    final normalized = AiContextRef.normalizeMetadata(resultRef.toMetadata());
    final resultMatch = RegExp(
      r'^yijing:result:([0-9a-f]{64}):method=(number|time|manual|coins)$',
    ).firstMatch(resultRef.anchorId);
    if (normalized.isEmpty ||
        resultRef.kind != AiContextKind.toolResult ||
        resultRef.moduleId != yijingModuleId ||
        resultRef.snapshotId == null ||
        resultRef.snapshotId != resultRef.anchorVersion ||
        resultRef.ruleVersion != YiJingToolService.ruleVersion ||
        resultRef.sourceId != YiJingToolService.sourceId ||
        resultMatch == null ||
        resultMatch.group(1) != resultRef.snapshotId ||
        !RegExp(_supportedYiJingFieldPath).hasMatch(fieldPath)) {
      throw ArgumentError(
        'A YiJing field reference requires a verified result identity and supported scalar field path.',
      );
    }

    final snapshotId = resultRef.snapshotId!;
    final method = resultMatch.group(2)!;
    return AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: yijingModuleId,
      anchorId:
          'yijing:result:$snapshotId:method=$method:field=$fieldPath',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: resultRef.ruleVersion,
      sourceId: YiJingToolService.sourceId,
      fieldPath: fieldPath,
      title: fieldLabel,
    );
  }

  static AiContextResolution<AiResolvedToolField> resolveYiJingResultField({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.fieldValue ||
        normalized.isEmpty ||
        ref.moduleId != yijingModuleId ||
        ref.sourceId != YiJingToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YiJing field reference is incomplete or does not identify the local YiJing engine.',
      );
    }
    if (ref.ruleVersion != YiJingToolService.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The YiJing engine or hexagram data version no longer matches this field.',
      );
    }

    final match = RegExp(
      r'^yijing:result:([0-9a-f]{64}):method=(number|time|manual|coins):field=(.+)$',
    ).firstMatch(ref.anchorId);
    final snapshotId = ref.snapshotId;
    final fieldPath = ref.fieldPath;
    if (match == null ||
        snapshotId == null ||
        ref.anchorVersion != snapshotId ||
        match.group(1) != snapshotId ||
        fieldPath == null ||
        match.group(3) != fieldPath ||
        !RegExp(_supportedYiJingFieldPath).hasMatch(fieldPath)) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YiJing field path, anchor and result snapshot identity do not agree.',
      );
    }

    final method = match.group(2)!;
    final resultRef = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: yijingModuleId,
      anchorId: 'yijing:result:$snapshotId:method=$method',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: YiJingToolService.sourceId,
      title: '易经起卦结果（$method）',
    );
    final resultResolution = resolveYiJingToolResult(
      ref: resultRef,
      structuredSnapshot: structuredSnapshot,
    );
    final resolvedResult = resultResolution.value;
    if (!resultResolution.isResolved || resolvedResult == null) {
      return AiContextResolution(
        status: resultResolution.status,
        reason: resultResolution.reason,
      );
    }

    Object? value = resolvedResult.structuredSnapshot;
    for (final segment in fieldPath.split('.')) {
      if (value is Map) {
        value = value[segment];
      } else if (value is List) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= value.length) {
          value = null;
          break;
        }
        value = value[index];
      } else {
        value = null;
        break;
      }
    }
    if (value == null || (value is String && value.trim().isEmpty)) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The requested YiJing field is missing from the verified result snapshot.',
      );
    }
    if (value is! String && value is! num && value is! bool) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The requested YiJing field is not a supported scalar field value.',
      );
    }

    final result = resolvedResult.structuredSnapshot['result'];
    if (result is! Map) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The verified YiJing result does not contain its structured result scope.',
      );
    }
    final fieldUnit = fieldPath.endsWith('.seq')
        ? '通行本《周易》King Wen 卦序，1–64'
        : fieldPath == 'result.moving'
            ? '0=静卦；1–6=主断动爻位置，自下而上'
            : fieldPath.startsWith('result.movingTexts.')
                ? '通行本《周易》对应爻辞原文'
                : 'App 本地易经结果快照中的原始结构字段';
    final scope = <String, Object?>{
      'method': result['method'],
      'primary': result['primary'],
      'moving': result['moving'],
      'movingLines': result['movingLines'],
      'movingTitles': result['movingTitles'],
      'movingTexts': result['movingTexts'],
      'changed': result['changed'],
      'nuclear': result['nuclear'],
      'primaryLines': result['primaryLines'],
    };
    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolField._(
        ref: ref,
        fieldLabel: ref.title?.trim().isNotEmpty == true
            ? ref.title!
            : fieldPath,
        fieldScope: Map<String, Object?>.unmodifiable(scope),
        fieldValue: [
          Map<String, Object?>.unmodifiable({
            'fieldPath': fieldPath,
            'value': value,
            'unit': fieldUnit,
          }),
        ],
        fieldUnit: fieldUnit,
        structuredSnapshot: resolvedResult.structuredSnapshot,
      ),
    );
  }

  static const meihuaModuleId = 'meihua';

  static String _meihuaMethodLabel(String method) => switch (method) {
        'time' => '时间起卦',
        'number' => '数字起卦',
        'random' => '随机起卦',
        _ => 'MISSING',
      };

  static AiContextRef buildMeihuaResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final ruleVersion = structuredSnapshot['ruleVersion'];
    final input = structuredSnapshot['input'];
    final sourceIds = structuredSnapshot['sourceIds'];
    final method = input is Map ? input['method'] : null;
    final arguments = input is Map ? input['arguments'] : null;
    if (snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ruleVersion != MeihuaToolService.ruleVersion ||
        structuredSnapshot['capabilityId'] != meihuaModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            MeihuaToolService.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        method is! String ||
        !const {'time', 'number', 'random'}.contains(method) ||
        arguments is! Map ||
        arguments.entries.any(
          (entry) => entry.key is! String || entry.value is! String,
        ) ||
        arguments['method'] != method ||
        sourceIds is! List ||
        !sourceIds.contains(MeihuaToolService.sourceId) ||
        !sourceIds.contains(MeihuaToolService.dataSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A Meihua context reference requires a complete, source-bound successful execution snapshot.',
      );
    }

    final result = structuredSnapshot['result'];
    if (result is! Map ||
        result['method'] != method ||
        result['main'] is! Map ||
        result['mutual'] is! Map ||
        result['changed'] is! Map ||
        result['movingYao'] is! int ||
        result['stages'] is! List ||
        result['trace'] is! List) {
      throw ArgumentError(
        'The Meihua snapshot does not contain a complete structured hexagram result.',
      );
    }

    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: meihuaModuleId,
      anchorId: 'meihua:result:$snapshotId:method=$method',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion as String,
      sourceId: MeihuaToolService.sourceId,
      title: '梅花易数${_meihuaMethodLabel(method)}',
    );
  }

  static AiContextResolution<AiResolvedToolResult> resolveMeihuaToolResult({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != meihuaModuleId ||
        ref.sourceId != MeihuaToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Meihua reference is incomplete or does not identify the local Meihua engine.',
      );
    }
    if (ref.ruleVersion != MeihuaToolService.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The Meihua engine or hexagram data version no longer matches this result.',
      );
    }

    final match = RegExp(
      r'^meihua:result:([0-9a-f]{64}):method=(time|number|random)$',
    ).firstMatch(ref.anchorId);
    final snapshotId = ref.snapshotId;
    if (match == null ||
        snapshotId == null ||
        ref.anchorVersion != snapshotId ||
        match.group(1) != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Meihua result anchor and snapshot identity do not agree.',
      );
    }
    final method = match.group(2)!;
    if (ref.title != null &&
        ref.title != '梅花易数${_meihuaMethodLabel(method)}') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Meihua result title does not match its method anchor.',
      );
    }

    final input = structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final sourceIds = structuredSnapshot['sourceIds'];
    final result = structuredSnapshot['result'];
    if (input is! Map ||
        input['method'] != method ||
        arguments is! Map ||
        arguments.entries.any(
          (entry) => entry.key is! String || entry.value is! String,
        ) ||
        arguments['method'] != method ||
        arguments['date'] is! String ||
        DateTime.tryParse(arguments['date'] as String) == null ||
        DateTime.tryParse(arguments['date'] as String)!.toIso8601String()
            .substring(0, 10) != arguments['date'] ||
        (method == 'number' &&
            (int.tryParse(arguments['first'] ?? '') == null ||
                int.tryParse(arguments['second'] ?? '') == null ||
                arguments.containsKey('hour_branch'))) ||
        (method == 'time' &&
            (!MeihuaToolService.earthlyBranches.contains(
              arguments['hour_branch'],
            ) ||
                arguments.containsKey('first') ||
                arguments.containsKey('second'))) ||
        (method == 'random' &&
            (arguments.containsKey('first') ||
                arguments.containsKey('second') ||
                arguments.containsKey('hour_branch'))) ||
        structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['ruleVersion'] != MeihuaToolService.ruleVersion ||
        structuredSnapshot['resultSchemaVersion'] !=
            MeihuaToolService.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        structuredSnapshot['capabilityId'] != meihuaModuleId ||
        sourceIds is! List ||
        !sourceIds.contains(MeihuaToolService.sourceId) ||
        !sourceIds.contains(MeihuaToolService.dataSourceId) ||
        result is! Map ||
        result['method'] != method ||
        result['main'] is! Map ||
        result['mutual'] is! Map ||
        result['changed'] is! Map ||
        result['movingYao'] is! int ||
        result['stages'] is! List ||
        result['trace'] is! List) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Meihua reference is not bound to a complete recorded successful execution.',
      );
    }

    try {
      if (AiToolResultSnapshot.createStructuredId(
            snapshot: structuredSnapshot,
          ) !=
          snapshotId) {
        return const AiContextResolution(
          status: AiContextResolutionStatus.stale,
          reason: 'The supplied Meihua result no longer matches its immutable snapshot digest.',
        );
      }
      final derived = input['derived'];
      if (derived is! Map ||
          derived['lunarMonth'] is! int ||
          derived['lunarDay'] is! int ||
          (method == 'time' &&
              (derived['yearZhiIndex'] is! int ||
                  derived['hourZhiIndex'] is! int))) {
        return const AiContextResolution(
          status: AiContextResolutionStatus.unknown,
          reason: 'The Meihua snapshot does not preserve the exact derived inputs used by the calculation.',
        );
      }
      final displaySummary = structuredSnapshot['displaySummary'];
      if (displaySummary is! Map ||
          displaySummary['values'] is! Map ||
          displaySummary['title'] is! String) {
        return const AiContextResolution(
          status: AiContextResolutionStatus.unknown,
          reason: 'The Meihua snapshot does not contain a valid display summary.',
        );
      }
      return AiContextResolution(
        status: AiContextResolutionStatus.resolved,
        value: AiResolvedToolResult._(
          ref: ref,
          structuredSnapshot: structuredSnapshot,
        ),
      );
    } catch (_) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Meihua result could not be verified from its immutable local snapshot.',
      );
    }
  }

  static const _supportedMeihuaFieldPath =
      r'^result\.(?:(?:main|mutual|changed)\.(?:seq|name|judgement)|movingYao|movingYaoCi|tiWuxing|yongWuxing|mainRelation\.(?:label|verdict)|tiWangShuai\.label|stages\.[0-2]\.(?:name|hexName|relationLabel|detail))$';

  static AiContextRef buildMeihuaFieldContextRef({
    required AiContextRef resultRef,
    required String fieldPath,
    required String fieldLabel,
  }) {
    final normalized = AiContextRef.normalizeMetadata(resultRef.toMetadata());
    final resultMatch = RegExp(
      r'^meihua:result:([0-9a-f]{64}):method=(time|number|random)$',
    ).firstMatch(resultRef.anchorId);
    if (normalized.isEmpty ||
        resultRef.kind != AiContextKind.toolResult ||
        resultRef.moduleId != meihuaModuleId ||
        resultRef.snapshotId == null ||
        resultRef.snapshotId != resultRef.anchorVersion ||
        resultRef.ruleVersion != MeihuaToolService.ruleVersion ||
        resultRef.sourceId != MeihuaToolService.sourceId ||
        resultMatch == null ||
        resultMatch.group(1) != resultRef.snapshotId ||
        !RegExp(_supportedMeihuaFieldPath).hasMatch(fieldPath)) {
      throw ArgumentError(
        'A Meihua field reference requires a verified result identity and a supported scalar field path.',
      );
    }
    final snapshotId = resultRef.snapshotId!;
    final method = resultMatch.group(2)!;
    return AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: meihuaModuleId,
      anchorId:
          'meihua:result:$snapshotId:method=$method:field=$fieldPath',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: resultRef.ruleVersion,
      sourceId: MeihuaToolService.sourceId,
      fieldPath: fieldPath,
      title: fieldLabel,
    );
  }

  static AiContextResolution<AiResolvedToolField> resolveMeihuaResultField({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.fieldValue ||
        normalized.isEmpty ||
        ref.moduleId != meihuaModuleId ||
        ref.sourceId != MeihuaToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Meihua field reference is incomplete or does not identify the local Meihua engine.',
      );
    }
    if (ref.ruleVersion != MeihuaToolService.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The Meihua engine or hexagram data version no longer matches this field.',
      );
    }

    final match = RegExp(
      r'^meihua:result:([0-9a-f]{64}):method=(time|number|random):field=(.+)$',
    ).firstMatch(ref.anchorId);
    final snapshotId = ref.snapshotId;
    final fieldPath = ref.fieldPath;
    if (match == null ||
        snapshotId == null ||
        ref.anchorVersion != snapshotId ||
        match.group(1) != snapshotId ||
        fieldPath == null ||
        match.group(3) != fieldPath ||
        !RegExp(_supportedMeihuaFieldPath).hasMatch(fieldPath)) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Meihua field path, anchor and result snapshot identity do not agree.',
      );
    }
    final method = match.group(2)!;
    final resultRef = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: meihuaModuleId,
      anchorId: 'meihua:result:$snapshotId:method=$method',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: MeihuaToolService.sourceId,
      title: '梅花易数${_meihuaMethodLabel(method)}',
    );
    final resultResolution = resolveMeihuaToolResult(
      ref: resultRef,
      structuredSnapshot: structuredSnapshot,
    );
    final resolvedResult = resultResolution.value;
    if (!resultResolution.isResolved || resolvedResult == null) {
      return AiContextResolution(
        status: resultResolution.status,
        reason: resultResolution.reason,
      );
    }

    Object? value = resolvedResult.structuredSnapshot;
    for (final segment in fieldPath.split('.')) {
      if (value is Map) {
        value = value[segment];
      } else if (value is List) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= value.length) {
          value = null;
          break;
        }
        value = value[index];
      } else {
        value = null;
        break;
      }
    }
    if (value == null || (value is String && value.trim().isEmpty)) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The requested Meihua field is missing from the verified result snapshot.',
      );
    }
    if (value is! String && value is! num && value is! bool) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The requested Meihua field is not a supported scalar field value.',
      );
    }

    final result = resolvedResult.structuredSnapshot['result'];
    if (result is! Map) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The verified Meihua result does not contain its structured result scope.',
      );
    }
    final fieldUnit = fieldPath.endsWith('.seq')
        ? '通行本《周易》King Wen 卦序，1–64'
        : fieldPath == 'result.movingYao'
            ? '动爻位置，1–6，自下而上'
            : 'App 本地梅花快照中的原始结构字段；不作概率或科学预测解释';
    final fieldLabel = ref.title?.trim().isNotEmpty == true
        ? ref.title!
        : fieldPath;
    final scope = <String, Object?>{
      'method': result['method'],
      'main': result['main'],
      'mutual': result['mutual'],
      'changed': result['changed'],
      'movingYao': result['movingYao'],
      'movingYaoCi': result['movingYaoCi'],
      'ti': result['ti'],
      'yong': result['yong'],
      'tiWuxing': result['tiWuxing'],
      'yongWuxing': result['yongWuxing'],
      'mainRelation': result['mainRelation'],
      'tiWangShuai': result['tiWangShuai'],
      'monthBranch': result['monthBranch'],
      'stages': result['stages'],
      'verdict': result['verdict'],
    };
    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolField._(
        ref: ref,
        fieldLabel: fieldLabel,
        fieldScope: Map<String, Object?>.unmodifiable(scope),
        fieldValue: [
          Map<String, Object?>.unmodifiable({
            'fieldPath': fieldPath,
            'value': value,
            'unit': fieldUnit,
          }),
        ],
        fieldUnit: fieldUnit,
        structuredSnapshot: resolvedResult.structuredSnapshot,
      ),
    );
  }

  static const baziModuleId = 'bazi';

  static AiContextRef buildBaziResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final ruleVersion = structuredSnapshot['ruleVersion'];
    final sourceIds = structuredSnapshot['sourceIds'];
    final input = structuredSnapshot['input'];
    final result = structuredSnapshot['result'];
    final validDigest = snapshotId is String &&
        snapshotId.length == 64 &&
        snapshotId.codeUnits.every((unit) =>
            (unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102));
    if (!validDigest ||
        ruleVersion != BaziContextSnapshot.ruleVersion ||
        structuredSnapshot['capabilityId'] != baziModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            BaziContextSnapshot.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        sourceIds is! List ||
        !sourceIds.contains(BaziContextSnapshot.sourceId) ||
        input is! Map ||
        input['arguments'] is! Map ||
        input['location'] is! Map ||
        input['settings'] is! Map ||
        result is! Map ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A Bazi context reference requires a complete, source-bound successful snapshot.',
      );
    }
    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: baziModuleId,
      anchorId: 'bazi:result:$snapshotId',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ruleVersion as String,
      sourceId: BaziContextSnapshot.sourceId,
      title: '八字排盘结果',
    );
  }

  static AiContextResolution<AiResolvedToolResult> resolveBaziToolResult({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != baziModuleId ||
        ref.sourceId != BaziContextSnapshot.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Bazi reference is incomplete or does not identify the local Bazi engine.',
      );
    }
    if (ref.ruleVersion != BaziContextSnapshot.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The Bazi engine, analysis rules, calendar package or city data version no longer matches this result.',
      );
    }

    final snapshotId = ref.snapshotId;
    final isHexDigest = snapshotId != null &&
        snapshotId.length == 64 &&
        snapshotId.codeUnits.every((unit) =>
            (unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102));
    if (!isHexDigest ||
        ref.anchorVersion != snapshotId ||
        ref.anchorId != 'bazi:result:$snapshotId' ||
        (ref.title != null && ref.title != '八字排盘结果')) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Bazi result anchor, title and snapshot identity do not agree.',
      );
    }

    try {
      final sourceIds = structuredSnapshot['sourceIds'];
      if (structuredSnapshot['snapshotId'] != snapshotId ||
          structuredSnapshot['ruleVersion'] != BaziContextSnapshot.ruleVersion ||
          structuredSnapshot['resultSchemaVersion'] !=
              BaziContextSnapshot.resultSchemaVersion ||
          structuredSnapshot['executionStatus'] != 'SUCCESS' ||
          structuredSnapshot['capabilityId'] != baziModuleId ||
          sourceIds is! List ||
          !sourceIds.contains(BaziContextSnapshot.sourceId) ||
          AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
              snapshotId) {
        return const AiContextResolution(
          status: AiContextResolutionStatus.stale,
          reason: 'The supplied Bazi snapshot metadata or digest does not match the reference.',
        );
      }

      final input = structuredSnapshot['input'];
      if (input is! Map) {
        return const AiContextResolution(
          status: AiContextResolutionStatus.unknown,
          reason: 'The Bazi snapshot does not contain recorded birth inputs, location and calculation settings.',
        );
      }
      final rebuilt = BaziContextSnapshot.rebuildFromInput(
        input: Map<String, Object?>.from(input),
      );
      if (rebuilt['snapshotId'] != snapshotId) {
        return const AiContextResolution(
          status: AiContextResolutionStatus.stale,
          reason: 'Rebuilding the Bazi chart from the recorded inputs no longer matches this immutable result.',
        );
      }
      final rebuiltSources = rebuilt['sourceIds'];
      if (rebuiltSources is! List ||
          sourceIds.length != rebuiltSources.length) {
        return const AiContextResolution(
          status: AiContextResolutionStatus.unknown,
          reason: 'The Bazi snapshot source list does not match its recorded location provenance.',
        );
      }
      for (var index = 0; index < sourceIds.length; index++) {
        if (sourceIds[index] != rebuiltSources[index]) {
          return const AiContextResolution(
            status: AiContextResolutionStatus.unknown,
            reason: 'The Bazi snapshot source list does not match its recorded location provenance.',
          );
        }
      }
      return AiContextResolution(
        status: AiContextResolutionStatus.resolved,
        value: AiResolvedToolResult._(
          ref: ref,
          structuredSnapshot: rebuilt,
        ),
      );
    } catch (_) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Bazi result could not be reconstructed and verified from the local engine.',
      );
    }
  }

  static const _supportedBaziFieldPath =
      r'^result\.analysis\.(?:pattern|dayMaster|strengthLevel|strengthScore|fiveElements\.\d+\.(?:element|score|status))$';

  static AiContextRef buildBaziFieldContextRef({
    required AiContextRef resultRef,
    required String fieldPath,
    required String fieldLabel,
  }) {
    final normalized = AiContextRef.normalizeMetadata(resultRef.toMetadata());
    if (normalized.isEmpty ||
        resultRef.kind != AiContextKind.toolResult ||
        resultRef.moduleId != baziModuleId ||
        resultRef.snapshotId == null ||
        resultRef.snapshotId != resultRef.anchorVersion ||
        resultRef.ruleVersion != BaziContextSnapshot.ruleVersion ||
        resultRef.sourceId != BaziContextSnapshot.sourceId ||
        !RegExp(_supportedBaziFieldPath).hasMatch(fieldPath)) {
      throw ArgumentError(
        'A Bazi field reference requires a verified result identity and a supported field path.',
      );
    }
    final snapshotId = resultRef.snapshotId!;
    return AiContextRef(
      kind: AiContextKind.fieldValue,
      moduleId: baziModuleId,
      anchorId: 'bazi:result:$snapshotId:field:$fieldPath',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: resultRef.ruleVersion,
      sourceId: BaziContextSnapshot.sourceId,
      fieldPath: fieldPath,
      title: fieldLabel,
    );
  }

  static AiContextResolution<AiResolvedToolField> resolveBaziResultField({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (normalized.isEmpty ||
        ref.kind != AiContextKind.fieldValue ||
        ref.moduleId != baziModuleId ||
        ref.sourceId != BaziContextSnapshot.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Bazi field reference is incomplete or does not identify the local Bazi engine.',
      );
    }
    if (ref.ruleVersion != BaziContextSnapshot.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The Bazi engine or calculation rule version no longer matches this field.',
      );
    }

    final snapshotId = ref.snapshotId;
    final fieldPath = ref.fieldPath;
    if (snapshotId == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ref.anchorVersion != snapshotId ||
        fieldPath == null ||
        !RegExp(_supportedBaziFieldPath).hasMatch(fieldPath) ||
        ref.anchorId != 'bazi:result:$snapshotId:field:$fieldPath') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Bazi field path, anchor and result snapshot identity do not agree.',
      );
    }

    final resultRef = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: baziModuleId,
      anchorId: 'bazi:result:$snapshotId',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: BaziContextSnapshot.sourceId,
      title: '八字排盘结果',
    );
    final resultResolution = resolveBaziToolResult(
      ref: resultRef,
      structuredSnapshot: structuredSnapshot,
    );
    final resolvedResult = resultResolution.value;
    if (!resultResolution.isResolved || resolvedResult == null) {
      return AiContextResolution(
        status: resultResolution.status,
        reason: resultResolution.reason,
      );
    }

    Object? value = resolvedResult.structuredSnapshot;
    for (final segment in fieldPath.split('.')) {
      if (value is Map) {
        value = value[segment];
      } else if (value is List) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= value.length) {
          value = null;
          break;
        }
        value = value[index];
      } else {
        value = null;
        break;
      }
    }
    if (value == null || (value is String && value.trim().isEmpty)) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The requested Bazi field is missing from the verified result snapshot.',
      );
    }
    if (value is! String && value is! num && value is! bool) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The requested Bazi field is not a supported scalar field value.',
      );
    }

    final result = resolvedResult.structuredSnapshot['result'];
    final analysis = result is Map ? result['analysis'] : null;
    if (analysis is! Map) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The verified Bazi result does not contain its analysis scope.',
      );
    }

    final unit = fieldPath == 'result.analysis.strengthScore'
        ? 'App 内部日主强弱规则分值；不是概率或统计置信度'
        : fieldPath.endsWith('.score')
            ? 'App 内部五行分布规则分值；不是人口频率或概率'
            : 'App 本地八字引擎返回的文本/枚举字段';
    final fieldLabel = ref.title?.trim().isNotEmpty == true
        ? ref.title!
        : fieldPath;
    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolField._(
        ref: ref,
        fieldLabel: fieldLabel,
        fieldScope: Map<String, Object?>.unmodifiable({
          'dayMaster': analysis['dayMaster'],
          'pattern': analysis['pattern'],
          'patternDescription': analysis['patternDescription'],
          'strengthLevel': analysis['strengthLevel'],
          'strengthScore': analysis['strengthScore'],
          'strengthFactors': analysis['strengthFactors'],
          'fiveElements': analysis['fiveElements'],
          'favorable': analysis['favorable'],
          'unfavorable': analysis['unfavorable'],
        }),
        fieldValue: [
          Map<String, Object?>.unmodifiable({
            'fieldPath': fieldPath,
            'value': value,
            'unit': unit,
          }),
        ],
        fieldUnit: unit,
        structuredSnapshot: resolvedResult.structuredSnapshot,
      ),
    );
  }


  static const formulaModuleId = 'formula';
  static const formulaAssetVersion =
      'assets/data/formulas.json@58b299e95c47fd54fc1bca18c6762c544b8d87bc';

  static AiContextRef buildFormulaContextRef(Formula formula) {
    return AiContextRef(
      kind: AiContextKind.formula,
      moduleId: formulaModuleId,
      anchorId: 'formula:${formula.id}',
      anchorVersion: formulaAssetVersion,
      sourceId: 'formula:${formula.id}',
      title: formula.name,
    );
  }

  static AiContextResolution<AiResolvedKnowledgeEntry> resolveFormula({
    required AiContextRef ref,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.formula ||
        normalized.isEmpty ||
        ref.moduleId != formulaModuleId ||
        ref.anchorVersion != formulaAssetVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The formula reference is incomplete or does not match the bundled formula source.',
      );
    }

    final formulaId = ref.anchorId.startsWith('formula:')
        ? ref.anchorId.substring('formula:'.length)
        : '';
    if (formulaId.isEmpty || ref.sourceId != 'formula:$formulaId') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The formula anchor and source ID do not agree.',
      );
    }
    final formula = FormulaRepository.getById(formulaId);
    if (formula == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The referenced formula is not present in the bundled formula repository.',
      );
    }

    final content = <String, Object?>{
      'id': formula.id,
      'name': formula.name,
      'alias': formula.alias,
      'meridian': formula.meridian,
      'category': formula.category,
      'components': formula.components
          .map((component) => <String, Object?>{
                'name': component.name,
                'dosage': component.dosage,
                'role': component.role,
              })
          .toList(growable: false),
      'indication': formula.indication,
      'contraindication': formula.contraindication,
      'dosage': formula.dosage,
      'preparation': formula.preparation,
      'explanation': formula.explanation,
      'keywords': formula.keywords,
    };

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedKnowledgeEntry._(
        ref: ref,
        title: formula.name,
        content: Map<String, Object?>.unmodifiable(content),
      ),
    );
  }


  static const meridianModuleId = 'meridian';
  static const meridianRuleVersion = 'diagnostic-rules-meridian-details-v1';
  static const meridianResultSchemaVersion = 'meridian-knowledge-v1';
  static const meridianSourceId = 'local-data:diagnostic-rules:meridianDetails';

  static AiContextRef buildMeridianContextRef({
    required String meridian,
  }) {
    final snapshot = _createMeridianKnowledgeSnapshot(meridian);
    if (snapshot == null) {
      throw ArgumentError.value(meridian, 'meridian', 'A known, complete six-meridian entry is required.');
    }
    final snapshotId = snapshot['snapshotId'] as String;
    return AiContextRef(
      kind: AiContextKind.knowledgeEntry,
      moduleId: meridianModuleId,
      anchorId: 'meridian:detail:' + meridian,
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: meridianRuleVersion,
      sourceId: meridianSourceId,
      title: meridian + '病',
    );
  }

  static AiContextResolution<AiResolvedKnowledgeEntry> resolveMeridianKnowledgeEntry({
    required AiContextRef ref,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.knowledgeEntry || normalized.isEmpty ||
        ref.moduleId != meridianModuleId || ref.sourceId != meridianSourceId) {
      return const AiContextResolution(status: AiContextResolutionStatus.unknown, reason: 'The six-meridian reference is incomplete or has an unverified source.');
    }
    if (ref.ruleVersion != meridianRuleVersion) {
      return const AiContextResolution(status: AiContextResolutionStatus.stale, reason: 'The six-meridian rule data version no longer matches this context.');
    }
    final match = RegExp(r'^meridian:detail:(太阳|阳明|少阳|太阴|少阴|厥阴)$').firstMatch(ref.anchorId);
    if (match == null) {
      return const AiContextResolution(status: AiContextResolutionStatus.unknown, reason: 'The six-meridian anchor does not identify one exact local record.');
    }
    final meridian = match.group(1)!;
    if (ref.title != meridian + '病') {
      return const AiContextResolution(status: AiContextResolutionStatus.unknown, reason: 'The six-meridian title does not match the selected local record.');
    }
    final snapshot = _createMeridianKnowledgeSnapshot(meridian);
    if (snapshot == null) {
      return const AiContextResolution(status: AiContextResolutionStatus.missing, reason: 'The selected six-meridian record is not available in the local rules data.');
    }
    final snapshotId = snapshot['snapshotId'];
    if (snapshotId is! String || ref.snapshotId != snapshotId || ref.anchorVersion != snapshotId) {
      return const AiContextResolution(status: AiContextResolutionStatus.stale, reason: 'The six-meridian record has changed since this context was created.');
    }
    final result = snapshot['result'];
    if (result is! Map<String, Object?>) {
      return const AiContextResolution(status: AiContextResolutionStatus.missing, reason: 'The six-meridian snapshot has no structured local record.');
    }
    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedKnowledgeEntry._(ref: ref, title: meridian + '病', content: Map<String, Object?>.unmodifiable(result)),
    );
  }

  static Map<String, Object?>? _createMeridianKnowledgeSnapshot(String meridian) {
    final details = DiagnosticRules.meridianDetails[meridian];
    if (details == null) return null;
    final nature = details['nature'];
    final organ = details['organ'];
    final keyPulse = details['keyPulse'];
    final coreSymptoms = details['coreSymptoms'];
    final transmissionIn = details['transmissionIn'];
    final transmissionOut = details['transmissionOut'];
    final classicText = details['classicText'];
    final niNote = details['niNote'];
    final healingTime = DiagnosticRules.meridianHealingTime[meridian];
    if (nature is! String || nature.isEmpty || organ is! String || organ.isEmpty ||
        keyPulse is! String || keyPulse.isEmpty || coreSymptoms is! List || coreSymptoms.isEmpty ||
        coreSymptoms.any((value) => value is! String || value.isEmpty) ||
        transmissionOut is! List || transmissionOut.isEmpty ||
        transmissionOut.any((value) => value is! String || value.isEmpty) ||
        classicText is! String || classicText.isEmpty || niNote is! String || niNote.isEmpty ||
        healingTime is! String || healingTime.isEmpty ||
        !(transmissionIn is String && transmissionIn.isNotEmpty ||
          transmissionIn is List && transmissionIn.every((value) => value is String && value.isNotEmpty))) {
      return null;
    }
    final result = <String, Object?>{
      'meridian': meridian,
      'nature': nature,
      'organ': organ,
      'keyPulse': keyPulse,
      'coreSymptoms': List<String>.unmodifiable(coreSymptoms.cast<String>()),
      'healingTime': healingTime,
      'transmissionIn': transmissionIn is List ? List<String>.unmodifiable(transmissionIn.cast<String>()) : transmissionIn,
      'transmissionOut': List<String>.unmodifiable(transmissionOut.cast<String>()),
      'classicText': classicText,
      'niNote': niNote,
    };
    final snapshot = <String, Object?>{
      'capabilityId': meridianModuleId,
      'resultSchemaVersion': meridianResultSchemaVersion,
      'executionStatus': 'SUCCESS',
      'ruleVersion': meridianRuleVersion,
      'sourceIds': const <String>[meridianSourceId],
      'input': <String, Object?>{'meridian': meridian},
      'result': result,
    };
    snapshot['snapshotId'] = AiToolResultSnapshot.createStructuredId(snapshot: snapshot);
    return Map<String, Object?>.unmodifiable(snapshot);
  }

  static const herbModuleId = 'herb';
  static const herbAssetVersion =
      'assets/data/herbs.json@73fb43ff3e0456ca8404a42059dc37769a511dee';

  static AiContextRef buildHerbContextRef(Herb herb) {
    return AiContextRef(
      kind: AiContextKind.herb,
      moduleId: herbModuleId,
      anchorId: 'herb:${herb.name}',
      anchorVersion: herbAssetVersion,
      sourceId: 'assets/data/herbs.json#${herb.name}',
      title: herb.name,
    );
  }

  static AiContextResolution<AiResolvedKnowledgeEntry> resolveHerb({
    required AiContextRef ref,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.herb ||
        normalized.isEmpty ||
        ref.moduleId != herbModuleId ||
        ref.anchorVersion != herbAssetVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The herb reference is incomplete or does not match the bundled herb source.',
      );
    }

    final herbName = ref.anchorId.startsWith('herb:')
        ? ref.anchorId.substring('herb:'.length)
        : '';
    if (herbName.isEmpty ||
        ref.sourceId != 'assets/data/herbs.json#$herbName' ||
        (ref.title != null && ref.title != herbName)) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The herb anchor, title and source reference do not agree.',
      );
    }

    // Exact lookup only: aliases and fuzzy matches must not silently change
    // the knowledge entry the user opened.
    final herb = HerbRepository.getExactByName(herbName);
    if (herb == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The referenced herb is not present in the bundled herb repository.',
      );
    }

    final content = <String, Object?>{
      'name': herb.name,
      'original': herb.original,
      'nature': herb.nature,
      'action': herb.action,
      'rongchuan': herb.rongchuan,
      'niNote': herb.niNote,
      'dosage': herb.dosage,
      'contraindication': herb.contraindication,
      'clinicalNotes': herb.clinicalNotes,
      'historicalNotes': herb.historicalNotes,
      'herbComparisons': herb.herbComparisons,
      'natureCategory': herb.natureCategory,
      'flavor': herb.flavor,
      'meridians': herb.meridians,
      'category': herb.category,
    };

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedKnowledgeEntry._(
        ref: ref,
        title: herb.name,
        content: Map<String, Object?>.unmodifiable(content),
      ),
    );
  }


  static const acupointModuleId = 'acupoint';
  static const acupointAssetVersion =
      'assets/data/acupoints.json@cf955d1e5485b6b4fcef15dc7711469b4b941d88';
  static const _acupointResultSchemaVersion = 1;

  static Map<String, Object?> _acupointKnowledgeSnapshot(
    AcupointDetail point,
  ) {
    return <String, Object?>{
      'capabilityId': acupointModuleId,
      'input': <String, Object?>{'entryId': point.name},
      'resultSchemaVersion': _acupointResultSchemaVersion,
      'ruleVersion': acupointAssetVersion,
      'sourceId': 'assets/data/acupoints.json#${point.name}',
      'entryId': point.name,
      'entry': Map<String, Object?>.unmodifiable(
        Map<String, Object?>.from(point.toJson()),
      ),
    };
  }

  static AiContextRef buildAcupointContextRef({
    required AcupointDetail acupoint,
  }) {
    final matches = AcupointRepository.getAll()
        .where((item) => item.name == acupoint.name)
        .toList(growable: false);
    if (acupoint.name.trim().isEmpty ||
        matches.length != 1 ||
        AiToolResultSnapshot.canonicalJson(
              _acupointKnowledgeSnapshot(matches.single),
            ) !=
            AiToolResultSnapshot.canonicalJson(
              _acupointKnowledgeSnapshot(acupoint),
            )) {
      throw ArgumentError(
        'An acupoint context requires one exact entry from the bundled acupoints dataset.',
      );
    }

    final sourceId = 'assets/data/acupoints.json#${acupoint.name}';
    final snapshotId = AiToolResultSnapshot.createStructuredId(
      snapshot: _acupointKnowledgeSnapshot(matches.single),
    );
    return AiContextRef(
      kind: AiContextKind.knowledgeEntry,
      moduleId: acupointModuleId,
      anchorId: 'acupoint:${acupoint.name}',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: acupointAssetVersion,
      sourceId: sourceId,
      title: acupoint.name,
    );
  }

  static AiContextResolution<AiResolvedKnowledgeEntry> resolveAcupoint({
    required AiContextRef ref,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.knowledgeEntry ||
        normalized.isEmpty ||
        ref.moduleId != acupointModuleId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The acupoint reference is incomplete or does not identify the local acupoint knowledge module.',
      );
    }
    if (ref.ruleVersion != acupointAssetVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The bundled acupoints dataset version no longer matches this reference.',
      );
    }

    const prefix = 'acupoint:';
    final pointName =
        ref.anchorId.startsWith(prefix) ? ref.anchorId.substring(prefix.length) : '';
    final snapshotId = ref.snapshotId;
    if (pointName.isEmpty ||
        snapshotId == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ref.anchorVersion != snapshotId ||
        ref.sourceId != 'assets/data/acupoints.json#$pointName' ||
        (ref.title != null && ref.title != pointName)) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The acupoint anchor, title, source and immutable snapshot identity do not agree.',
      );
    }

    final matches = AcupointRepository.getAll()
        .where((item) => item.name == pointName)
        .toList(growable: false);
    if (matches.isEmpty) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The exact acupoint entry is not present in the bundled dataset.',
      );
    }
    if (matches.length != 1) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The acupoint name is not unique in the bundled dataset.',
      );
    }

    final snapshot = _acupointKnowledgeSnapshot(matches.single);
    if (AiToolResultSnapshot.createStructuredId(snapshot: snapshot) !=
        snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The current local acupoint record no longer matches the immutable snapshot.',
      );
    }

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedKnowledgeEntry._(
        ref: ref,
        title: matches.single.name,
        content: Map<String, Object?>.unmodifiable(snapshot),
      ),
    );
  }

  static const acupunctureModuleId = 'acupuncture-prescriptions';
  static const acupunctureAssetVersion =
      'assets/data/acupuncture.json@ccf4419e37e2f67afc58d71a86592b295bd88d5b';
  static const _acupunctureEntryResultSchemaVersion = 1;

  static String _acupunctureEntrySourceId(String categoryId, int entryId) =>
      'acupuncture:' + categoryId + ':' + entryId.toString();

  static String _acupunctureEntryAnchorId(String categoryId, int entryId) =>
      acupunctureModuleId + ':' + categoryId + ':' + entryId.toString();

  static Map<String, Object?> _acupunctureEntryKnowledgeSnapshot({
    required AcupunctureCategory category,
    required AcupointEntry entry,
  }) {
    return <String, Object?>{
      'capabilityId': acupunctureModuleId,
      'input': <String, Object?>{
        'categoryId': category.id,
        'entryId': entry.id,
      },
      'resultSchemaVersion': _acupunctureEntryResultSchemaVersion,
      'ruleVersion': acupunctureAssetVersion,
      'sourceId': _acupunctureEntrySourceId(category.id, entry.id),
      'category': <String, Object?>{
        'id': category.id,
        'name': category.name,
      },
      'entryId': entry.id,
      'entry': Map<String, Object?>.unmodifiable(
        Map<String, Object?>.from(entry.toJson()),
      ),
    };
  }

  static AiContextRef buildAcupunctureEntryContextRef({
    required String categoryId,
    required AcupointEntry entry,
  }) {
    final normalizedCategoryId = categoryId.trim();
    final categoryMatches = AcupunctureRepository.getAll()
        .where((category) => category.id == normalizedCategoryId)
        .toList(growable: false);
    if (normalizedCategoryId.isEmpty ||
        categoryMatches.length != 1 ||
        entry.id <= 0 ||
        entry.symptom.trim().isEmpty) {
      throw ArgumentError(
        'An acupuncture context requires one exact category and positive entry ID from the bundled dataset.',
      );
    }

    final category = categoryMatches.single;
    final entryMatches = category.entries
        .where((item) => item.id == entry.id)
        .toList(growable: false);
    if (entryMatches.length != 1 ||
        AiToolResultSnapshot.canonicalJson(
              _acupunctureEntryKnowledgeSnapshot(
                category: category,
                entry: entryMatches.single,
              ),
            ) !=
            AiToolResultSnapshot.canonicalJson(
              _acupunctureEntryKnowledgeSnapshot(
                category: category,
                entry: entry,
              ),
            )) {
      throw ArgumentError(
        'An acupuncture context requires one exact, unchanged entry within the selected category.',
      );
    }

    final snapshot = _acupunctureEntryKnowledgeSnapshot(
      category: category,
      entry: entryMatches.single,
    );
    final snapshotId = AiToolResultSnapshot.createStructuredId(
      snapshot: snapshot,
    );
    return AiContextRef(
      kind: AiContextKind.knowledgeEntry,
      moduleId: acupunctureModuleId,
      anchorId: _acupunctureEntryAnchorId(category.id, entry.id),
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: acupunctureAssetVersion,
      sourceId: _acupunctureEntrySourceId(category.id, entry.id),
      title: entry.symptom,
    );
  }

  static AiContextResolution<AiResolvedKnowledgeEntry>
      resolveAcupunctureEntry({required AiContextRef ref}) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    final parts = ref.anchorId.split(':');
    if (ref.kind != AiContextKind.knowledgeEntry ||
        normalized.isEmpty ||
        ref.moduleId != acupunctureModuleId ||
        parts.length != 3 ||
        parts[0] != acupunctureModuleId ||
        parts[1].trim().isEmpty) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The acupuncture prescription reference is incomplete or does not identify the local prescription dataset.',
      );
    }
    if (ref.ruleVersion != acupunctureAssetVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The bundled acupuncture dataset version no longer matches this reference.',
      );
    }

    final categoryId = parts[1];
    final entryId = int.tryParse(parts[2]);
    final snapshotId = ref.snapshotId;
    final sourceId = entryId == null
        ? ''
        : _acupunctureEntrySourceId(categoryId, entryId);
    final hasValidDigest = snapshotId != null &&
        snapshotId.length == 64 &&
        snapshotId
            .split('')
            .every((character) => '0123456789abcdef'.contains(character));
    if (entryId == null ||
        entryId <= 0 ||
        !hasValidDigest ||
        ref.anchorVersion != snapshotId ||
        ref.anchorId != _acupunctureEntryAnchorId(categoryId, entryId) ||
        ref.sourceId != sourceId ||
        (ref.title != null && ref.title!.trim().isEmpty)) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The acupuncture category, entry ID, source and immutable snapshot identity do not agree.',
      );
    }

    final categoryMatches = AcupunctureRepository.getAll()
        .where((category) => category.id == categoryId)
        .toList(growable: false);
    if (categoryMatches.isEmpty) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The exact acupuncture category is not present in the bundled dataset.',
      );
    }
    if (categoryMatches.length != 1) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The acupuncture category ID is not unique in the bundled dataset.',
      );
    }

    final category = categoryMatches.single;
    final entryMatches = category.entries
        .where((entry) => entry.id == entryId)
        .toList(growable: false);
    if (entryMatches.isEmpty) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The exact acupuncture prescription entry is not present in the selected category.',
      );
    }
    if (entryMatches.length != 1) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The acupuncture entry ID is not unique within the selected category.',
      );
    }

    final entry = entryMatches.single;
    if (ref.title != null && ref.title != entry.symptom) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The acupuncture entry title does not match the selected local record.',
      );
    }
    final snapshot = _acupunctureEntryKnowledgeSnapshot(
      category: category,
      entry: entry,
    );
    if (AiToolResultSnapshot.createStructuredId(snapshot: snapshot) !=
        snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The current local acupuncture entry no longer matches the immutable snapshot.',
      );
    }

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedKnowledgeEntry._(
        ref: ref,
        title: entry.symptom,
        content: Map<String, Object?>.unmodifiable(snapshot),
      ),
    );
  }

  static const neijingModuleId = 'neijing-entries';
  static const neijingEntriesAssetVersion =
      'lib/data/neijing_entries.dart@7f76c837e89829b44d9fc3830cdbd1d31abfd8f9';

  static AiContextRef buildNeijingEntryContextRef(NeijingEntry entry) {
    return AiContextRef(
      kind: AiContextKind.classic,
      moduleId: neijingModuleId,
      anchorId: 'neijing:${entry.id}',
      anchorVersion: neijingEntriesAssetVersion,
      sourceId: 'app-data:lib/data/neijing_entries.dart#${entry.id}',
      title: entry.title,
    );
  }

  static AiContextResolution<AiResolvedKnowledgeEntry> resolveNeijingEntry({
    required AiContextRef ref,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.classic ||
        normalized.isEmpty ||
        ref.moduleId != neijingModuleId ||
        ref.anchorVersion != neijingEntriesAssetVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Neijing reference is incomplete or does not match the bundled entry source.',
      );
    }

    final entryId = ref.anchorId.startsWith('neijing:')
        ? ref.anchorId.substring('neijing:'.length)
        : '';
    if (entryId.isEmpty ||
        ref.sourceId != 'app-data:lib/data/neijing_entries.dart#$entryId') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Neijing anchor and source ID do not agree.',
      );
    }

    NeijingEntry? entry;
    for (final candidate in kNeijingEntries) {
      if (candidate.id == entryId) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The referenced Neijing entry is not present in the bundled entry set.',
      );
    }
    if (ref.title != null && ref.title != entry.title) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Neijing title does not match the stable entry ID.',
      );
    }

    final content = <String, Object?>{
      'id': entry.id,
      'dimension': entry.dimension,
      'title': entry.title,
      'original': entry.original,
      'source': entry.source,
      'vernacular': entry.vernacular,
      'nishi': entry.nishi,
      'tags': entry.tags,
    };
    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedKnowledgeEntry._(
        ref: ref,
        title: entry.title,
        content: Map<String, Object?>.unmodifiable(content),
      ),
    );
  }

  static const medicalCaseModuleId = 'medical-cases';
  static const medicalCaseAssetVersion =
      'cases_table.md@eafd79148c7aeea2f9891738e153cd3009bd1670';

  static AiContextRef buildMedicalCaseContextRef(MedicalCase medicalCase) {
    return AiContextRef(
      kind: AiContextKind.caseRecord,
      moduleId: medicalCaseModuleId,
      anchorId: 'medical-case:${medicalCase.seq}',
      anchorVersion: medicalCaseAssetVersion,
      sourceId:
          'app-data:assets/medical_cases/cases_table.md#seq=${medicalCase.seq}',
      title: '#${medicalCase.seq} ${medicalCase.displayName}',
    );
  }

  static Future<AiContextResolution<AiResolvedKnowledgeEntry>>
      resolveMedicalCase({required AiContextRef ref}) async {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.caseRecord ||
        normalized.isEmpty ||
        ref.moduleId != medicalCaseModuleId ||
        ref.anchorVersion != medicalCaseAssetVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The medical-case reference is incomplete or does not match the bundled case assets.',
      );
    }

    final seqText = ref.anchorId.startsWith('medical-case:')
        ? ref.anchorId.substring('medical-case:'.length)
        : '';
    final seq = int.tryParse(seqText);
    if (seq == null ||
        seq < 2 ||
        ref.sourceId !=
            'app-data:assets/medical_cases/cases_table.md#seq=$seq') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The medical-case anchor and source reference do not agree.',
      );
    }

    // getAllMedicalCases retains the existing in-process cache used by the
    // medical-case library/detail screens. An empty result is UNKNOWN because
    // this helper intentionally swallows an asset-load failure as an empty set.
    final cases = await getAllMedicalCases();
    if (cases.isEmpty) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The medical-case asset set could not be confirmed as loaded.',
      );
    }

    MedicalCase? medicalCase;
    for (final candidate in cases) {
      if (candidate.seq == seq) {
        medicalCase = candidate;
        break;
      }
    }
    if (medicalCase == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The referenced internal medical-case record is not present in the bundled case table.',
      );
    }

    final expectedTitle =
        '#${medicalCase.seq} ${medicalCase.displayName}';
    if (ref.title != null && ref.title != expectedTitle) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The medical-case title does not match the resolved internal record.',
      );
    }

    final rawFields = <String, String>{
      'date': medicalCase.date,
      'patient': medicalCase.patient,
      'diagnosis': medicalCase.diagnosis,
      'mechanism': medicalCase.mechanism,
      'western': medicalCase.western,
      'formula': medicalCase.formula,
      'acupuncture': medicalCase.acupuncture,
      'method': medicalCase.method,
      'result': medicalCase.result,
      'advice': medicalCase.advice,
      'view': medicalCase.view,
    };
    final missingFields = rawFields.entries
        .where((entry) => entry.value.trim().isEmpty)
        .map((entry) => entry.key)
        .toList(growable: false);
    final content = <String, Object?>{
      'internalSequence': medicalCase.seq,
      'internalSequenceMeaning':
          '仅为 App 医案表内部主键，不是原始病例编号、文献页码或独立病例身份。',
      'displayName': medicalCase.displayName,
      for (final entry in rawFields.entries)
        entry.key:
            entry.value.trim().isEmpty ? 'MISSING' : entry.value,
      'missingFields': missingFields,
      'sourceLedger': medicalCase.sourceLedger.toJson(),
      'sourceTextVerificationStatus':
          medicalCase.sourceLedger.sourceStatus,
      'bibliographicLocatorStatus': medicalCase.sourceLedger.status,
    };

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedKnowledgeEntry._(
        ref: ref,
        title: expectedTitle,
        content: Map<String, Object?>.unmodifiable(content),
      ),
    );
  }

  static const ziweiModuleId = 'ziwei';
  static const ziweiSourceId = 'local-engine:ziwei-core@0.13.0';

  static AiContextResolution<AiResolvedToolField> resolveZiweiPalaceStars({
    required AiContextRef ref,
    required ZiweiChart chart,
    required String expectedSnapshotId,
    required String expectedRuleVersion,
    required Map<String, Object?> structuredSnapshot,
  }) {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.fieldValue ||
        normalized.isEmpty ||
        ref.moduleId != ziweiModuleId ||
        ref.sourceId != ziweiSourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The field reference is incomplete or does not identify a Ziwei source.',
      );
    }

    if (ref.snapshotId != expectedSnapshotId ||
        ref.anchorVersion != expectedSnapshotId ||
        ref.ruleVersion != expectedRuleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The field reference does not match the current result snapshot and rule version.',
      );
    }

    if (ref.anchorId !=
        'ziwei:result:$expectedSnapshotId:field:${ref.fieldPath}') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The field anchor does not match its snapshot and field path.',
      );
    }

    if (structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        structuredSnapshot['capabilityId'] != ziweiModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            'ziwei-structured-result-v1') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The structured result is not a successful Ziwei execution.',
      );
    }

    final snapshotId = structuredSnapshot['snapshotId'];
    final ruleVersion = structuredSnapshot['ruleVersion'];
    final sourceIds = structuredSnapshot['sourceIds'];
    final inputValue = structuredSnapshot['input'];
    final resultValue = structuredSnapshot['result'];
    if (snapshotId is! String ||
        ruleVersion is! String ||
        ruleVersion != expectedRuleVersion ||
        snapshotId != expectedSnapshotId ||
        sourceIds is! List ||
        !sourceIds.contains(ziweiSourceId) ||
        inputValue is! Map ||
        resultValue is! Map<String, Object?>) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The structured result is missing a required identity or payload field.',
      );
    }

    final actualSnapshotId =
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot);
    if (actualSnapshotId != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The structured result content no longer matches its immutable snapshot digest.',
      );
    }

    final pathMatch = RegExp(
      r'^palacesByPhysicalBranch\.(\d+)\.stars$',
    ).firstMatch(ref.fieldPath!);
    if (pathMatch == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The requested field path is not a supported Ziwei result field.',
      );
    }

    final palaceIndex = int.tryParse(pathMatch.group(1)!);
    if (palaceIndex == null || palaceIndex < 0 || palaceIndex > 11) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The requested physical palace index is outside the 12-palace result.',
      );
    }

    ZiweiPalace? palace;
    for (final candidate in chart.palaces) {
      if (candidate.index == palaceIndex) {
        palace = candidate;
        break;
      }
    }
    if (palace == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The requested palace field is not present in the resolved chart.',
      );
    }

    final palacesValue = resultValue['palacesByPhysicalBranch'];
    if (palacesValue is! List) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The structured snapshot does not contain the palace result collection.',
      );
    }
    Map<String, Object?>? palaceRecord;
    for (final candidate in palacesValue) {
      if (candidate is Map<String, Object?> &&
          candidate['physicalBranchIndex'] == palaceIndex) {
        palaceRecord = candidate;
        break;
      }
    }
    if (palaceRecord == null || palaceRecord['stars'] is! List) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.missing,
        reason: 'The requested palace field is not present in the structured snapshot.',
      );
    }
    if (palaceRecord['roleLabel'] != palace.roleLabel ||
        palaceRecord['branchLabel'] != palace.branchLabel ||
        palaceRecord['ganzhiLabel'] != palace.ganzhiLabel ||
        palaceRecord['isLife'] != palace.isLife ||
        palaceRecord['isBody'] != palace.isBody) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The palace identity and scope do not match the structured snapshot.',
      );
    }

    final snapshotStars = (palaceRecord['stars'] as List)
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
    final engineStars = palace.stars
        .map(serializeZiweiStarForAssistant)
        .toList(growable: false);
    if (snapshotStars.length != (palaceRecord['stars'] as List).length ||
        AiToolResultSnapshot.canonicalJson(snapshotStars) !=
            AiToolResultSnapshot.canonicalJson(engineStars)) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The field values do not match the current deterministic engine result.',
      );
    }

    final resolvedSnapshot = Map<String, Object?>.unmodifiable({
      ...structuredSnapshot,
    });
    final resolvedScope = Map<String, Object?>.unmodifiable({
      'palaceIndex': palace.index,
      'palaceRole': palace.roleLabel,
      'earthlyBranch': palace.branchLabel,
      'ganzhi': palace.ganzhiLabel,
      'scope': '仅本宫原局星曜；不包含流年流曜、其他宫位或大限解读',
    });

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolField._(
        ref: ref,
        fieldLabel: '${palace.roleLabel}星曜',
        fieldScope: resolvedScope,
        fieldValue: snapshotStars,
        fieldUnit: '不适用（离散星曜条目）',
        structuredSnapshot: resolvedSnapshot,
      ),
    );
  }

  static AiContextRef buildGuanshaResultContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final input = structuredSnapshot['input'];
    final arguments = input is Map ? input['arguments'] : null;
    final settings = input is Map ? input['settings'] : null;
    final sources = structuredSnapshot['sourceIds'];
    if (snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        structuredSnapshot['capabilityId'] !=
            GuanshaResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            GuanshaResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            GuanshaResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'explicitBirthDetails' ||
        arguments is! Map ||
        arguments.length != 4 ||
        arguments['birth_date'] is! String ||
        arguments['birth_time'] is! String ||
        !const {'male', 'female'}.contains(arguments['gender']) ||
        arguments['birthplace'] is! String ||
        (arguments['birthplace'] as String).trim().isEmpty ||
        settings is! Map ||
        settings['useTrueSolarTime'] is! bool ||
        settings['distinguishZiShi'] is! bool ||
        sources is! List ||
        sources.length != 3 ||
        sources[0] != GuanshaToolService.sourceId ||
        sources[1] != GuanshaToolService.dataSourceId ||
        sources[2] != GuanshaToolService.locationSourceId ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A Guansha reference requires a complete successful child-safety snapshot bound to the local engine and source assets.',
      );
    }
    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: GuanshaResultContextExecutor.moduleId,
      anchorId: 'guansha:result:$snapshotId',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: GuanshaResultContextExecutor.ruleVersion,
      sourceId: GuanshaToolService.sourceId,
      title: '小儿关煞结果',
    );
  }

  static Future<AiContextResolution<AiResolvedToolResult>>
      resolveGuanshaToolResult({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) async {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != GuanshaResultContextExecutor.moduleId ||
        ref.sourceId != GuanshaToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Guansha reference is incomplete or does not identify the local Guansha engine.',
      );
    }
    if (ref.ruleVersion != GuanshaResultContextExecutor.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The Guansha data, rule engine, city directory, Bazi engine, settings or locked packages changed.',
      );
    }

    final match = RegExp(r'^guansha:result:([0-9a-f]{64})$')
        .firstMatch(ref.anchorId);
    final snapshotId = ref.snapshotId;
    if (match == null ||
        snapshotId == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ref.anchorVersion != snapshotId ||
        match.group(1) != snapshotId ||
        ref.title != '小儿关煞结果') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Guansha anchor, title and immutable snapshot identity do not agree.',
      );
    }

    final input = structuredSnapshot['input'];
    final argumentsValue = input is Map ? input['arguments'] : null;
    final settings = input is Map ? input['settings'] : null;
    final sources = structuredSnapshot['sourceIds'];
    if (structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['capabilityId'] !=
            GuanshaResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            GuanshaResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            GuanshaResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'explicitBirthDetails' ||
        argumentsValue is! Map ||
        argumentsValue.length != 4 ||
        argumentsValue.entries.any(
          (entry) => entry.key is! String || entry.value is! String,
        ) ||
        !const {'male', 'female'}.contains(argumentsValue['gender']) ||
        (argumentsValue['birthplace'] as String? ?? '').trim().isEmpty ||
        settings is! Map ||
        settings['useTrueSolarTime'] is! bool ||
        settings['distinguishZiShi'] is! bool ||
        sources is! List ||
        sources.length != 3 ||
        sources[0] != GuanshaToolService.sourceId ||
        sources[1] != GuanshaToolService.dataSourceId ||
        sources[2] != GuanshaToolService.locationSourceId ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The supplied Guansha input, settings, sources or structured result no longer match its immutable digest.',
      );
    }

    final arguments = <String, String>{
      for (final entry in argumentsValue.entries)
        entry.key as String: entry.value as String,
    };
    final rebuilt = await GuanshaResultContextExecutor.executeWithSnapshot(
      arguments,
    );
    if (!rebuilt.succeeded || rebuilt.structuredSnapshot == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The local Guansha result could not be reconstructed from its recorded child birth input.',
      );
    }
    if (rebuilt.structuredSnapshot!['snapshotId'] != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The local Guansha calculation no longer matches this immutable result.',
      );
    }

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolResult._(
        ref: ref,
        structuredSnapshot: rebuilt.structuredSnapshot!,
      ),
    );
  }


  static AiContextRef buildDreamEntryContextRef({
    required Map<String, Object?> structuredSnapshot,
  }) {
    final snapshotId = structuredSnapshot['snapshotId'];
    final input = structuredSnapshot['input'];
    final selectedEntryId =
        input is Map ? input['selectedEntryId'] : null;
    final result = structuredSnapshot['result'];
    final values = result is Map ? result['values'] : null;
    final sources = structuredSnapshot['sourceIds'];
    if (snapshotId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        structuredSnapshot['capabilityId'] !=
            DreamResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            DreamResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            DreamResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input.length != 2 ||
        input['method'] != 'explicitEntrySelection' ||
        selectedEntryId is! String ||
        !RegExp(r'^[a-z0-9_-]{1,80}$').hasMatch(selectedEntryId) ||
        values is! Map ||
        values['词条 ID'] != selectedEntryId ||
        sources is! List ||
        sources.length != 1 ||
        sources.single != DreamToolService.sourceId ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A Dream reference requires one explicitly selected, successful local entry snapshot.',
      );
    }
    return AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: DreamResultContextExecutor.moduleId,
      anchorId: 'dream:entry:$selectedEntryId:result:$snapshotId',
      anchorVersion: snapshotId,
      snapshotId: snapshotId,
      ruleVersion: DreamResultContextExecutor.ruleVersion,
      sourceId: DreamToolService.sourceId,
      title: '周公解梦词条',
    );
  }

  static Future<AiContextResolution<AiResolvedToolResult>>
      resolveDreamEntryToolResult({
    required AiContextRef ref,
    required Map<String, Object?> structuredSnapshot,
  }) async {
    final normalized = AiContextRef.normalizeMetadata(ref.toMetadata());
    if (ref.kind != AiContextKind.toolResult ||
        normalized.isEmpty ||
        ref.moduleId != DreamResultContextExecutor.moduleId ||
        ref.sourceId != DreamToolService.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Dream reference is incomplete or does not identify the local dream dataset.',
      );
    }
    if (ref.ruleVersion != DreamResultContextExecutor.ruleVersion) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The local dream dataset or selection contract has changed.',
      );
    }

    final snapshotId = ref.snapshotId;
    final anchorMatch = RegExp(
      r'^dream:entry:([a-z0-9_-]{1,80}):result:([0-9a-f]{64})$',
    ).firstMatch(ref.anchorId);
    if (snapshotId == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotId) ||
        ref.anchorVersion != snapshotId ||
        anchorMatch == null ||
        anchorMatch.group(2) != snapshotId ||
        ref.title != '周公解梦词条') {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Dream entry anchor, title and immutable snapshot identity do not agree.',
      );
    }

    final selectedEntryId = anchorMatch.group(1)!;
    final input = structuredSnapshot['input'];
    final result = structuredSnapshot['result'];
    final values = result is Map ? result['values'] : null;
    final sources = structuredSnapshot['sourceIds'];
    if (structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['capabilityId'] !=
            DreamResultContextExecutor.moduleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            DreamResultContextExecutor.resultSchemaVersion ||
        structuredSnapshot['ruleVersion'] !=
            DreamResultContextExecutor.ruleVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input.length != 2 ||
        input['method'] != 'explicitEntrySelection' ||
        input['selectedEntryId'] != selectedEntryId ||
        values is! Map ||
        values['词条 ID'] != selectedEntryId ||
        result is! Map ||
        result['title'] != '周公解梦' ||
        sources is! List ||
        sources.length != 1 ||
        sources.single != DreamToolService.sourceId ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The supplied Dream entry identity, source or structured result no longer matches its immutable digest.',
      );
    }

    final rebuilt = DreamResultContextExecutor.executeWithSnapshot(
      selectedEntryId: selectedEntryId,
    );
    if (!rebuilt.succeeded || rebuilt.structuredSnapshot == null) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The selected Dream entry could not be reconstructed from the current local dataset.',
      );
    }
    if (rebuilt.structuredSnapshot!['snapshotId'] != snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The selected local Dream entry no longer matches this immutable snapshot.',
      );
    }

    return AiContextResolution(
      status: AiContextResolutionStatus.resolved,
      value: AiResolvedToolResult._(
        ref: ref,
        structuredSnapshot: rebuilt.structuredSnapshot!,
      ),
    );
  }

}
