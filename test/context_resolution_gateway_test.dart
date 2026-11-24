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
}) => AiContextRef(
  kind: AiContextKind.formula,
  moduleId: 'formula',
  anchorId: anchorId,
  anchorVersion: anchorVersion,
  sourceId: 'asset:assets/data/formulas.json',
  title: '桂枝汤',
);

void main() {
  group('ContextResolutionGateway', () {
    test('validates a complete stable reference without entitlement dependency', () async {
      final result = await const ContextResolutionGateway().validateReference(_reference());
      expect(result.status, ContextResolutionGatewayStatus.validReference);
      expect(result.isValidReference, isTrue);
    });

    test('rejects malformed persisted metadata before resolver execution', () async {
      const metadata = <String, String>{
        'kind': 'toolResult', 'moduleId': 'yunqi',
        'anchorId': 'yunqi:result:abc', 'anchorVersion': 'abc',
        'snapshotId': 'abc', 'sourceId': 'local-engine:yunqi',
      };
      var resolverCalls = 0;
      final gateway = const ContextResolutionGateway();
      final validation = await gateway.validateMetadata(metadata);
      final reference = AiContextRef.fromMetadata(metadata);
      if (reference != null && validation.isValidReference) {
        await gateway.resolve<_ResolvedValue>(
          reference: reference,
          resolver: () async {
            resolverCalls++;
            return const AiContextResolution<_ResolvedValue>(
              status: AiContextResolutionStatus.unknown,
            );
          },
          referenceOf: (value) => value.ref,
        );
      }
      expect(validation.status, ContextResolutionGatewayStatus.invalidReference);
      expect(resolverCalls, 0);
    });

    test('rejects unknown persisted metadata fields', () {
      final reference = AiContextRef.fromMetadata({
        ..._reference().toMetadata(),
        'unrecognizedPrivilege': 'true',
      });
      expect(reference, isNull);
    });

    test('accepts only results anchored to the requested reference', () async {
      final reference = _reference();
      final result = await const ContextResolutionGateway().resolve<_ResolvedValue>(
        reference: reference,
        resolver: () async => AiContextResolution<_ResolvedValue>(
          status: AiContextResolutionStatus.resolved,
          value: _ResolvedValue(reference),
        ),
        referenceOf: (value) => value.ref,
      );
      expect(result.status, ContextResolutionGatewayStatus.resolved);
      expect(result.isResolved, isTrue);
      expect(identical(result.value!.ref, reference), isTrue);
    });

    test('rejects a resolver result from another anchor as stale', () async {
      final result = await const ContextResolutionGateway().resolve<_ResolvedValue>(
        reference: _reference(),
        resolver: () async => AiContextResolution<_ResolvedValue>(
          status: AiContextResolutionStatus.resolved,
          value: _ResolvedValue(_reference(anchorId: 'formula:ma-huang-tang')),
        ),
        referenceOf: (value) => value.ref,
      );
      expect(result.status, ContextResolutionGatewayStatus.stale);
      expect(result.value, isNull);
    });

    test('keeps resolver source statuses distinct', () async {
      final gateway = const ContextResolutionGateway();
      Future<ContextResolutionGatewayStatus> run(AiContextResolutionStatus status) async {
        final result = await gateway.resolve<_ResolvedValue>(
          reference: _reference(),
          resolver: () async => AiContextResolution<_ResolvedValue>(
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

    test('history restore and subsequent turn validate the same anchor', () async {
      final gateway = const ContextResolutionGateway();
      final reference = _reference();
      expect((await gateway.validateReference(reference)).isValidReference, isTrue);
      expect((await gateway.validateReference(reference)).isValidReference, isTrue);
    });

    test('resolver exceptions never become resolved context', () async {
      final result = await const ContextResolutionGateway().resolve<_ResolvedValue>(
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
