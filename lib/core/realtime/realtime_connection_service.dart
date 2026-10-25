import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'realtime_transport.dart';

enum RealtimeConnectionState {
  disabled,
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class RealtimeRefreshUnavailable implements Exception {
  const RealtimeRefreshUnavailable();
}

class RealtimeSession {
  const RealtimeSession(this.identity, this.policy, this.accessToken);
  final Object identity, policy;
  final String accessToken;
}

class RealtimeChannel {
  const RealtimeChannel({
    required this.id,
    required this.destination,
    required this.message,
    required this.resync,
  });
  final String id, destination;
  final void Function(String) message;
  final void Function() resync;
}

/// One transport owner and one retry timer. Channel policy is supplied by features.
class RealtimeConnectionService extends ChangeNotifier {
  RealtimeConnectionService({
    required this.factory,
    required this.endpoint,
    required this.refresh,
    required this.recoverAccess,
    double Function()? random,
  }) : _random = random ?? Random().nextDouble;
  final RealtimeTransportFactory factory;
  final Uri Function() endpoint;
  final Future<void> Function(String rejectedToken) refresh;
  final Future<void> Function(String code) recoverAccess;
  final double Function() _random;
  RealtimeSession? _session;
  List<RealtimeChannel> _channels = const [];
  final Set<String> _blocked = {};
  RealtimeTransport? _transport;
  Future<void> _serial = Future.value();
  Timer? _retry, _stable;
  int _epoch = 0, _attempt = 0, _authRefreshes = 0;
  bool _enabled = false, _foreground = true, _disposed = false;
  bool _connectionBlocked = false;
  String? _authBlockedToken;
  RealtimeConnectionState state = RealtimeConnectionState.disabled;
  RealtimeProblem? problem;
  Set<String> get blockedChannels => Set.unmodifiable(_blocked);
  Iterable<RealtimeChannel> get _eligible =>
      _channels.where((c) => !_blocked.contains(c.id));
  bool get _wanted =>
      !_disposed &&
      _enabled &&
      _foreground &&
      _session != null &&
      !_connectionBlocked &&
      _eligible.isNotEmpty;
  bool _current(int epoch) => !_disposed && epoch == _epoch;

  void configure({
    required bool enabled,
    required bool foreground,
    required RealtimeSession? session,
    required List<RealtimeChannel> channels,
  }) {
    if (_disposed) return;
    final policyChanged =
        session?.identity != _session?.identity ||
        session?.policy != _session?.policy;
    final changed =
        policyChanged ||
        enabled != _enabled ||
        foreground != _foreground ||
        session?.accessToken != _session?.accessToken ||
        channels.length != _channels.length ||
        channels.indexed.any(
          (entry) =>
              entry.$1 >= _channels.length ||
              entry.$2.id != _channels[entry.$1].id ||
              entry.$2.destination != _channels[entry.$1].destination,
        );
    if (!changed) {
      _channels = List.unmodifiable(channels);
      return;
    }
    if (policyChanged) {
      _blocked.clear();
      _connectionBlocked = false;
      _authRefreshes = 0;
      problem = null;
      _authBlockedToken = null;
    } else if (_authBlockedToken != null &&
        session?.accessToken != _authBlockedToken) {
      _authBlockedToken = null;
      _connectionBlocked = false;
      _authRefreshes = 0;
    }
    _session = session;
    _channels = List.unmodifiable(channels);
    _enabled = enabled;
    _foreground = foreground;
    if (foreground) _attempt = 0;
    _restart();
  }

  void _set(RealtimeConnectionState value) {
    if (_disposed) return;
    state = value;
    notifyListeners();
  }

  void stop({bool notify = true}) {
    if (_disposed) return;
    _enabled = false;
    _foreground = false;
    _session = null;
    _channels = const [];
    _restart(notify: notify);
  }

  void _restart({bool notify = true}) {
    final epoch = ++_epoch;
    _retry?.cancel();
    _retry = null;
    _stable?.cancel();
    final old = _transport;
    _transport = null; // Invalidate callbacks before any asynchronous cleanup.
    final next = !_enabled
        ? RealtimeConnectionState.disabled
        : RealtimeConnectionState.disconnected;
    if (notify) {
      _set(next);
    } else {
      state = next;
    }
    _serial = _serial.then((_) async {
      await old?.close();
      if (!_current(epoch) || !_wanted) return;
      _connect(epoch);
    });
  }

