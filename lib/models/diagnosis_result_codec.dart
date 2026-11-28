import 'diagnosis.dart';

/// Versioned, lossless JSON codec for a completed deterministic diagnosis.
///
/// Historical results are snapshots, not instructions to rerun the current
/// diagnostic engine. Decoding therefore reconstructs the stored result and
/// never recalculates it from the interview answers.
class DiagnosisResultCodec {
  const DiagnosisResultCodec._();

  static const int schemaVersion = 1;

  static Map<String, dynamic> toJson(DiagnosisResult result) => {
        'schemaVersion': schemaVersion,
        'meridian': result.meridian,
        'pattern': result.pattern,
        'patternDetail': result.patternDetail,
        'formula': result.formula,
        'recommendedFormulas': result.recommendedFormulas,
        'explanation': result.explanation,
        'confidence': result.confidence,
        'matchedSymptoms': result.matchedSymptoms,
        'followUpQuestions': result.followUpQuestions,
        'combinedMeridian': result.combinedMeridian,
        'tongueCoating': result.tongueCoating,
        'tongueShape': result.tongueShape,
        'pulseType': result.pulseType,
        'pulseTypeSecondary': result.pulseTypeSecondary,
        if (result.careAdvice != null) 'careAdvice': result.careAdvice,
        if (result.differential != null)
          'differential': _differentialToJson(result.differential!),
        if (result.prescription != null)
          'prescription': _prescriptionToJson(result.prescription!),
        'answers': result.answers,
        if (result.trueFalseHeatCold != null)
          'trueFalseHeatCold': _trueFalseToJson(result.trueFalseHeatCold!),
        if (result.medicationRules != null)
          'medicationRules': result.medicationRules!
              .map(_medicationRuleToJson)
              .toList(growable: false),
        if (result.sweatingContraindications != null)
          'sweatingContraindications': result.sweatingContraindications!
              .map(_sweatingToJson)
              .toList(growable: false),
        if (result.bloodStasisSigns != null)
          'bloodStasisSigns': result.bloodStasisSigns!
              .map(_bloodStasisToJson)
              .toList(growable: false),
        if (result.pulseCombination != null)
          'pulseCombination': _pulseCombinationToJson(result.pulseCombination!),
        if (result.facialComplexion != null)
          'facialComplexion': _facialComplexionToJson(result.facialComplexion!),
        if (result.patternDifferential != null)
          'patternDifferential':
              _patternDifferentialToJson(result.patternDifferential!),
        if (result.transmission != null)
          'transmission': _transmissionToJson(result.transmission!),
        'transmissionWarning': result.transmissionWarning,
        'pulseTongueContradiction': result.pulseTongueContradiction,
        if (result.pulseTongueAssessment != null)
          'pulseTongueAssessment':
              _pulseTongueAssessmentToJson(result.pulseTongueAssessment!),
        'recommendConsult': result.recommendConsult,
      };

