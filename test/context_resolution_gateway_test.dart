import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/feature_authorizer.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/context_resolution_gateway.dart';

class _FakeAuthorizer implements FeatureAuthorizer {
  _FakeAuthorizer(this.decision);

  FeatureAuthorizationDecision decision;
  int calls = 0;
  final List<String> requested = [];

  @override
  Future<FeatureAuthorizationDecision> authorize(String featureId) async {
    calls += 1;
    requested.add(featureId);
    return decision;
  }
}

class _ThrowingAuthorizer implements FeatureAuthorizer {
  @override
  Future<FeatureAuthorizationDecision> authorize(String featureId) async {
    throw StateError('secure store unavailable');
  }
}

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
    test('denied entitlement prevents resolver execution', () async {
      final authorizer = _FakeAuthorizer(
        FeatureAuthorizationDecision.denied(
          featureId: ContextResolutionGateway.featureId,
          reason: FeatureAuthorizationFailureReason.unlicensed,
        ),
      );
      var resolverCalls = 0;
      final result = await ContextResolutionGateway(authorizer: authorizer)
          .resolve<_ResolvedValue>(
        reference: _reference(),
        resolver: () {
          resolverCalls += 1;
          return AiContextResolution<_ResolvedValue>(
            status: AiContextResolutionStatus.resolved,
            value: _ResolvedValue(_reference()),
          );
        },
        referenceOf: (value) => value.ref,
      );

      expect(result.status, ContextResolutionGatewayStatus.authorizationDenied);
      expect(result.authorizationReason, FeatureAuthorizationFailureReason.unlicensed);
      expect(authorizer.requested, [ContextResolutionGateway.featureId]);
      expect(resolverCalls, 0);
      expect(result.value, isNull);
    });

    test('temporarily unavailable entitlement prevents resolver execution', () async {
      final authorizer = _FakeAuthorizer(
        FeatureAuthorizationDecision.temporarilyUnavailable(
          featureId: ContextResolutionGateway.featureId,
          reason: FeatureAuthorizationFailureReason.initializationTimeout,
        ),
      );
      var resolverCalls = 0;
      final result = await ContextResolutionGateway(authorizer: authorizer)
          .resolve<_ResolvedValue>(
        reference: _reference(),
        resolver: () {
          resolverCalls += 1;
          return const AiContextResolution<_ResolvedValue>(
            status: AiContextResolutionStatus.unknown,
          );
        },
        referenceOf: (value) => value.ref,
      );

      expect(result.status, ContextResolutionGatewayStatus.authorizationUnavailable);
      expect(result.authorizationReason, FeatureAuthorizationFailureReason.initializationTimeout);
      expect(resolverCalls, 0);
    });

    test('authorized resolver returns only the exact requested anchor', () async {
      final reference = _reference();
      final authorizer = _FakeAuthorizer(
        FeatureAuthorizationDecision.allowed(
          featureId: ContextResolutionGateway.featureId,
        ),
      );
      var resolverCalls = 0;
      final result = await ContextResolutionGateway(authorizer: authorizer)
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
      expect(authorizer.calls, 1);
      expect(resolverCalls, 1);
    });

    test('a resolver result from another anchor is rejected as stale', () async {
      final authorizer = _FakeAuthorizer(
        FeatureAuthorizationDecision.allowed(
          featureId: ContextResolutionGateway.featureId,
        ),
      );
      final result = await ContextResolutionGateway(authorizer: authorizer)
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
      final authorizer = _FakeAuthorizer(
        FeatureAuthorizationDecision.allowed(
          featureId: ContextResolutionGateway.featureId,
        ),
      );
      final gateway = ContextResolutionGateway(authorizer: authorizer);

      Future<ContextResolutionGatewayStatus> run(
        AiContextResolutionStatus status,
      ) async {
        final result = await gateway.resolve<_ResolvedValue>(
          reference: _reference(),
          resolver: () => AiContextResolution<_ResolvedValue>(
            status: status,
            reason: 'source-\${status.name}',
          ),
          referenceOf: (value) => value.ref,
        );
        return result.status;
      }

      expect(await run(AiContextResolutionStatus.missing), ContextResolutionGatewayStatus.missing);
      expect(await run(AiContextResolutionStatus.unknown), ContextResolutionGatewayStatus.unknown);
      expect(await run(AiContextResolutionStatus.stale), ContextResolutionGatewayStatus.stale);
      expect(await run(AiContextResolutionStatus.denied), ContextResolutionGatewayStatus.sourceDenied);
      expect(authorizer.calls, 4);
    });

    test('malformed persisted metadata is rejected before entitlement lookup', () async {
      final authorizer = _FakeAuthorizer(
        FeatureAuthorizationDecision.allowed(
          featureId: ContextResolutionGateway.featureId,
        ),
      );
      final result = await ContextResolutionGateway(authorizer: authorizer)
          .authorizeMetadata(const {
        'kind': 'toolResult',
        'moduleId': 'yunqi',
        'anchorId': 'yunqi:result:abc',
        'anchorVersion': 'abc',
        'snapshotId': 'abc',
        'sourceId': 'local-engine:yunqi',
      });

      expect(result.status, ContextResolutionGatewayStatus.invalidReference);
      expect(authorizer.calls, 0);
    });

    test('unknown persisted metadata fields are rejected', () {
      final reference = AiContextRef.fromMetadata({
        ..._reference().toMetadata(),
        'unrecognizedPrivilege': 'true',
      });
      expect(reference, isNull);
    });

    test('history restore and each subsequent turn re-authorize the reference', () async {
      final authorizer = _FakeAuthorizer(
        FeatureAuthorizationDecision.allowed(
          featureId: ContextResolutionGateway.featureId,
        ),
      );
      final gateway = ContextResolutionGateway(authorizer: authorizer);
      final reference = _reference();

      final restore = await gateway.authorizeReference(reference);
      final nextTurn = await gateway.authorizeReference(reference);

      expect(restore.status, ContextResolutionGatewayStatus.authorized);
      expect(nextTurn.status, ContextResolutionGatewayStatus.authorized);
      expect(authorizer.calls, 2);
      expect(authorizer.requested, [
        ContextResolutionGateway.featureId,
        ContextResolutionGateway.featureId,
      ]);
    });

    test('provider exception fails closed', () async {
      final result = await ContextResolutionGateway(
        authorizer: _ThrowingAuthorizer(),
      ).authorizeReference(_reference());

      expect(result.status, ContextResolutionGatewayStatus.authorizationUnavailable);
      expect(result.authorizationReason, FeatureAuthorizationFailureReason.providerError);
    });

    test('wrong feature id from provider fails closed', () async {
      final authorizer = _FakeAuthorizer(
        FeatureAuthorizationDecision.denied(
          featureId: 'ai_advanced',
          reason: FeatureAuthorizationFailureReason.unlicensed,
        ),
      );
      final result = await ContextResolutionGateway(authorizer: authorizer)
          .authorizeReference(_reference());

      expect(result.status, ContextResolutionGatewayStatus.authorizationUnavailable);
      expect(result.authorizationReason, FeatureAuthorizationFailureReason.providerError);
    });

    test('resolver exception never becomes resolved context', () async {
      final authorizer = _FakeAuthorizer(
        FeatureAuthorizationDecision.allowed(
          featureId: ContextResolutionGateway.featureId,
        ),
      );
      final result = await ContextResolutionGateway(authorizer: authorizer)
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