  void _connect(int epoch) {
    if (!_current(epoch) || !_wanted || _transport != null) return;
    final session = _session!;
    _set(
      _attempt == 0
          ? RealtimeConnectionState.connecting
          : RealtimeConnectionState.reconnecting,
    );
    try {
      final url = endpoint();
      final transport = factory();
      _transport = transport;
      bool active() => _current(epoch) && identical(_transport, transport);
      transport.open(
        url,
        session.accessToken,
        RealtimeCallbacks(
          connected: () {
            if (!active() || !_wanted) return;
            _set(RealtimeConnectionState.connected);
            for (final channel in _eligible.toList()) {
              if (!active()) return;
              transport.subscribe(channel.id, channel.destination, (body) {
                if (active() && _wanted && !_blocked.contains(channel.id)) {
                  for (final current in _channels.where(
                    (c) => c.id == channel.id,
                  )) {
                    current.message(body);
                  }
                }
              });
              if (active()) channel.resync();
            }
            _stable = Timer(const Duration(seconds: 30), () {
              if (active()) {
                _attempt = 0;
                _authRefreshes = 0;
              }
            });
          },
          failed: (failure) {
            if (active()) unawaited(_failed(epoch, transport, failure));
          },
        ),
      );
    } catch (_) {
      // Configuration/protocol errors cannot be fixed by a retry loop.
      problem = const RealtimeProblem(
        RealtimeFailureKind.protocol,
        code: 'REALTIME_PROTOCOL_VIOLATION',
      );
      _connectionBlocked = true;
      _restart();
    }
  }

  Future<void> _failed(
    int epoch,
    RealtimeTransport transport,
    RealtimeProblem failure,
  ) async {
    if (!_current(epoch) || !identical(_transport, transport)) return;
    problem = failure;
    _transport = null;
    _stable?.cancel();
    _set(RealtimeConnectionState.disconnected);
    // Serialize physical closes with subsequent connections, including refresh callbacks.
    final cleanup = _serial.then((_) => transport.close());
    _serial = cleanup;
    final code = failure.code;
    if (code == 'UNAUTHORIZED' || code == 'TOKEN_EXPIRED') {
      if (_authRefreshes++ >= 1) {
        _connectionBlocked = true;
        _authBlockedToken = _session!.accessToken;
        return;
      }
      final token = _session!.accessToken;
      var retryable = false;
      try {
        await refresh(token);
      } catch (error) {
        retryable = error is RealtimeRefreshUnavailable;
        /* Auth flow alone decides logout. */
      }
      if (!_current(epoch)) {
        return; // New token/scope already scheduled a connection.
      }
      if (_session?.accessToken == token) {
        if (retryable) {
          _authRefreshes--;
          await cleanup;
          if (_current(epoch)) _scheduleRetry(epoch);
          return;
        }
        _connectionBlocked =
            true; // No usable replacement; avoid refreshing forever.
        _authBlockedToken = token;
        _set(RealtimeConnectionState.disconnected);
        return;
      }
    } else if (const {
      'FORBIDDEN',
      'FEATURE_NOT_ENTITLED',
      'SUBSCRIPTION_NOT_ACTIVE',
    }.contains(code)) {
      if (failure.channelId != null &&
          _channels.any((c) => c.id == failure.channelId)) {
        _blocked.add(failure.channelId!);
      } else {
        _blocked.addAll(_channels.map((c) => c.id));
      }
      // A policy recovery is attempted once; repeated identical grants stay blocked.
      unawaited(recoverAccess(code!).catchError((Object _) {}));
    } else if (code == 'ACCOUNT_INACTIVE' || code == 'RESTAURANT_INACTIVE') {
      _connectionBlocked = true;
      unawaited(recoverAccess(code!).catchError((Object _) {}));
    } else if (code == 'REALTIME_PROTOCOL_VIOLATION' ||
        failure.kind == RealtimeFailureKind.protocol ||
        failure.closeCode == 1008 && code == null) {
      _connectionBlocked = true;
    }
    await cleanup;
    if (!_current(epoch) || !_wanted) return;
    _scheduleRetry(epoch);
  }

  void _scheduleRetry(int epoch) {
    if (_retry != null || !_current(epoch) || !_wanted) return;
    final base = min(30000, 1000 * (1 << min(_attempt++, 5)));
    final delay = Duration(
      milliseconds: (base * (0.75 + 0.25 * _random())).round(),
    );
    _set(RealtimeConnectionState.reconnecting);
    _retry = Timer(delay, () {
      _retry = null;
      if (_current(epoch) && _wanted) _connect(epoch);
    });
  }

  /// Explicit user/network signal; never clears terminal channel policy decisions.
  void retry() {
    if (_wanted && _transport == null) _restart();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    _retry?.cancel();
    _stable?.cancel();
    final transport = _transport;
    _transport = null;
    unawaited(transport?.close());
    _session = null;
    _channels = const [];
    _blocked.clear();
    super.dispose();
  }
}
