import '../models/ai_context_ref.dart';
import '../models/formula.dart';
import '../data/formula_repository.dart';
import 'ai_tool_result_snapshot.dart';
import 'assistant_chart_result_formatter.dart';
import 'ziwei_engine.dart';

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

/// Resolves app-controlled field paths against a real in-memory engine result.
class AiContextResolver {
  const AiContextResolver._();


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

/// Resolves app-controlled field paths against a real engine result and
/// verifies that the full structured snapshot digest still matches its data.
class AiContextResolver {
  const AiContextResolver._();

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