  static DiagnosisResult fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw FormatException(
        'Unsupported diagnosis result schema: ${json['schemaVersion']}',
      );
    }
    final answers = _object(json['answers'], 'answers');
    final careAdvice = json['careAdvice'] == null
        ? null
        : _stringListMap(json['careAdvice'], 'careAdvice');
    final rawMedicationRules = _optionalObjectList(json['medicationRules'], 'medicationRules');
    final rawSweating = _optionalObjectList(
      json['sweatingContraindications'],
      'sweatingContraindications',
    );
    final rawBloodStasis = _optionalObjectList(json['bloodStasisSigns'], 'bloodStasisSigns');

    return DiagnosisResult(
      meridian: _requiredString(json, 'meridian'),
      pattern: _requiredString(json, 'pattern'),
      patternDetail: _stringOrDefault(json, 'patternDetail', ''),
      formula: _requiredString(json, 'formula'),
      recommendedFormulas: _stringList(json['recommendedFormulas'], 'recommendedFormulas'),
      explanation: _stringOrDefault(json, 'explanation', ''),
      confidence: _number(json, 'confidence'),
      matchedSymptoms: _stringList(json['matchedSymptoms'], 'matchedSymptoms'),
      followUpQuestions: _stringList(json['followUpQuestions'], 'followUpQuestions'),
      combinedMeridian: _optionalString(json, 'combinedMeridian'),
      tongueCoating: _optionalString(json, 'tongueCoating'),
      tongueShape: _optionalString(json, 'tongueShape'),
      pulseType: _optionalString(json, 'pulseType'),
      pulseTypeSecondary: _optionalString(json, 'pulseTypeSecondary'),
      careAdvice: careAdvice,
      differential: json['differential'] == null
          ? null
          : _differentialFromJson(_object(json['differential'], 'differential')),
      prescription: json['prescription'] == null
          ? null
          : _prescriptionFromJson(_object(json['prescription'], 'prescription')),
      answers: answers,
      trueFalseHeatCold: json['trueFalseHeatCold'] == null
          ? null
          : _trueFalseFromJson(_object(json['trueFalseHeatCold'], 'trueFalseHeatCold')),
      medicationRules: rawMedicationRules?.map(_medicationRuleFromJson).toList(growable: false),
      sweatingContraindications: rawSweating?.map(_sweatingFromJson).toList(growable: false),
      bloodStasisSigns: rawBloodStasis?.map(_bloodStasisFromJson).toList(growable: false),
      pulseCombination: json['pulseCombination'] == null
          ? null
          : _pulseCombinationFromJson(_object(json['pulseCombination'], 'pulseCombination')),
      facialComplexion: json['facialComplexion'] == null
          ? null
          : _facialComplexionFromJson(_object(json['facialComplexion'], 'facialComplexion')),
      patternDifferential: json['patternDifferential'] == null
          ? null
          : _patternDifferentialFromJson(_object(json['patternDifferential'], 'patternDifferential')),
      transmission: json['transmission'] == null
          ? null
          : _transmissionFromJson(_object(json['transmission'], 'transmission')),
      transmissionWarning: _optionalString(json, 'transmissionWarning'),
      pulseTongueContradiction: _optionalString(json, 'pulseTongueContradiction'),
      pulseTongueAssessment: json['pulseTongueAssessment'] == null
          ? null
          : _pulseTongueAssessmentFromJson(
              _object(json['pulseTongueAssessment'], 'pulseTongueAssessment'),
            ),
      recommendConsult: _boolean(json, 'recommendConsult'),
    );
  }

  static Map<String, dynamic> _differentialToJson(DifferentialDiagnosisResult value) => {
        'name1': value.name1,
        'formula1': value.formula1,
        'name2': value.name2,
        'formula2': value.formula2,
        'keyDifference': value.keyDifference,
        'details': value.details,
      };

  static DifferentialDiagnosisResult _differentialFromJson(Map<String, dynamic> value) =>
      DifferentialDiagnosisResult(
        name1: _requiredString(value, 'name1'),
        formula1: _requiredString(value, 'formula1'),
        name2: _requiredString(value, 'name2'),
        formula2: _requiredString(value, 'formula2'),
        keyDifference: _requiredString(value, 'keyDifference'),
        details: _stringMap(value['details'], 'differential.details'),
      );

  static Map<String, dynamic> _prescriptionToJson(FormulaPrescription value) => {
        'formulaName': value.formulaName,
        'components': value.components.map((item) => {
          'name': item.name,
          'dosage': item.dosage,
          'role': item.role,
        }).toList(growable: false),
        'dosage': value.dosage,
        'preparation': value.preparation,
        'contraindication': value.contraindication,
        if (value.modifications != null)
          'modifications': value.modifications!.map((item) => {
            'condition': item.condition,
            'symptom': item.symptom,
            'type': item.type.name,
            'herbName': item.herbName,
            'replaceWith': item.replaceWith,
            'resultFormula': item.resultFormula,
            'description': item.description,
          }).toList(growable: false),
      };

  static FormulaPrescription _prescriptionFromJson(Map<String, dynamic> value) {
    final components = _requiredObjectList(value['components'], 'prescription.components');
    final modifications = _optionalObjectList(value['modifications'], 'prescription.modifications');
    return FormulaPrescription(
      formulaName: _requiredString(value, 'formulaName'),
      components: components.map((item) => PrescriptionComponent(
        name: _requiredString(item, 'name'),
        dosage: _stringOrDefault(item, 'dosage', ''),
        role: _stringOrDefault(item, 'role', ''),
      )).toList(growable: false),
      dosage: _stringOrDefault(value, 'dosage', ''),
      preparation: _stringOrDefault(value, 'preparation', ''),
      contraindication: _stringOrDefault(value, 'contraindication', ''),
      modifications: modifications?.map((item) {
        final typeName = _requiredString(item, 'type');
        final type = ModificationType.values.where((entry) => entry.name == typeName);
        if (type.isEmpty) throw FormatException('Unknown formula modification type: $typeName');
        return FormulaModification(
          condition: _requiredString(item, 'condition'),
          symptom: _requiredString(item, 'symptom'),
          type: type.first,
          herbName: _requiredString(item, 'herbName'),
          replaceWith: _optionalString(item, 'replaceWith'),
          resultFormula: _stringOrDefault(item, 'resultFormula', ''),
          description: _stringOrDefault(item, 'description', ''),
        );
      }).toList(growable: false),
    );
  }

  static Map<String, dynamic> _trueFalseToJson(TrueFalseHeatCold value) => {
        'type': value.type,
        'description': value.description,
        'dimensions': value.dimensions,
      };

  static TrueFalseHeatCold _trueFalseFromJson(Map<String, dynamic> value) =>
      TrueFalseHeatCold(
        type: _requiredString(value, 'type'),
        description: _requiredString(value, 'description'),
        dimensions: _stringMap(value['dimensions'], 'trueFalseHeatCold.dimensions'),
      );

  static Map<String, dynamic> _medicationRuleToJson(MedicationRule value) => {
        'category': value.category,
        'condition': value.condition,
        'prohibition': value.prohibition,
        'reason': value.reason,
        'emergencyTreatment': value.emergencyTreatment,
      };

  static MedicationRule _medicationRuleFromJson(Map<String, dynamic> value) =>
      MedicationRule(
        category: _requiredString(value, 'category'),
        condition: _requiredString(value, 'condition'),
        prohibition: _requiredString(value, 'prohibition'),
        reason: _requiredString(value, 'reason'),
        emergencyTreatment: _stringOrDefault(value, 'emergencyTreatment', ''),
      );

  static Map<String, dynamic> _sweatingToJson(SweatingContraindication value) => {
        'condition': value.condition,
        'reason': value.reason,
        'consequence': value.consequence,
      };

  static SweatingContraindication _sweatingFromJson(Map<String, dynamic> value) =>
      SweatingContraindication(
        condition: _requiredString(value, 'condition'),
        reason: _requiredString(value, 'reason'),
        consequence: _requiredString(value, 'consequence'),
      );

  static Map<String, dynamic> _bloodStasisToJson(BloodStasisSign value) => {
        'method': value.method,
        'description': value.description,
        'clinicalSignificance': value.clinicalSignificance,
      };

  static BloodStasisSign _bloodStasisFromJson(Map<String, dynamic> value) =>
      BloodStasisSign(
        method: _requiredString(value, 'method'),
        description: _requiredString(value, 'description'),
        clinicalSignificance: _requiredString(value, 'clinicalSignificance'),
      );

  static Map<String, dynamic> _pulseCombinationToJson(PulseCombination value) => {
        'pulse1': value.pulse1,
        'pulse2': value.pulse2,
        'meridian': value.meridian,
        'formula': value.formula,
        'description': value.description,
      };

  static PulseCombination _pulseCombinationFromJson(Map<String, dynamic> value) =>
      PulseCombination(
        pulse1: _requiredString(value, 'pulse1'),
        pulse2: _requiredString(value, 'pulse2'),
        meridian: _requiredString(value, 'meridian'),
        formula: _requiredString(value, 'formula'),
        description: _requiredString(value, 'description'),
      );

  static Map<String, dynamic> _facialComplexionToJson(FacialComplexion value) => {
        'color': value.color,
        'meridian': value.meridian,
        'formula': value.formula,
        'description': value.description,
      };

  static FacialComplexion _facialComplexionFromJson(Map<String, dynamic> value) =>
      FacialComplexion(
        color: _requiredString(value, 'color'),
        meridian: _requiredString(value, 'meridian'),
        formula: _requiredString(value, 'formula'),
        description: _requiredString(value, 'description'),
      );

  static Map<String, dynamic> _patternDifferentialToJson(PatternDifferential value) => {
        'pattern1': value.pattern1,
        'pattern2': value.pattern2,
        'classicText': value.classicText,
        'keyPoint': value.keyPoint,
        'niNote': value.niNote,
      };

  static PatternDifferential _patternDifferentialFromJson(Map<String, dynamic> value) =>
      PatternDifferential(
        pattern1: _requiredString(value, 'pattern1'),
        pattern2: _requiredString(value, 'pattern2'),
        classicText: _requiredString(value, 'classicText'),
        keyPoint: _requiredString(value, 'keyPoint'),
        niNote: _requiredString(value, 'niNote'),
      );

  static Map<String, dynamic> _transmissionToJson(MeridianTransmission value) => {
        'from': value.from,
        'to': value.to,
        'sign': value.sign,
        'treatment': value.treatment,
      };

  static MeridianTransmission _transmissionFromJson(Map<String, dynamic> value) =>
      MeridianTransmission(
        from: _requiredString(value, 'from'),
        to: _requiredString(value, 'to'),
        sign: _requiredString(value, 'sign'),
        treatment: _requiredString(value, 'treatment'),
      );

  static Map<String, dynamic> _pulseTongueAssessmentToJson(PulseTongueAssessment value) => {
        'status': value.status,
        'supportingEvidence': value.supportingEvidence,
        'contradictingEvidence': value.contradictingEvidence,
        'missingEvidence': value.missingEvidence,
        'followUpQuestionKeys': value.followUpQuestionKeys,
        'followUpQuestions': value.followUpQuestions,
      };

  static PulseTongueAssessment _pulseTongueAssessmentFromJson(Map<String, dynamic> value) =>
      PulseTongueAssessment(
        status: _requiredString(value, 'status'),
        supportingEvidence: _stringList(value['supportingEvidence'], 'supportingEvidence'),
        contradictingEvidence: _stringList(value['contradictingEvidence'], 'contradictingEvidence'),
        missingEvidence: _stringList(value['missingEvidence'], 'missingEvidence'),
        followUpQuestionKeys: _stringList(value['followUpQuestionKeys'], 'followUpQuestionKeys'),
        followUpQuestions: _stringList(value['followUpQuestions'], 'followUpQuestions'),
      );

  static Map<String, dynamic> _object(Object? value, String field) {
    if (value is! Map) throw FormatException('$field must be an object');
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) throw FormatException('$field has a non-string key');
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static List<Map<String, dynamic>> _requiredObjectList(Object? value, String field) {
    if (value is! List) throw FormatException('$field must be a list');
    return value.map((item) => _object(item, field)).toList(growable: false);
  }

  static List<Map<String, dynamic>>? _optionalObjectList(Object? value, String field) =>
      value == null ? null : _requiredObjectList(value, field);

  static String _requiredString(Map<String, dynamic> value, String field) {
    final item = value[field];
    if (item is! String) throw FormatException('$field must be a string');
    return item;
  }

  static String _stringOrDefault(Map<String, dynamic> value, String field, String fallback) {
    final item = value[field];
    if (item == null) return fallback;
    if (item is! String) throw FormatException('$field must be a string');
    return item;
  }

  static String? _optionalString(Map<String, dynamic> value, String field) {
    final item = value[field];
    if (item == null) return null;
    if (item is! String) throw FormatException('$field must be a string or null');
    return item;
  }

  static List<String> _stringList(Object? value, String field) {
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException('$field must be a list of strings');
    }
    return value.cast<String>();
  }

  static Map<String, String> _stringMap(Object? value, String field) {
    final map = _object(value, field);
    if (map.values.any((item) => item is! String)) {
      throw FormatException('$field must contain only string values');
    }
    return map.map((key, item) => MapEntry(key, item as String));
  }

  static Map<String, List<String>> _stringListMap(Object? value, String field) {
    final map = _object(value, field);
    return map.map((key, item) => MapEntry(key, _stringList(item, '$field.$key')));
  }

  static double _number(Map<String, dynamic> value, String field) {
    final item = value[field];
    if (item is! num) throw FormatException('$field must be numeric');
    return item.toDouble();
  }

  static bool _boolean(Map<String, dynamic> value, String field) {
    final item = value[field];
    if (item is! bool) throw FormatException('$field must be boolean');
    return item;
  }
}
