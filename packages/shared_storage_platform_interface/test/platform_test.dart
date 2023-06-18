import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_storage_platform_interface/src/method_channel_shared_storage_platform.dart';
import 'package:shared_storage_platform_interface/src/shared_storage_platform_interface.dart';
import 'package:shared_storage_platform_interface/src/serialization.dart';

const channelName = 'io.alexrintt/shared_storage';
const utf8encoder = Utf8Encoder();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannelNsdPlatform shared_storage;
  late MethodChannel methodChannel;
  late Map<String, Function(String handle, dynamic arguments)> mockHandlers;

  setUp(() async {
    shared_storage = MethodChannelNsdPlatform();
    shared_storage.enableLogging(LogTopic.calls);
    methodChannel = const MethodChannel(channelName);
    mockHandlers = HashMap();

    // install custom handler that routes method calls to mock handlers
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {
      final handle = deserializeHandle(methodCall.arguments)!;
      return mockHandlers[methodCall.method]
          ?.call(handle, methodCall.arguments);
    });
  });

  group('$MethodChannelNsdPlatform discovery', () {
    test('Start succeeds if native code reports success', () async {
      // simulate success callback by native code
      mockHandlers['startDiscovery'] = (handle, arguments) {
        mockReply('onDiscoveryStartSuccessful', serializeHandle(handle));
      };

      await shared_storage.startDiscovery('_foo._tcp');
    });

    test('Start succeeds for special service enumeration type', () async {
      // simulate success callback by native code
      mockHandlers['startDiscovery'] = (handle, arguments) {
        mockReply('onDiscoveryStartSuccessful', serializeHandle(handle));
      };

      await shared_storage.startDiscovery('_services._dns-sd._udp');
    });

    test('Autoresolve', () async {
      late String capturedHandle;

      // simulate success callback by native code
      mockHandlers['startDiscovery'] = (handle, arguments) {
        capturedHandle = handle;
        mockReply('onDiscoveryStartSuccessful', serializeHandle(handle));
      };

      // set up mock resolver to answer with "resolved" service
      mockHandlers['resolve'] = (handle, arguments) {
        mockReply('onResolveSuccessful', {
          ...serializeHandle(handle),
          ...serializeService(const Service(
              name: 'Some name', type: 'bar', host: 'baz', port: 56000))
        });
      };

      final discovery = await shared_storage.startDiscovery('_foo._tcp');

      // simulate unresolved discovered service
      await mockReply('onServiceDiscovered', {
        ...serializeHandle(capturedHandle),
        ...serializeService(const Service(name: 'Some name', type: '_foo._tcp'))
      });

      final discoveredService = discovery.services.elementAt(0);
      expect(discoveredService.host, 'baz');
      expect(discoveredService.port, 56000);
    });

    test('IP lookup', () async {
      late String capturedHandle;

      // simulate success callback by native code
      mockHandlers['startDiscovery'] = (handle, arguments) {
        capturedHandle = handle;
        mockReply('onDiscoveryStartSuccessful', serializeHandle(handle));
      };

      // set up mock resolver to answer with "resolved" service
      mockHandlers['resolve'] = (handle, arguments) {
        mockReply('onResolveSuccessful', {
          ...serializeHandle(handle),
          ...serializeService(const Service(
              name: 'Some name', type: 'bar', host: 'localhost', port: 56000))
        });
      };

      final discovery = await shared_storage.startDiscovery('_foo._tcp',
          ipLookupType: IpLookupType.any);

      // simulate unresolved discovered service
      await mockReply('onServiceDiscovered', {
        ...serializeHandle(capturedHandle),
        ...serializeService(const Service(name: 'Some name', type: '_foo._tcp'))
      });

      final discoveredService = discovery.services.elementAt(0);
      expect(discoveredService.addresses, isNotEmpty);
    });

    test('Start fails if native code reports failure', () async {
      // simulate failure callback by native code
      mockHandlers['startDiscovery'] = (handle, arguments) {
        mockReply('onDiscoveryStartFailed', {
          ...serializeHandle(handle),
          ...serializeErrorCause(ErrorCause.maxLimit),
          ...serializeErrorMessage('some error')
        });
      };

      final matcher = isA<SharedStorageError>()
          .having((e) => e.cause, 'error cause', ErrorCause.maxLimit)
          .having((e) => e.message, 'error message', contains('some error'));

      expect(shared_storage.startDiscovery('_foo._tcp'), throwsA(matcher));
    });

    test('Start fails if service type is invalid', () async {
      final matcher = isA<SharedStorageError>()
          .having((e) => e.cause, 'error cause', ErrorCause.illegalArgument)
          .having((e) => e.message, 'error message', contains('format'));

      expect(shared_storage.startDiscovery('foo'), throwsA(matcher));
    });

    test('Invalid service types are ignored if configured', () async {
      shared_storage.disableServiceTypeValidation(true);

      mockHandlers['startDiscovery'] = (handle, arguments) {
        mockReply('onDiscoveryStartSuccessful', serializeHandle(handle));
      };

      await shared_storage.startDiscovery('foo');
    });

    test('Start fails if IP lookup is enabled without auto resolve', () async {
      final matcher = isA<SharedStorageError>()
          .having((e) => e.cause, 'error cause', ErrorCause.illegalArgument)
          .having((e) => e.message, 'error message',
              contains('Auto resolve must be enabled'));

      expect(
          shared_storage.startDiscovery('_foo._tcp',
              autoResolve: false, ipLookupType: IpLookupType.v4),
          throwsA(matcher));
    });

    test('Platform exceptions are converted to shared_storage errors',
        () async {
      mockHandlers['startDiscovery'] = (handle, arguments) {
        throw PlatformException(
            code: ErrorCause.securityIssue.name, message: 'platform');
      };

      final matcher = isA<SharedStorageError>()
          .having((e) => e.cause, 'error cause', ErrorCause.securityIssue)
          .having((e) => e.message, 'error message', contains('platform'));

      // platform exceptions are propagated to the flutter side
      // and should be converted to shared_storage errors
      expect(shared_storage.startDiscovery('_foo._tcp'), throwsA(matcher));
    });

    test('Missing plugin exceptions are converted to shared_storage errors',
        () async {
      mockHandlers['startDiscovery'] = (handle, arguments) {
        throw MissingPluginException();
      };

      // platform exceptions are propagated to the flutter side
      // and should be converted to shared_storage errors (internal)
      final matcher = isA<SharedStorageError>()
          .having((e) => e.cause, 'error cause', ErrorCause.internalError);

      expect(shared_storage.startDiscovery('_foo._tcp'), throwsA(matcher));
    });

    test('Generic exceptions are converted to shared_storage errors', () async {
      mockHandlers['startDiscovery'] = (handle, arguments) {
        throw Exception('generic');
      };

      final matcher = isA<SharedStorageError>()
          .having((e) => e.cause, 'error cause', ErrorCause.internalError)
          .having((e) => e.message, 'error message', contains('generic'));

      // all other exceptions are converted to platform exceptions by flutter
      // and should be converted to shared_storage errors (internal)
      expect(shared_storage.startDiscovery('_foo._tcp'), throwsA(matcher));
    });

    test('Stop succeeds if native code reports success', () async {
      mockHandlers['startDiscovery'] = (handle, arguments) {
        mockReply('onDiscoveryStartSuccessful', serializeHandle(handle));
      };

      mockHandlers['stopDiscovery'] = (handle, arguments) {
        mockReply('onDiscoveryStopSuccessful', serializeHandle(handle));
      };

      final discovery = await shared_storage.startDiscovery('_foo._tcp');
      await shared_storage.stopDiscovery(discovery);
    });

    test('Stop fails if native code reports failure', () async {
      mockHandlers['startDiscovery'] = (handle, arguments) {
        mockReply('onDiscoveryStartSuccessful', serializeHandle(handle));
      };

      mockHandlers['stopDiscovery'] = (handle, arguments) {
        mockReply('onDiscoveryStopFailed', {
          ...serializeHandle(handle),
          ...serializeErrorCause(ErrorCause.maxLimit),
          ...serializeErrorMessage('some error')
        });
      };

      final discovery = await shared_storage.startDiscovery('_foo._tcp');

      final matcher = isA<SharedStorageError>()
          .having((e) => e.cause, 'error cause', ErrorCause.maxLimit)
          .having((e) => e.message, 'error message', contains('some error'));

      expect(shared_storage.stopDiscovery(discovery), throwsA(matcher));
    });

    test('Client is notified if service is discovered', () async {
      late String capturedHandle;

      mockHandlers['startDiscovery'] = (handle, arguments) {
        capturedHandle = handle;
        mockReply('onDiscoveryStartSuccessful', serializeHandle(handle));
      };

      final discovery =
          await shared_storage.startDiscovery('_foo._tcp', autoResolve: false);

      const service = Service(name: 'Some name', type: '_foo._tcp');
      await mockReply('onServiceDiscovered',
          {...serializeHandle(capturedHandle), ...serializeService(service)});

      expect(discovery.services.length, 1);
    });

    test('Client is notified if service is lost', () async {
      late String capturedHandle;

      mockHandlers['startDiscovery'] = (handle, arguments) {
        capturedHandle = handle;
        mockReply('onDiscoveryStartSuccessful', serializeHandle(handle));
      };

      final discovery =
          await shared_storage.startDiscovery('_foo._tcp', autoResolve: false);

      const service = Service(name: 'Some name', type: '_foo._tcp');

      await mockReply('onServiceDiscovered',
          {...serializeHandle(capturedHandle), ...serializeService(service)});

      expect(discovery.services.length, 1);

      await mockReply('onServiceLost',
          {...serializeHandle(capturedHandle), ...serializeService(service)});

      expect(discovery.services.length, 0);
    });

    test('Callback is notified if service is discovered', () async {
      late String capturedHandle;

      mockHandlers['startDiscovery'] = (handle, arguments) {
        capturedHandle = handle;
        mockReply('onDiscoveryStartSuccessful', serializeHandle(handle));
      };

      final discovery =
          await shared_storage.startDiscovery('_foo._tcp', autoResolve: false);

      final completer = Completer();
      discovery.addServiceListener((service, status) {
        if (status == ServiceStatus.found) {
          completer.complete();
        }
      });

      const service = Service(name: 'Some name', type: '_foo._tcp');
      await mockReply('onServiceDiscovered',
          {...serializeHandle(capturedHandle), ...serializeService(service)});

      await completer.future;
    });

    test('Callback is notified if service is lost', () async {
      late String capturedHandle;

      mockHandlers['startDiscovery'] = (handle, arguments) {
        capturedHandle = handle;
        mockReply('onDiscoveryStartSuccessful', serializeHandle(handle));
      };

      final discovery =
          await shared_storage.startDiscovery('_foo._tcp', autoResolve: false);

      final completer = Completer();
      discovery.addServiceListener((service, status) {
        if (status == ServiceStatus.lost) {
          completer.complete();
        }
      });

      const service = Service(name: 'Some name', type: '_foo._tcp');

      await mockReply('onServiceDiscovered',
          {...serializeHandle(capturedHandle), ...serializeService(service)});

      await mockReply('onServiceLost',
          {...serializeHandle(capturedHandle), ...serializeService(service)});

      await completer.future;
    });

    test('Callback is unregistered properly', () async {
      late String capturedHandle;

      mockHandlers['startDiscovery'] = (handle, arguments) {
        capturedHandle = handle;
        mockReply('onDiscoveryStartSuccessful', serializeHandle(handle));
      };

      final discovery =
          await shared_storage.startDiscovery('_foo._tcp', autoResolve: false);

      final completer = Completer();
      serviceListener(service, status) {
        completer.complete(); // should never be called
      }

      discovery.addServiceListener(serviceListener);
      discovery.removeServiceListener(serviceListener);

      const service = Service(name: 'Some name', type: '_foo._tcp');

      await mockReply('onServiceDiscovered',
          {...serializeHandle(capturedHandle), ...serializeService(service)});

      await mockReply('onServiceLost',
          {...serializeHandle(capturedHandle), ...serializeService(service)});

      expect(completer.isCompleted, false);
    });
  });

  group('$MethodChannelNsdPlatform resolve', () {
    test('Resolve succeeds if native code reports success', () async {
      mockHandlers['resolve'] = (handle, arguments) {
        // return service info with name only
        mockReply('onResolveSuccessful', {
          ...serializeHandle(handle),
          ...serializeService(Service(
              name: 'Some name',
              type: '_foo._tcp',
              host: 'bar',
              port: 42,
              txt: {'string': utf8encoder.convert('κόσμε')}))
        });
      };

      const service = Service(name: 'Some name', type: '_foo._tcp');
      final result = await shared_storage.resolve(service);

      // result should contain the original fields plus the updated host / port
      expect(result.name, 'Some name');
      expect(result.type, '_foo._tcp');
      expect(result.host, 'bar');
      expect(result.port, 42);
      expect(result.txt, {'string': utf8encoder.convert('κόσμε')});
    });

    test('Resolve fails if native code reports failure', () async {
      mockHandlers['resolve'] = (handle, arguments) {
        // return service info with name only
        mockReply('onResolveFailed', {
          ...serializeHandle(handle),
          ...serializeErrorCause(ErrorCause.maxLimit),
          ...serializeErrorMessage('some error')
        });
      };

      const service = Service(name: 'Some name', type: '_foo._tcp');

      final matcher = isA<SharedStorageError>()
          .having((e) => e.cause, 'error cause', ErrorCause.maxLimit)
          .having((e) => e.message, 'error message', contains('some error'));

      expect(shared_storage.resolve(service), throwsA(matcher));
    });

    test('Resolve fails if service type is invalid', () async {
      const service = Service(name: 'Some name', type: 'foo');

      final matcher = isA<SharedStorageError>()
          .having((e) => e.cause, 'error cause', ErrorCause.illegalArgument)
          .having((e) => e.message, 'error message', contains('format'));

      expect(shared_storage.resolve(service), throwsA(matcher));
    });
  });

  group('$MethodChannelNsdPlatform registration', () {
    test('Registration succeeds if native code reports success', () async {
      mockHandlers['register'] = (handle, arguments) {
        // return service info with name only
        mockReply('onRegistrationSuccessful', {
          ...serializeHandle(handle),
          ...serializeService(const Service(name: 'Some name (2)'))
        });
      };

      final registration = await shared_storage
          .register(const Service(name: 'Some name', type: '_foo._tcp'));

      final service = registration.service;

      // new service info should contain both the original service type and the updated name
      expect(service.name, 'Some name (2)');
      expect(service.type, '_foo._tcp');
    });

    test('Registration fails if native code reports failure', () async {
      // simulate failure callback by native code
      mockHandlers['register'] = (handle, arguments) {
        mockReply('onRegistrationFailed', {
          ...serializeHandle(handle),
          ...serializeErrorCause(ErrorCause.maxLimit),
          ...serializeErrorMessage('some error')
        });
      };

      const service = Service(name: 'Some name', type: '_foo._tcp');

      final matcher = isA<SharedStorageError>()
          .having((e) => e.cause, 'error cause', ErrorCause.maxLimit)
          .having((e) => e.message, 'error message', contains('some error'));

      expect(shared_storage.register(service), throwsA(matcher));
    });

    test('Registration fails if service type is invalid', () async {
      const service = Service(name: 'Some name', type: 'foo');

      final matcher = isA<SharedStorageError>()
          .having((e) => e.cause, 'error cause', ErrorCause.illegalArgument)
          .having((e) => e.message, 'error message', contains('format'));

      expect(shared_storage.register(service), throwsA(matcher));
    });

    test('Unregistration succeeds if native code reports success', () async {
      // simulate success callback by native code
      mockHandlers['register'] = (handle, arguments) {
        const service = Service(name: 'Some name (2)', type: '_foo._tcp');
        mockReply('onRegistrationSuccessful',
            {...serializeHandle(handle), ...serializeService(service)});
      };

      mockHandlers['unregister'] = (handle, arguments) {
        mockReply('onUnregistrationSuccessful', {
          ...serializeHandle(handle),
        });
      };

      const service = Service(name: 'Some name', type: '_foo._tcp');

      final registration = await shared_storage.register(service);
      await shared_storage.unregister(registration);
    });

    test('Unregistration fails if native code reports failure', () async {
      // simulate success callback by native code
      mockHandlers['register'] = (handle, arguments) {
        const service = Service(name: 'Some name (2)', type: '_foo._tcp');
        mockReply('onRegistrationSuccessful',
            {...serializeHandle(handle), ...serializeService(service)});
      };

      mockHandlers['unregister'] = (handle, arguments) {
        mockReply('onUnregistrationFailed', {
          ...serializeHandle(handle),
          ...serializeErrorCause(ErrorCause.maxLimit),
          ...serializeErrorMessage('some error')
        });
      };

      const service = Service(name: 'Some name', type: '_foo._tcp');
      final registration = await shared_storage.register(service);

      final matcher = isA<SharedStorageError>()
          .having((e) => e.cause, 'error cause', ErrorCause.maxLimit)
          .having((e) => e.message, 'error message', contains('some error'));

      expect(shared_storage.unregister(registration), throwsA(matcher));
    });
  });

  group('$MethodChannelNsdPlatform native code api', () {
    test('Native code receives error if no handle was given', () async {
      final matcher = isA<PlatformException>().having(
          (e) => e.message, 'error message', contains('Expected handle'));

      expect(mockReply('onDiscoveryStopSuccessful', {}), throwsA(matcher));
    });

    test('Native code receives error if the handle is unknown', () async {
      final matcher = isA<PlatformException>()
          .having((e) => e.message, 'error message', contains('No handler'));

      expect(
          mockReply('onDiscoveryStopSuccessful', serializeHandle('ssafdeaw')),
          throwsA(matcher));
    });
  });

  group('$NsdPlatformInterface', () {
    test('Verify default platform', () async {
      expect(NsdPlatformInterface.instance, isA<MethodChannelNsdPlatform>());
    });

    test('Set custom platform interface', () async {
      final customPlatformInterface = MethodChannelNsdPlatform();
      NsdPlatformInterface.instance = customPlatformInterface;
      expect(NsdPlatformInterface.instance, customPlatformInterface);
    });
  });

  group('$Service', () {
    test('Verify default platform', () async {
      const service = Service(
          name: 'Some name (2)', type: '_foo._tcp', host: 'localhost', port: 0);
      expect(
          service.toString(),
          stringContainsInOrder(
              ['Some name (2)', '_foo._tcp', 'localhost', '0']));
    });

    test('Attributes are contained in text rendering', () async {
      final service = Service(
          name: 'Some name',
          type: '_foo._tcp',
          host: 'bar',
          port: 42,
          txt: {'string': utf8encoder.convert('κόσμε')});

      expect(service.toString(), contains('Some name'));
      expect(service.toString(), contains('_foo._tcp'));
      expect(service.toString(), contains('bar'));
      expect(service.toString(), contains(42.toString()));
      expect(service.toString(),
          contains(utf8encoder.convert('κόσμε').toString()));
    });
  });

  group('$Discovery', () {
    test('Attributes are contained in text rendering', () async {
      const service = Service(name: 'Some name', type: '_foo._tcp');
      final discovery = Discovery('bar');
      discovery.add(service);

      expect(discovery.toString(), contains('bar'));
      expect(discovery.toString(), contains('Some name'));
      expect(discovery.toString(), contains('_foo._tcp'));
    });
  });

  group('$Registration', () {
    test('Attributes are contained in text rendering', () async {
      const service = Service(name: 'Some name', type: '_foo._tcp');
      final registration = Registration('bar', service);

      expect(registration.toString(), contains('bar'));
      expect(registration.toString(), contains('Some name'));
      expect(registration.toString(), contains('_foo._tcp'));
    });
  });
}

Future<dynamic> mockReply(String method, dynamic arguments) async {
  const codec = StandardMethodCodec();
  final dataIn = codec.encodeMethodCall(MethodCall(method, arguments));

  final completer = Completer<ByteData?>();
  TestDefaultBinaryMessengerBinding.instance!.channelBuffers
      .push(channelName, dataIn, (dataOut) {
    completer.complete(dataOut);
  });

  final envelope = await completer.future;
  if (envelope != null) {
    return codec.decodeEnvelope(envelope);
  }
}
