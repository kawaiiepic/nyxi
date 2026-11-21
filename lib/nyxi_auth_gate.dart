import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'fluz_gateway.dart';
import 'fluz_panel.dart';

/// Single entry point for both mobile and desktop. The dashboard is never
/// mounted without a recently verified Nyxi backend and account session.
class NyxiAuthGate extends StatefulWidget {
  const NyxiAuthGate({
    super.key,
    required this.dashboardBuilder,
    this.controller,
  });

  final Widget Function(FluzController controller) dashboardBuilder;
  /// Supply a fake controller in tests; normally the gate owns its session.
  final FluzController? controller;

  @override
  State<NyxiAuthGate> createState() => _NyxiAuthGateState();
}

enum _GatePhase { checking, offline, signedOut, authenticating, ready }

class _NyxiAuthGateState extends State<NyxiAuthGate>
    with WidgetsBindingObserver {
  late final FluzController _controller;
  late final bool _ownsController;
  final _email = TextEditingController();
  final _password = TextEditingController();
  Timer? _heartbeat;
  _GatePhase _phase = _GatePhase.checking;
  bool _creatingAccount = false;
  bool _verifying = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? FluzController();
    _controller.addListener(_onAccountChanged);
    WidgetsBinding.instance.addObserver(this);
    // Never start in the dashboard, even when the app was hot-restarted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _verifyBackend();
    });
    _heartbeat = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted && _phase != _GatePhase.authenticating) {
        _verifyBackend();
      }
    });
  }

  void _onAccountChanged() {
    // A sign-out or rejected session must unmount the dashboard immediately.
    if (!mounted || _phase != _GatePhase.ready || _controller.signedIn) {
      return;
    }
    setState(() => _phase = _GatePhase.checking);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _verifyBackend();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Hide sensitive dashboard data when the app backgrounds.
      if (mounted && _phase == _GatePhase.ready) {
        setState(() => _phase = _GatePhase.checking);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (mounted && _phase != _GatePhase.authenticating) {
        setState(() => _phase = _GatePhase.checking);
        _verifyBackend();
      }
    }
  }

  Future<void> _verifyBackend() async {
    if (_verifying || !mounted || _phase == _GatePhase.authenticating) return;
    _verifying = true;
    try {
      // Fail closed: a reachable host alone is not enough, and a session
      // must be confirmed by /api/auth/me before mounting the dashboard.
      final healthy = await _controller.api.health()
          .timeout(const Duration(seconds: 6), onTimeout: () => false);
      if (!mounted) return;
      if (!healthy) {
        setState(() => _phase = _GatePhase.offline);
        return;
      }

      if (!_controller.api.signedIn || !_controller.signedIn) {
        setState(() => _phase = _GatePhase.signedOut);
        return;
      }

      try {
        final account = await _controller.api.me()
            .timeout(const Duration(seconds: 6));
        if (!mounted) return;
        if (account.id.isEmpty ||
            account.id != _controller.user!.id) {
          _controller.forgetSession();
          setState(() => _phase = _GatePhase.signedOut);
          return;
        }
        setState(() => _phase = _GatePhase.ready);
      } on FluzGatewayException catch (error) {
        if (!mounted) return;
        if (error.statusCode == 401) {
          _controller.forgetSession();
          setState(() => _phase = _GatePhase.signedOut);
        } else {
          setState(() => _phase = _GatePhase.offline);
        }
      } catch (_) {
        if (mounted) setState(() => _phase = _GatePhase.offline);
      }
    } catch (_) {
      if (mounted) setState(() => _phase = _GatePhase.offline);
    } finally {
      _verifying = false;
    }
  }

  Future<void> _submitCredentials() async {
    if (_phase != _GatePhase.signedOut) return;
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _formError = 'Enter your email address and password.');
      return;
    }
    setState(() {
      _formError = null;
      _phase = _GatePhase.authenticating;
    });

    await _controller.authenticate(
      email,
      password,
      register: _creatingAccount,
    );
    _password.clear();
    if (!mounted) return;

    if (!_controller.signedIn || !_controller.api.signedIn) {
      final message = _controller.error ?? 'Unable to sign in.';
      final healthy = await _controller.api.health()
          .timeout(const Duration(seconds: 6), onTimeout: () => false);
      if (!mounted) return;
      setState(() {
        _formError = message;
        _phase = healthy ? _GatePhase.signedOut : _GatePhase.offline;
      });
      return;
    }

    // A successful login response is not sufficient to open the app.
    // Validate the just-created session against the backend first.
    setState(() => _phase = _GatePhase.checking);
    await _verifyBackend();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _controller.removeListener(_onAccountChanged);
    WidgetsBinding.instance.removeObserver(this);
    _email.dispose();
    _password.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _GatePhase.ready) {
      return widget.dashboardBuilder(_controller);
    }

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF8F5F9),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFF0E6EF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x136B2257),
                      blurRadius: 36,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEB008E),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: const Text(
                        'n ✦',
                        style: TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 23),
                    Text(
                      _phase == _GatePhase.offline
                          ? 'Nyxi is locked'
                          : _phase == _GatePhase.signedOut
                              ? (_creatingAccount
                                  ? 'Create your Nyxi account'
                                  : 'Sign in to Nyxi')
                              : 'Checking Nyxi…',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        color: Color(0xFF241928),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _phase == _GatePhase.offline
                          ? 'The Nyxi backend is offline or not responding. '
                              'Your account and dashboard stay inaccessible '
                              'until the server responds.'
                          : _phase == _GatePhase.signedOut
                              ? 'An online Nyxi account is required. '
                                  'There is no offline or guest mode.'
                              : 'Verifying the server and your account session.',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: Color(0xFF857A88),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_phase == _GatePhase.offline) ...[
                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton.filled(
                          onPressed: _verifyBackend,
                          child: const Text('Retry connection'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Center(
                        child: Text(
                          'Nyxi automatically checks the server every 12 seconds.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9D97A1),
                          ),
                        ),
                      ),
                    ] else if (_phase == _GatePhase.signedOut) ...[
                      CupertinoTextField(
                        key: const ValueKey('nyxi-email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        placeholder: 'Email address',
                        autocorrect: false,
                        padding: const EdgeInsets.all(15),
                      ),
                      const SizedBox(height: 12),
                      CupertinoTextField(
                        key: const ValueKey('nyxi-password'),
                        controller: _password,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        placeholder: 'Password',
                        onSubmitted: (_) => _submitCredentials(),
                        padding: const EdgeInsets.all(15),
                      ),
                      if (_formError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _formError!,
                          style: const TextStyle(
                            color: Color(0xFFB51B7C),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton.filled(
                          key: const ValueKey('nyxi-auth-submit'),
                          onPressed: _submitCredentials,
                          child: Text(
                            _creatingAccount ? 'Create account' : 'Sign in',
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Center(
                        child: CupertinoButton(
                          onPressed: () {
                            _password.clear();
                            setState(() {
                              _creatingAccount = !_creatingAccount;
                              _formError = null;
                            });
                          },
                          child: Text(
                            _creatingAccount
                                ? 'Already have an account? Sign in'
                                : 'New to Nyxi? Create an account',
                          ),
                        ),
                      ),
                    ] else
                      const Center(child: CupertinoActivityIndicator(radius: 14)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
