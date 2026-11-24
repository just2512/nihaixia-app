import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/context_resolution_gateway.dart';

class _ResolvedValue {
  const _ResolvedValue(this.ref);
  final AiContextRef ref;
}

AiContextRef _reference({
  String anchorId = 'formula:gui-zhi-tang',
  String anchorVersion = 'asset-sha256:abc123',
}) =>
    AiContextRef(
      kind: AiContextKind.formula,
      moduleId: 'formula',
      anchorId: anchorId,
      anchorVersion: anchorVersion,
      sourceId: 'asset:assets/data/formulas.json',
      title: '桂枝汤',
    );

void main() {
  group('ContextResolutionGateway', () {
    test('validates a source reference without any feature entitlement', () async {
      final result = await const ContextResolutionGateway()
          .validateReference(_reference());

      expect(result.status, ContextResolutionGatewayStatus.referenceValidated);
      expect(result.isReferenceValid, isTrue);
      expect(result.isResolved, isFalse);
    });

    test('resolves only the exact requested anchor', () async {
      final reference = _reference();
      var resolverCalls = 0;
      final result = await const ContextResolutionGateway()
          .resolve<_ResolvedValue>(
        reference: reference,
        resolver: () {
          resolverCalls += 1;
          return AiContextResolution<_ResolvedValue>(
            status: AiContextResolutionStatus.resolved,
            value: _ResolvedValue(reference),
          );
        },
        referenceOf: (value) => value.ref,
      );

      expect(result.status, ContextResolutionGatewayStatus.resolved);
      expect(result.isResolved, isTrue);
      expect(identical(result.value!.ref, reference), isTrue);
      expect(resolverCalls, 1);
    });

    test('a resolver result from another anchor is rejected as stale', () async {
      final result = await const ContextResolutionGateway()
          .resolve<_ResolvedValue>(
        reference: _reference(),
        resolver: () => AiContextResolution<_ResolvedValue>(
          status: AiContextResolutionStatus.resolved,
          value: _ResolvedValue(
            _reference(anchorId: 'formula:ma-huang-tang'),
          ),
        ),
        referenceOf: (value) => value.ref,
      );

      expect(result.status, ContextResolutionGatewayStatus.stale);
      expect(result.value, isNull);
    });

    test('source statuses remain distinct', () async {
      const gateway = ContextResolutionGateway();

      Future<ContextResolutionGatewayStatus> run(
        AiContextResolutionStatus status,
      ) async {
        final result = await gateway.resolve<_ResolvedValue>(
          reference: _reference(),
          resolver: () => AiContextResolution<_ResolvedValue>(
            status: status,
            reason: 'source-${status.name}',
          ),
          referenceOf: (value) => value.ref,
        );
        return result.status;
      }

      expect(await run(AiContextResolutionStatus.missing), ContextResolutionGatewayStatus.missing);
      expect(await run(AiContextResolutionStatus.unknown), ContextResolutionGatewayStatus.unknown);
      expect(await run(AiContextResolutionStatus.stale), ContextResolutionGatewayStatus.stale);
      expect(await run(AiContextResolutionStatus.denied), ContextResolutionGatewayStatus.sourceDenied);
    });

    test('malformed persisted metadata is rejected before resolver execution', () async {
      var resolverCalls = 0;
      final result = await const ContextResolutionGateway().resolve<_ResolvedValue>(
        reference: AiContextRef(
          kind: AiContextKind.formula,
          moduleId: 'formula',
          anchorId: 'formula:gui-zhi-tang',
          anchorVersion: 'asset-sha256:abc123',
          sourceId: 'asset:assets/data/formulas.json',
          title: '桂枝汤',
        ).copyWith(anchorId: ' '),
        resolver: () {
          resolverCalls += 1;
          return AiContextResolution<_ResolvedValue>(
            status: AiContextResolutionStatus.resolved,
            value: _ResolvedValue(_reference()),
          );
        },
        referenceOf: (value) => value.ref,
      );
      expect(result.status, ContextResolutionGatewayStatus.invalidReference);
      expect(resolverCalls, 0);
    });

    test('unknown persisted metadata fields are rejected', () {
      final reference = AiContextRef.fromMetadata({
        ..._reference().toMetadata(),
        'unrecognizedPrivilege': 'true',
      });
      expect(reference, isNull);
    });

    test('history restore and each subsequent turn validate the same reference', () async {
      const gateway = ContextResolutionGateway();
      final reference = _reference();

      final restore = await gateway.validateReference(reference);
      final nextTurn = await gateway.validateReference(reference);

      expect(restore.status, ContextResolutionGatewayStatus.referenceValidated);
      expect(nextTurn.status, ContextResolutionGatewayStatus.referenceValidated);
    });

    test('resolver exception never becomes resolved context', () async {
      final result = await const ContextResolutionGateway()
          .resolve<_ResolvedValue>(
        reference: _reference(),
        resolver: () => throw StateError('asset loader failure'),
        referenceOf: (value) => value.ref,
      );

      expect(result.status, ContextResolutionGatewayStatus.resolverFailure);
      expect(result.isResolved, isFalse);
      expect(result.reason, 'StateError');
    });
  });
}
