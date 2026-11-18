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
