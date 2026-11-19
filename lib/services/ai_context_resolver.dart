import '../models/ai_context_ref.dart';
import '../models/formula.dart';
import '../models/herb.dart';
import '../data/formula_repository.dart';
import '../data/herb_repository.dart';
import '../data/medical_case_data.dart';
import '../data/neijing_entries.dart';
import 'ai_tool_result_snapshot.dart';
import 'assistant_chart_result_formatter.dart';
import 'ziwei_engine.dart';
import 'yunqi_tool_executor.dart';
import 'almanac_tool_executor.dart';
import 'bazi_context_snapshot.dart';
import 'yijing_tool_executor.dart';
import 'meihua_tool_executor.dart';
import 'xiaoliuren_tool_executor.dart';
import 'huangdi_siji_result_context_executor.dart';
import 'huangdi_siji_tool_executor.dart';
import 'solar_term_result_context_executor.dart';
import 'solar_term_tool_executor.dart';
import 'ziwuliuzhu_tool_executor.dart';
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
        ruleVersion != XiaoliurenToolExecutor.ruleVersion ||
        structuredSnapshot['capabilityId'] != xiaoliurenModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            XiaoliurenToolExecutor.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'time' ||
        input['executionDate'] is! String ||
        arguments is! Map ||
        arguments.length != 3 ||
        date is! String ||
        hour is! String ||
        rule is! String ||
        !XiaoliurenToolExecutor.hourBranches.contains(hour) ||
        !const {'common', 'duoneng'}.contains(rule) ||
        sourceIds is! List ||
        !sourceIds.contains(XiaoliurenToolExecutor.sourceId) ||
        !sourceIds.contains(XiaoliurenToolExecutor.ruleDataSourceId) ||
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
      sourceId: XiaoliurenToolExecutor.sourceId,
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
        ref.sourceId != XiaoliurenToolExecutor.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Xiaoliuren reference is incomplete or does not identify the local Xiaoliuren engine.',
      );
    }
    if (ref.ruleVersion != XiaoliurenToolExecutor.ruleVersion) {
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
        !XiaoliurenToolExecutor.hourBranches.contains(anchorMatch.group(3))) {
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
        structuredSnapshot['ruleVersion'] != XiaoliurenToolExecutor.ruleVersion ||
        structuredSnapshot['resultSchemaVersion'] !=
            XiaoliurenToolExecutor.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        structuredSnapshot['capabilityId'] != xiaoliurenModuleId ||
        sourceIds is! List ||
        !sourceIds.contains(XiaoliurenToolExecutor.sourceId) ||
        !sourceIds.contains(XiaoliurenToolExecutor.ruleDataSourceId)) {
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

      final reconstructed = XiaoliurenToolExecutor.executeWithSnapshot(
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
        ruleVersion != AlmanacToolExecutor.ruleVersion ||
        structuredSnapshot['capabilityId'] != almanacModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            AlmanacToolExecutor.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['date'] is! String ||
        sourceIds is! List ||
        !sourceIds.contains(AlmanacToolExecutor.sourceId) ||
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
      sourceId: AlmanacToolExecutor.sourceId,
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
        ref.sourceId != AlmanacToolExecutor.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The almanac reference is incomplete or does not identify the local almanac engine.',
      );
    }
    if (ref.ruleVersion != AlmanacToolExecutor.ruleVersion) {
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
      final snapshot = AlmanacToolExecutor.createStructuredSnapshot(date!);
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
        ruleVersion != ZiWuLiuZhuToolExecutor.ruleVersion ||
        structuredSnapshot['capabilityId'] != ziWuLiuZhuModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            ZiWuLiuZhuToolExecutor.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'deviceLocalDateTime' ||
        arguments is! Map ||
        arguments.length != 1 ||
        at is! String ||
        sourceIds is! List ||
        !sourceIds.contains(ZiWuLiuZhuToolExecutor.sourceId) ||
        !sourceIds.contains(ZiWuLiuZhuToolExecutor.referenceSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      throw ArgumentError(
        'A ZiWuLiuZhu context reference requires a complete, source-bound successful snapshot.',
      );
    }

    final execution = ZiWuLiuZhuToolExecutor.executeWithSnapshot({'at': at});
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
      sourceId: ZiWuLiuZhuToolExecutor.sourceId,
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
        ref.sourceId != ZiWuLiuZhuToolExecutor.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The ZiWuLiuZhu reference is incomplete or does not identify the local calculation engine.',
      );
    }
    if (ref.ruleVersion != ZiWuLiuZhuToolExecutor.ruleVersion) {
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
        structuredSnapshot['ruleVersion'] != ZiWuLiuZhuToolExecutor.ruleVersion ||
        structuredSnapshot['resultSchemaVersion'] !=
            ZiWuLiuZhuToolExecutor.resultSchemaVersion ||
        structuredSnapshot['capabilityId'] != ziWuLiuZhuModuleId ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] != 'deviceLocalDateTime' ||
        arguments is! Map ||
        arguments.length != 1 ||
        arguments['at'] != at ||
        sourceIds is! List ||
        !sourceIds.contains(ZiWuLiuZhuToolExecutor.sourceId) ||
        !sourceIds.contains(ZiWuLiuZhuToolExecutor.referenceSourceId) ||
        AiToolResultSnapshot.createStructuredId(snapshot: structuredSnapshot) !=
            snapshotId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.stale,
        reason: 'The supplied ZiWuLiuZhu result or its provenance no longer matches the immutable snapshot digest.',
      );
    }

    final execution =
        ZiWuLiuZhuToolExecutor.executeWithSnapshot({'at': at});
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
        !SolarTermToolExecutor.termNames.contains(term) ||
        sourceIds is! List ||
        sourceIds.length != 2 ||
        !sourceIds.contains(SolarTermToolExecutor.sourceId) ||
        !sourceIds.contains(SolarTermToolExecutor.knowledgeSourceId) ||
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
      sourceId: SolarTermToolExecutor.sourceId,
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
        ref.sourceId != SolarTermToolExecutor.sourceId) {
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
    if (!SolarTermToolExecutor.termNames.contains(term) ||
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
        !sources.contains(SolarTermToolExecutor.sourceId) ||
        !sources.contains(SolarTermToolExecutor.knowledgeSourceId) ||
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
        !sourceIds.contains(HuangdiSijiToolExecutor.sourceId) ||
        !sourceIds.contains(HuangdiSijiToolExecutor.dataSourceId) ||
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
      sourceId: HuangdiSijiToolExecutor.sourceId,
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
        ref.sourceId != HuangdiSijiToolExecutor.sourceId) {
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
        !sources.contains(HuangdiSijiToolExecutor.sourceId) ||
        !sources.contains(HuangdiSijiToolExecutor.dataSourceId) ||
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
        ruleVersion != YunQiToolExecutor.ruleVersion ||
        structuredSnapshot['capabilityId'] != yunqiModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            YunQiToolExecutor.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['date'] is! String ||
        sourceIds is! List ||
        !sourceIds.contains(YunQiToolExecutor.sourceId) ||
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
      sourceId: YunQiToolExecutor.sourceId,
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
        ref.sourceId != YunQiToolExecutor.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YunQi reference is incomplete or does not identify the local YunQi engine.',
      );
    }
    if (ref.ruleVersion != YunQiToolExecutor.ruleVersion) {
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
      final snapshot = YunQiToolExecutor.createStructuredSnapshot(date!);
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
        ruleVersion != YiJingToolExecutor.ruleVersion ||
        structuredSnapshot['capabilityId'] != yijingModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            YiJingToolExecutor.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        input is! Map ||
        input['method'] is! String ||
        sourceIds is! List ||
        !sourceIds.contains(YiJingToolExecutor.sourceId) ||
        !sourceIds.contains(YiJingToolExecutor.dataSourceId) ||
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
      sourceId: YiJingToolExecutor.sourceId,
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
        ref.sourceId != YiJingToolExecutor.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YiJing reference is incomplete or does not identify the local YiJing engine.',
      );
    }
    if (ref.ruleVersion != YiJingToolExecutor.ruleVersion) {
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
        structuredSnapshot['ruleVersion'] != YiJingToolExecutor.ruleVersion ||
        structuredSnapshot['resultSchemaVersion'] !=
            YiJingToolExecutor.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        structuredSnapshot['capabilityId'] != yijingModuleId ||
        structuredSnapshot['sourceIds'] is! List ||
        !(structuredSnapshot['sourceIds'] as List)
            .contains(YiJingToolExecutor.sourceId) ||
        !(structuredSnapshot['sourceIds'] as List)
            .contains(YiJingToolExecutor.dataSourceId)) {
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
          YiJingToolExecutor.createStructuredSnapshot(arguments);
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
        resultRef.ruleVersion != YiJingToolExecutor.ruleVersion ||
        resultRef.sourceId != YiJingToolExecutor.sourceId ||
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
      sourceId: YiJingToolExecutor.sourceId,
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
        ref.sourceId != YiJingToolExecutor.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The YiJing field reference is incomplete or does not identify the local YiJing engine.',
      );
    }
    if (ref.ruleVersion != YiJingToolExecutor.ruleVersion) {
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
      sourceId: YiJingToolExecutor.sourceId,
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
        ruleVersion != MeihuaToolExecutor.ruleVersion ||
        structuredSnapshot['capabilityId'] != meihuaModuleId ||
        structuredSnapshot['resultSchemaVersion'] !=
            MeihuaToolExecutor.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        method is! String ||
        !const {'time', 'number', 'random'}.contains(method) ||
        arguments is! Map ||
        arguments.entries.any(
          (entry) => entry.key is! String || entry.value is! String,
        ) ||
        arguments['method'] != method ||
        sourceIds is! List ||
        !sourceIds.contains(MeihuaToolExecutor.sourceId) ||
        !sourceIds.contains(MeihuaToolExecutor.dataSourceId) ||
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
      sourceId: MeihuaToolExecutor.sourceId,
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
        ref.sourceId != MeihuaToolExecutor.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Meihua reference is incomplete or does not identify the local Meihua engine.',
      );
    }
    if (ref.ruleVersion != MeihuaToolExecutor.ruleVersion) {
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
            (!MeihuaToolExecutor.earthlyBranches.contains(
              arguments['hour_branch'],
            ) ||
                arguments.containsKey('first') ||
                arguments.containsKey('second'))) ||
        (method == 'random' &&
            (arguments.containsKey('first') ||
                arguments.containsKey('second') ||
                arguments.containsKey('hour_branch'))) ||
        structuredSnapshot['snapshotId'] != snapshotId ||
        structuredSnapshot['ruleVersion'] != MeihuaToolExecutor.ruleVersion ||
        structuredSnapshot['resultSchemaVersion'] !=
            MeihuaToolExecutor.resultSchemaVersion ||
        structuredSnapshot['executionStatus'] != 'SUCCESS' ||
        structuredSnapshot['capabilityId'] != meihuaModuleId ||
        sourceIds is! List ||
        !sourceIds.contains(MeihuaToolExecutor.sourceId) ||
        !sourceIds.contains(MeihuaToolExecutor.dataSourceId) ||
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
        resultRef.ruleVersion != MeihuaToolExecutor.ruleVersion ||
        resultRef.sourceId != MeihuaToolExecutor.sourceId ||
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
      sourceId: MeihuaToolExecutor.sourceId,
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
        ref.sourceId != MeihuaToolExecutor.sourceId) {
      return const AiContextResolution(
        status: AiContextResolutionStatus.unknown,
        reason: 'The Meihua field reference is incomplete or does not identify the local Meihua engine.',
      );
    }
    if (ref.ruleVersion != MeihuaToolExecutor.ruleVersion) {
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
      sourceId: MeihuaToolExecutor.sourceId,
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
      'cases_table.md@eafd79148c7aeea2f9891738e153cd3009bd1670;'
      'source_ledger.json@a61bd55f256adc620b7983fe2dd07a5d46721f89';

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
}
