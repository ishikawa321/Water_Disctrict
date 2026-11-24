import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ui_components.dart';

const projectUrl = 'https://kaeespcylucvsazfdaks.supabase.co';
// Public client key; database access is still controlled by Supabase policies.
const publishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_X81fBSYttDlVEYEiFCuoRQ_IQlSRsNo',
);
const mobileRecoveryUrl = 'waterdistrictconnect://reset-password/';

String passwordRecoveryUrl({required bool isWeb, required Uri baseUri}) {
  // Do not copy an earlier callback's code or token into a new reset link.
  return isWeb
      ? Uri(
          scheme: baseUri.scheme,
          host: baseUri.host,
          port: baseUri.hasPort ? baseUri.port : null,
          path: baseUri.path,
        ).toString()
      : mobileRecoveryUrl;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WaterDistrictApp());
}

final supabase = Supabase.instance.client;

class WaterDistrictApp extends StatelessWidget {
  const WaterDistrictApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Water District Connect',
      debugShowCheckedModeBanner: false,
      theme: waterTheme(),
      home: const WaterStartup(),
    );
  }
}

enum AccountScreen { login, resetPassword, dashboard }

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController signInSlide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final Animation<Offset> signInOffset = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(1, 0),
  ).animate(CurvedAnimation(parent: signInSlide, curve: Curves.easeInCubic));
  bool signingIn = false;
  final fieldErrors = <TextEditingController, String>{};
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();

  StreamSubscription<AuthState>? authSubscription;

  AccountScreen screen = AccountScreen.login;
  Map<String, dynamic>? profile;

  bool busy = false;
  bool passwordSaved = false;
  String? message;
  bool isError = false;

  @override
  void initState() {
    super.initState();

    authSubscription = supabase.auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;

        if (state.event == AuthChangeEvent.passwordRecovery) {
          passwordController.clear();
          confirmController.clear();

          setState(() {
            screen = AccountScreen.resetPassword;
            profile = null;
            passwordSaved = false;
            message = null;
            busy = false;
          });
        } else if (state.event == AuthChangeEvent.signedOut) {
          passwordController.clear();
          confirmController.clear();

          setState(() {
            screen = AccountScreen.login;
            profile = null;
            passwordSaved = false;
          });
        }
      },
      onError: (Object _) {
        if (!mounted) return;
        showMessage(
          'The recovery link could not be processed. '
          'Request a new link and open it in the same browser.',
          error: true,
        );
      },
    );
  }

  @override
  void dispose() {
    signInSlide.dispose();
    authSubscription?.cancel();
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  void showMessage(String text, {bool error = false}) {
    if (!mounted) return;

    setState(() {
      message = text;
      isError = error;
    });
  }

  void startWorking() {
    setState(() {
      busy = true;
      message = null;
      isError = false;
    });
  }

  void stopWorking() {
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> signIn() async {
    if (busy) return;

    final email = emailController.text.trim();

    fieldErrors.clear();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      fieldErrors[emailController] = 'Enter a valid email address.';
    }
    if (passwordController.text.isEmpty) {
      fieldErrors[passwordController] = 'Enter your password.';
    }
    if (fieldErrors.isNotEmpty) {
      setState(() {});
      return;
    }

    signingIn = true;
    signInSlide.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 800);
    startWorking();
    // Handle disposal immediately, even while the network request is pending.
    final labelExited = signInSlide
        .forward(from: 0)
        .orCancel
        .then<void>((_) {}, onError: (Object _) {});

    try {
      // Authentication and the label animation run at the same time.
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: passwordController.text,
      );

      final user = response.user;
      if (user == null) {
        throw StateError('No user returned.');
      }

      final result = await supabase
          .from('profiles')
          .select('display_name, role')
          .eq('user_id', user.id)
          .eq('active', true)
          .maybeSingle();

      await labelExited;
      if (!mounted || screen != AccountScreen.login) return;

      if (result == null || !['admin', 'client'].contains(result['role'])) {
        await supabase.auth.signOut();
        showMessage(
          'No active app profile was found. Contact the administrator.',
          error: true,
        );
        return;
      }

      passwordController.clear();

      setState(() {
        profile = result;
        screen = AccountScreen.dashboard;
      });
    } on AuthException {
      showMessage(
        'Sign-in failed. Check your email and password.',
        error: true,
      );
    } catch (_) {
      showMessage(
        'Could not load your account. Check your connection and retry.',
        error: true,
      );
    } finally {
      if (mounted) {
        if (screen == AccountScreen.login) {
          try {
            await signInSlide.reverse().orCancel;
          } on TickerCanceled {
            /* Disposed. */
          }
        }
        if (!mounted) return;
        signingIn = false;
        signInSlide.reset();
      }
      stopWorking();
    }
  }

  Future<void> requestPasswordReset() async {
    if (busy) return;

    final email = emailController.text.trim();

    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      fieldErrors[emailController] =
          'Enter your registered email address first.';
      setState(() => message = null);
      return;
    }

    startWorking();

    try {
      await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: passwordRecoveryUrl(isWeb: kIsWeb, baseUri: Uri.base),
      );

      showMessage(
        'If this email is registered, a reset link will be sent. '
        'Check your inbox and spam folder. Open the link on this device'
        '${kIsWeb ? " in the same browser" : ""}.',
      );
    } on AuthException catch (error) {
      showMessage(error.message, error: true);
    } catch (_) {
      showMessage(
        'Could not connect to the authentication service. '
        'Check your internet connection.',
        error: true,
      );
    } finally {
      stopWorking();
    }
  }

  Future<void> saveNewPassword() async {
    if (busy || passwordSaved) return;

    final password = passwordController.text;

    if (password.length < 8) {
      fieldErrors[passwordController] =
          'Use a password with at least 8 characters.';
      setState(() => message = null);
      return;
    }

    if (password != confirmController.text) {
      fieldErrors[confirmController] = 'Passwords do not match.';
      setState(() => message = null);
      return;
    }

    if (supabase.auth.currentSession == null) {
      showMessage(
        'The recovery session has expired. Request a new reset link.',
        error: true,
      );
      return;
    }

    startWorking();

    try {
      await supabase.auth.updateUser(UserAttributes(password: password));

      if (!mounted) return;

      passwordController.clear();
      confirmController.clear();

      setState(() {
        passwordSaved = true;
      });

      showMessage(
        'Password updated successfully. '
        'Select “Return to sign in” to continue.',
      );
    } on AuthException catch (error) {
      showMessage(error.message, error: true);
    } catch (_) {
      showMessage(
        'Could not update your password. Check your connection and retry.',
        error: true,
      );
    } finally {
      stopWorking();
    }
  }

  Future<void> returnToLogin() async {
    if (busy) return;

    final wasPasswordSaved = passwordSaved;
    startWorking();

    try {
      await supabase.auth.signOut();

      if (!mounted) return;

      passwordController.clear();
      confirmController.clear();

      setState(() {
        screen = AccountScreen.login;
        profile = null;
        passwordSaved = false;
      });

      if (wasPasswordSaved) {
        showMessage('Sign in using your new password.');
      }
    } catch (_) {
      showMessage('Could not sign out. Please retry.', error: true);
    } finally {
      stopWorking();
    }
  }

  bool passwordVisible = false;

  Widget input(
    TextEditingController controller,
    String label, {
    bool secret = false,
  }) {
    final field = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        enabled: !busy,
        obscureText: secret && !passwordVisible,
        autocorrect: false,
        enableSuggestions: !secret,
        onChanged: (_) {
          if (fieldErrors.containsKey(controller)) {
            setState(() => fieldErrors.remove(controller));
          }
        },
        keyboardType: secret
            ? TextInputType.visiblePassword
            : TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: label,
          errorText: fieldErrors[controller],
          prefixIcon: Icon(secret ? Icons.lock_outline : Icons.mail_outline),
          suffixIcon: secret
              ? IconButton(
                  tooltip: passwordVisible ? 'Hide password' : 'Show password',
                  onPressed: () =>
                      setState(() => passwordVisible = !passwordVisible),
                  icon: Icon(
                    passwordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                )
              : null,
        ),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return field;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: field,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (screen == AccountScreen.dashboard) {
      return ContentEntrance(
        child: ModernDashboard(
          profile: profile!,
          onSignOut: returnToLogin,
          signingOut: busy,
        ),
      );
    }
    final reset = screen == AccountScreen.resetPassword;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  AnimatedContainer(
                    duration: motionDuration(context, 220),
                    height: MediaQuery.viewInsetsOf(context).bottom > 0
                        ? 90
                        : 205,
                    child: const WaterArtwork(),
                  ),
                  const Text(
                    'Water District Connect',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Maramag, Philippines',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 24),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          reset ? 'Reset password' : 'Welcome back',
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          reset
                              ? 'Choose a new password for your account.'
                              : 'Sign in to your verified account',
                          style: const TextStyle(color: muted, fontSize: 15),
                        ),
                        const SizedBox(height: 24),
                        if (!reset) input(emailController, 'Email address'),
                        if (!reset || !passwordSaved) ...[
                          input(
                            passwordController,
                            reset ? 'New password' : 'Password',
                            secret: true,
                          ),
                          if (reset)
                            input(
                              confirmController,
                              'Confirm new password',
                              secret: true,
                            ),
                          FilledButton(
                            onPressed: busy
                                ? null
                                : reset
                                ? saveNewPassword
                                : signIn,
                            child: !reset
                                ? Semantics(
                                    label: signingIn ? 'Signing in' : 'Sign in',
                                    liveRegion: signingIn,
                                    child: ExcludeSemantics(
                                      child: ClipRect(
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            if (signingIn)
                                              FadeTransition(
                                                opacity: signInSlide.drive(
                                                  CurveTween(
                                                    curve: const Interval(
                                                      .85,
                                                      1,
                                                    ),
                                                  ),
                                                ),
                                                child: const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                              ),
                                            SlideTransition(
                                              position: signInOffset,
                                              child: const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text('Sign in'),
                                                  SizedBox(width: 12),
                                                  Icon(
                                                    Icons.arrow_forward,
                                                    size: 19,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (busy)
                                        const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      else
                                        Text(
                                          reset
                                              ? 'Save new password'
                                              : 'Sign in',
                                        ),
                                      if (!busy) ...[
                                        const SizedBox(width: 12),
                                        const Icon(
                                          Icons.arrow_forward,
                                          size: 19,
                                        ),
                                      ],
                                    ],
                                  ),
                          ),
                        ],
                        TextButton(
                          onPressed: busy
                              ? null
                              : reset
                              ? returnToLogin
                              : requestPasswordReset,
                          child: Text(
                            reset ? 'Return to sign in' : 'Forgot password?',
                          ),
                        ),
                        if (message != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                message!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isError
                                      ? Theme.of(context).colorScheme.error
                                      : royalBlue,
                                ),
                              ),
                            ),
                          ),
                        if (!reset)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDF2FF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  backgroundColor: Color(0xFF1A4FD6),
                                  foregroundColor: Colors.white,
                                  child: Icon(Icons.people_outline),
                                ),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Need help signing in?',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: ink,
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        'Ask authorized district personnel for assistance.',
                                        style: TextStyle(
                                          color: muted,
                                          height: 1.45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ServiceAccountsPage extends StatefulWidget {
  const ServiceAccountsPage({super.key});

  @override
  State<ServiceAccountsPage> createState() => _ServiceAccountsPageState();
}

class _ServiceAccountsPageState extends State<ServiceAccountsPage> {
  List<Map<String, dynamic>> accounts = [];
  bool loading = true;
  bool adding = false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    loadAccounts();
  }

  Future<void> loadAccounts() async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final result = await supabase
          .from('service_accounts')
          .select('id, account_number, holder_name, service_address, active')
          .order('account_number');
      if (!mounted) return;
      setState(() => accounts = result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loadError =
            'Could not load accounts. Check your connection and '
            'administrator access, then retry.';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> addAccount() async {
    if (adding) return;
    setState(() => adding = true);
    try {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AddServiceAccountPage()),
      );
      if (!mounted) return;
      if (saved == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: SuccessNotice('Water-service account saved.'),
          ),
        );
        await loadAccounts();
      }
    } finally {
      if (mounted) setState(() => adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Water-service accounts'),
        actions: [
          IconButton(
            tooltip: 'Refresh accounts',
            onPressed: loading || adding ? null : loadAccounts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: adding || loading ? null : addAccount,
        icon: const Icon(Icons.add),
        label: const Text('Add account'),
      ),
      body: Column(
        children: [
          if (loading && accounts.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (loadError != null && accounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(child: Text(loadError!)),
                  TextButton(
                    onPressed: loading ? null : loadAccounts,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: loading && accounts.isEmpty
                ? const Center(
                    child: SingleChildScrollView(child: LoadingCards()),
                  )
                : loadError != null && accounts.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(loadError!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: loadAccounts,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : accounts.isEmpty
                ? EmptyState(
                    title: 'No service accounts yet',
                    message: 'Add a water-service account to begin managing district records.',
                    icon: Icons.people_outline,
                    actionLabel: 'Add account',
                    onAction: addAccount,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: accounts.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final account = accounts[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.water_drop_outlined),
                          title: Text('${account['account_number']}'),
                          subtitle: Text(
                            '${account['holder_name']}\n'
                            '${account['service_address']}',
                          ),
                          isThreeLine: true,
                          trailing: Text(
                            account['active'] == true ? 'Active' : 'Inactive',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class AddServiceAccountPage extends StatefulWidget {
  const AddServiceAccountPage({super.key});

  @override
  State<AddServiceAccountPage> createState() => _AddServiceAccountPageState();
}

class _AddServiceAccountPageState extends State<AddServiceAccountPage> {
  final formKey = GlobalKey<FormState>();
  final numberController = TextEditingController();
  final holderController = TextEditingController();
  final addressController = TextEditingController();
  bool saving = false;
  String? error;

  @override
  void dispose() {
    numberController.dispose();
    holderController.dispose();
    addressController.dispose();
    super.dispose();
  }

  String? requiredField(String? value) {
    return value == null || value.trim().isEmpty
        ? 'This field is required.'
        : null;
  }

  Future<void> saveAccount() async {
    if (saving || !formKey.currentState!.validate()) return;
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(
        () => error = 'Your session has ended. Return and sign in again.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await supabase.from('service_accounts').insert({
        'account_number': numberController.text.trim(),
        'holder_name': holderController.text.trim(),
        'service_address': addressController.text.trim(),
        'active': true,
        'updated_by': user.id,
      });
    } on PostgrestException catch (exception) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = exception.code == '23505'
            ? 'This account number already exists. Enter a different number.'
            : exception.code == '42501'
            ? 'Access denied. Check your active administrator profile '
                  'and database policies.'
            : 'The account could not be saved. Check the database setup '
                  'and try again.';
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error =
            'The save could not be confirmed. Return to the account list '
            'and refresh before retrying.';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Add water-service account')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Use fictional records while testing. This creates a '
                      'water-service record; client login access is linked separately.',
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: numberController,
                      enabled: !saving,
                      validator: requiredField,
                      decoration: const InputDecoration(
                        labelText: 'Account number',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: holderController,
                      enabled: !saving,
                      validator: requiredField,
                      decoration: const InputDecoration(
                        labelText: 'Registered holder name',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: addressController,
                      enabled: !saving,
                      validator: requiredField,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Service address',
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (error != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    FilledButton.icon(
                      onPressed: saving ? null : saveAccount,
                      icon: const Icon(Icons.save_outlined),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(saving ? 'Saving...' : 'Save account'),
                      ),
                    ),
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

class ClientAccountPage extends StatefulWidget {
  const ClientAccountPage({super.key});

  @override
  State<ClientAccountPage> createState() => _ClientAccountPageState();
}

class _ClientAccountPageState extends State<ClientAccountPage> {
  Map<String, dynamic>? account;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    loadAccount();
  }

  Future<void> loadAccount() async {
    setState(() {
      loading = true;
      error = null;
      account = null;
    });
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw StateError('No signed-in user.');
      }
      final link = await supabase
          .from('account_access')
          .select('account_id')
          .eq('user_id', user.id)
          .eq('active', true)
          .maybeSingle();
      Map<String, dynamic>? result;
      if (link != null) {
        result = await supabase
            .from('service_accounts')
            .select('account_number, holder_name, service_address, active')
            .eq('id', link['account_id'])
            .maybeSingle();
      }
      if (!mounted) return;
      setState(() => account = result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error =
            'Could not load your account. Check your connection and retry. '
            'If this continues, contact authorized district personnel.';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = account;
    final holder = record?['holder_name'] as String? ?? '';
    final initials = holder
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0])
        .join();
    return Scaffold(
      appBar: AppBar(
        title: const Text('My account'),
        backgroundColor: royalBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: loading ? null : loadAccount,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: const ClientDesignNav(index: 3),
      body: loading
          ? const LoadingCards()
          : Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (error != null) ...[
                        Text(error!),
                        TextButton(
                          onPressed: loadAccount,
                          child: const Text('Retry'),
                        ),
                      ] else if (record == null)
                        const Text(
                          'No linked account is available. Contact authorized district personnel.',
                        )
                      else ...[
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: royalBlue,
                              foregroundColor: Colors.white,
                              child: Text(
                                initials,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    holder,
                                    style: const TextStyle(
                                      fontSize: 23,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Registered account holder',
                                    style: TextStyle(color: muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: [
                                DesignValue(
                                  'Account number',
                                  '${record['account_number']}',
                                ),
                                const Divider(height: 24),
                                DesignValue('Registered holder', holder),
                                const Divider(height: 24),
                                DesignValue(
                                  'Service address',
                                  '${record['service_address']}',
                                ),
                                const Divider(height: 24),
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Account status',
                                        style: TextStyle(color: muted),
                                      ),
                                    ),
                                    StatusBadge(
                                      record['active'] == true
                                          ? 'Active'
                                          : 'Inactive',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const DesignHelp(
                          icon: Icons.edit_note,
                          title: 'Need to correct your details?',
                          text: 'Contact authorized district personnel.',
                        ),
                        const SizedBox(height: 16),
                        const DesignHelp(
                          icon: Icons.help_outline,
                          title: 'Need help using the app?',
                          text: 'An authorized representative may assist after district verification.',
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text('Sign out'),
                          onPressed: () async {
                            try {
                              await supabase.auth.signOut();
                              if (context.mounted) {
                                Navigator.of(context)
                                    .popUntil((r) => r.isFirst);
                              }
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not sign out. Please retry.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// Use centavos to avoid floating-point rounding in payment totals.
int moneyCentavos(Object? value) {
  final text = value.toString();
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) {
    throw FormatException('Invalid monetary value', text);
  }
  final parts = text.split('.');
  return int.parse(parts[0]) * 100 +
      int.parse(parts.length == 1 ? '00' : parts[1].padRight(2, '0'));
}

String formatCentavos(int value) =>
    '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';

int billPayments(Map<String, dynamic> bill) {
  final payments = bill['offline_payments'] as List;
  return payments.fold<int>(
    0,
    (total, payment) => total + moneyCentavos(payment['amount_paid']),
  );
}

class BillsPage extends StatefulWidget {
  const BillsPage({super.key, required this.isAdmin});
  final bool isAdmin;
  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  List<Map<String, dynamic>> bills = [];
  bool loading = true;
  bool outstandingOnly = true;
  String? error;

  @override
  void initState() {
    super.initState();
    loadBills();
  }

  Future<void> loadBills() async {
    setState(() {
      loading = true;
      error = null;
      bills = [];
    });
    try {
      // Both bills and their embedded payments remain protected by RLS.
      final rows = await supabase
          .from('bills')
          .select(
            'bill_number, billing_period_start, billing_period_end, due_date, '
            'amount_due, service_accounts(account_number), offline_payments(amount_paid)',
          )
          .order('due_date', ascending: false);
      // Validate totals before rendering; malformed data must not appear as paid.
      for (final bill in rows) {
        moneyCentavos(bill['amount_due']);
        billPayments(bill);
      }
      if (mounted) setState(() => bills = rows);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not load bills and payment totals. Check your connection and database access, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> addBill() async {
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const AddBillPage()));
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: SuccessNotice('Bill saved.')));
    await loadBills();
  }

  @override
  Widget build(BuildContext context) {
    final visibleBills = bills
        .where(
          (bill) =>
              !outstandingOnly ||
              moneyCentavos(bill['amount_due']) > billPayments(bill),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'Manage bills' : 'My bills'),
        actions: [
          IconButton(
            tooltip: 'Refresh bills',
            onPressed: loading ? null : loadBills,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: widget.isAdmin
          ? null
          : const ClientDesignNav(index: 1),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: loading ? null : addBill,
              icon: const Icon(Icons.add),
              label: const Text('Add bill'),
            )
          : null,
      body: Column(
        children: [
          if (loading && bills.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (error != null && bills.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(child: Text(error!)),
                  TextButton(
                    onPressed: loading ? null : loadBills,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              children: [
                ChoiceChip(
                  label: const Text('Outstanding'),
                  selected: outstandingOnly,
                  onSelected: (_) => setState(() => outstandingOnly = true),
                ),
                ChoiceChip(
                  label: const Text('All bills'),
                  selected: !outstandingOnly,
                  onSelected: (_) => setState(() => outstandingOnly = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: loading && bills.isEmpty
                ? const Center(
                    child: SingleChildScrollView(child: LoadingCards()),
                  )
                : error != null && bills.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error!, textAlign: TextAlign.center),
                          TextButton(
                            onPressed: loadBills,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : visibleBills.isEmpty
                ? EmptyState(
                    title: outstandingOnly
                        ? 'No outstanding bills'
                        : 'No bills yet',
                    message: outstandingOnly
                        ? 'You can still review your billing history.'
                        : 'New billing records will appear here.',
                    icon: Icons.receipt_long_outlined,
                    actionLabel: outstandingOnly
                        ? 'View all bills'
                        : widget.isAdmin
                        ? 'Add bill'
                        : null,
                    onAction: outstandingOnly
                        ? () => setState(() => outstandingOnly = false)
                        : widget.isAdmin
                        ? addBill
                        : null,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: visibleBills.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final bill = visibleBills[index];
                      final account =
                          bill['service_accounts'] as Map<String, dynamic>?;
                      final billed = moneyCentavos(bill['amount_due']);
                      final paid = billPayments(bill);
                      final remaining = billed > paid ? billed - paid : 0;
                      final excess = paid > billed ? paid - billed : 0;
                      final status = remaining == 0
                          ? 'Paid'
                          : paid > 0
                          ? 'Partially paid'
                          : 'Unpaid';

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                children: [
                                  Text(
                                    'Bill ${bill['bill_number']}',
                                    style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  StatusBadge(status),
                                ],
                              ),
                              Text(
                                '${bill['billing_period_start']} – ${bill['billing_period_end']}',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 16,
                                ),
                              ),
                              const Divider(height: 28),
                              DesignValue(
                                'Original bill',
                                '₱${formatCentavos(billed)}',
                              ),
                              const SizedBox(height: 14),
                              DesignValue(
                                'Verified payments',
                                '₱${formatCentavos(paid)}',
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEDF2FF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: DesignValue(
                                  'Remaining balance',
                                  '₱${formatCentavos(remaining)}',
                                  strong: true,
                                ),
                              ),
                              const SizedBox(height: 18),
                              DesignValue('Due date', '${bill['due_date']}'),
                              const SizedBox(height: 10),
                              Text(
                                'Account: ${account?['account_number'] ?? 'Unavailable'}',
                                style: const TextStyle(color: muted),
                              ),
                              if (excess > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    'Recorded payments exceed this bill by ₱${formatCentavos(excess)}. Contact district personnel for review.',
                                  ),
                                ),
                              if (paid > 0)
                                TextButton.icon(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PaymentsPage(
                                        isAdmin: widget.isAdmin,
                                        billNumber: '${bill['bill_number']}',
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.receipt_long_outlined),
                                  label: const Text('View payment record'),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class AddBillPage extends StatefulWidget {
  const AddBillPage({super.key});
  @override
  State<AddBillPage> createState() => _AddBillPageState();
}

class _AddBillPageState extends State<AddBillPage> {
  final form = GlobalKey<FormState>();
  final billNumber = TextEditingController();
  final amount = TextEditingController();
  List<Map<String, dynamic>> accounts = [];
  String? accountId;
  DateTime? periodStart, periodEnd, dueDate;
  bool loading = true, saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    loadAccounts();
  }

  @override
  void dispose() {
    billNumber.dispose();
    amount.dispose();
    super.dispose();
  }

  Future<void> loadAccounts() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await supabase
          .from('service_accounts')
          .select('id, account_number, holder_name')
          .eq('active', true)
          .order('account_number');
      if (mounted) setState(() => accounts = rows);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not load service accounts. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String dateText(DateTime date) => date.toIso8601String().split('T').first;

  Future<void> pickDate(int field) async {
    final current = field == 0
        ? periodStart
        : field == 1
        ? periodEnd
        : dueDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (field == 0) {
        periodStart = selected;
      } else if (field == 1) {
        periodEnd = selected;
      } else {
        dueDate = selected;
      }
    });
  }

  Future<void> saveBill() async {
    if (saving || !form.currentState!.validate()) return;
    if (periodStart == null || periodEnd == null || dueDate == null) {
      setState(() => error = 'Select all three dates.');
      return;
    }
    if (periodEnd!.isBefore(periodStart!)) {
      setState(() => error = 'The period end cannot precede the period start.');
      return;
    }
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => error = 'Your session has ended. Sign in again.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await supabase.from('bills').insert({
        'account_id': accountId,
        'bill_number': billNumber.text.trim(),
        'billing_period_start': dateText(periodStart!),
        'billing_period_end': dateText(periodEnd!),
        'due_date': dateText(dueDate!),
        'amount_due': amount.text.trim(),
        'created_by': user.id,
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = e.code == '23505'
            ? 'This bill number already exists.'
            : e.code == '42501'
            ? 'Access denied. Only active administrators can add bills.'
            : 'Could not save the bill. Check the database setup and entered values.';
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = 'Save could not be confirmed. Return to the bills list and refresh before retrying.';
      });
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Add bill')),
        body: loading
            ? const Center(child: SingleChildScrollView(child: LoadingCards()))
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Enter the amount already computed by the district. Use fictional bills for testing.',
                          ),
                          const SizedBox(height: 20),
                          if (accounts.isEmpty) ...[
                            const Text('No active accounts are available.'),
                            TextButton(
                              onPressed: loadAccounts,
                              child: const Text('Reload accounts'),
                            ),
                          ],
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Water-service account',
                            ),
                            items: accounts
                                .map(
                                  (a) => DropdownMenuItem<String>(
                                    value: a['id'] as String,
                                    child: Text(
                                      '${a['account_number']} - ${a['holder_name']}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: saving
                                ? null
                                : (value) => setState(() => accountId = value),
                            validator: (_) =>
                                accountId == null ? 'Choose an account.' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: billNumber,
                            enabled: !saving,
                            decoration: const InputDecoration(
                              labelText: 'Bill number',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Enter a bill number.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: amount,
                            enabled: !saving,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'District-computed amount (PHP)',
                            ),
                            validator: (v) =>
                                RegExp(r'^\d{1,10}(\.\d{1,2})?$')
                                    .hasMatch(v?.trim() ?? '')
                                ? null
                                : 'Enter a nonnegative amount with up to two decimal places.',
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: saving ? null : () => pickDate(0),
                            child: Text(
                              'Period start: ${periodStart == null ? 'Choose date' : dateText(periodStart!)}',
                            ),
                          ),
                          OutlinedButton(
                            onPressed: saving ? null : () => pickDate(1),
                            child: Text(
                              'Period end: ${periodEnd == null ? 'Choose date' : dateText(periodEnd!)}',
                            ),
                          ),
                          OutlinedButton(
                            onPressed: saving ? null : () => pickDate(2),
                            child: Text(
                              'Due date: ${dueDate == null ? 'Choose date' : dateText(dueDate!)}',
                            ),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: saving || accounts.isEmpty
                                ? null
                                : saveBill,
                            child: Text(saving ? 'Saving...' : 'Save bill'),
                          ),
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

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key, required this.isAdmin, this.billNumber});
  final String? billNumber;
  final bool isAdmin;
  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  List<Map<String, dynamic>> payments = [];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    loadPayments();
  }

  Future<void> loadPayments() async {
    setState(() {
      loading = true;
      error = null;
      payments = [];
    });
    try {
      // Database policies restrict records independently of the screen role.
      final rows = await supabase
          .from('offline_payments')
          .select(
            'receipt_reference, payment_date, amount_paid, verified_at, '
            'bills(bill_number, service_accounts(account_number))',
          )
          .order('payment_date', ascending: false);
      if (mounted) {
        setState(
          () => payments = widget.billNumber == null
              ? rows
              : rows
                    .where(
                      (p) =>
                          (p['bills']
                              as Map<String, dynamic>?)?['bill_number'] ==
                          widget.billNumber,
                    )
                    .toList(),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not load payments. Check your connection and database access, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> recordPayment() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const RecordPaymentPage()));
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: SuccessNotice('Verified offline payment recorded.'),
      ),
    );
    await loadPayments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isAdmin ? 'Verified offline payments' : 'My payments',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh payments',
            onPressed: loading ? null : loadPayments,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: loading ? null : recordPayment,
              icon: const Icon(Icons.add),
              label: const Text('Record payment'),
            )
          : null,
      body: Column(
        children: [
          if (loading && payments.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (error != null && payments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(child: Text(error!)),
                  TextButton(
                    onPressed: loading ? null : loadPayments,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: loading && payments.isEmpty
                ? const Center(
                    child: SingleChildScrollView(child: LoadingCards()),
                  )
                : error != null && payments.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error!, textAlign: TextAlign.center),
                          TextButton(
                            onPressed: loadPayments,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : payments.isEmpty
                ? EmptyState(
                    title: 'No payments recorded',
                    message: 'Verified offline payments will appear here once recorded by the district.',
                    icon: Icons.receipt_long_outlined,
                    actionLabel: widget.isAdmin ? 'Record payment' : null,
                    onAction: widget.isAdmin ? recordPayment : null,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: payments.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final payment = payments[index];
                      final bill = payment['bills'] as Map<String, dynamic>?;
                      final account =
                          bill?['service_accounts'] as Map<String, dynamic>?;
                      final amount = num.parse('${payment['amount_paid']}')
                          .toStringAsFixed(2);
                      final verified = DateTime.tryParse(
                        '${payment['verified_at']}',
                      )?.toLocal();
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Chip(
                                avatar: Icon(Icons.verified_outlined, size: 18),
                                label: Text('Verified offline payment'),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'PHP $amount',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              Text(
                                'Receipt/reference: ${payment['receipt_reference']}',
                              ),
                              Text(
                                'Bill: ${bill?['bill_number'] ?? 'Unavailable'}',
                              ),
                              Text(
                                'Account: ${account?['account_number'] ?? 'Unavailable'}',
                              ),
                              Text('Payment date: ${payment['payment_date']}'),
                              if (verified != null)
                                Text(
                                  'Recorded: ${verified.toString().split('.').first}',
                                ),
                              const SizedBox(height: 12),
                              const Text(
                                'This is a record of an offline payment, not a newly issued receipt.',
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class RecordPaymentPage extends StatefulWidget {
  const RecordPaymentPage({super.key});
  @override
  State<RecordPaymentPage> createState() => _RecordPaymentPageState();
}

class _RecordPaymentPageState extends State<RecordPaymentPage> {
  final form = GlobalKey<FormState>();
  final receipt = TextEditingController();
  final amount = TextEditingController();
  List<Map<String, dynamic>> bills = [];
  String? billId;
  DateTime? paymentDate;
  bool loading = true, saving = false, verified = false;
  String? error;

  @override
  void initState() {
    super.initState();
    loadBills();
  }

  @override
  void dispose() {
    receipt.dispose();
    amount.dispose();
    super.dispose();
  }

  Future<void> loadBills() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await supabase
          .from('bills')
          .select('id, bill_number, service_accounts(account_number)')
          .order('created_at', ascending: false);
      if (mounted) setState(() => bills = rows);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not load bills. Please retry.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String dateText(DateTime date) => date.toIso8601String().split('T').first;

  Future<void> chooseDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: paymentDate ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (selected != null && mounted) setState(() => paymentDate = selected);
  }

  Future<void> savePayment() async {
    if (saving || !form.currentState!.validate()) return;
    if (paymentDate == null || !verified) {
      setState(
        () => error = 'Choose the payment date and confirm verification.',
      );
      return;
    }
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => error = 'Your session has ended. Sign in again.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await supabase.from('offline_payments').insert({
        'bill_id': billId,
        'receipt_reference': receipt.text.trim(),
        'payment_date': dateText(paymentDate!),
        'amount_paid': amount.text.trim(),
        'verified_by': user.id,
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = e.code == '23505'
            ? 'This receipt/reference is already recorded.'
            : e.code == '42501'
            ? 'Recording denied. Check administrator access and ensure the date is not in the future according to the database.'
            : 'Could not record payment. Check the entered values and database setup.';
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = 'Save could not be confirmed. Return to the payment list and refresh before retrying.';
      });
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Record offline payment')),
        body: loading
            ? const Center(child: SingleChildScrollView(child: LoadingCards()))
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Record payments only after checking district records. '
                            'For prototype testing, use fictional receipts. One receipt applies to one bill.',
                          ),
                          const SizedBox(height: 20),
                          if (bills.isEmpty) ...[
                            const Text('No bills are available.'),
                            TextButton(
                              onPressed: loadBills,
                              child: const Text('Reload bills'),
                            ),
                          ],
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Bill',
                            ),
                            items: bills.map((b) {
                              final account =
                                  b['service_accounts']
                                      as Map<String, dynamic>?;
                              return DropdownMenuItem<String>(
                                value: b['id'] as String,
                                child: Text(
                                  '${b['bill_number']} — ${account?['account_number'] ?? ''}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: saving
                                ? null
                                : (value) => setState(() => billId = value),
                            validator: (_) =>
                                billId == null ? 'Choose a bill.' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: receipt,
                            enabled: !saving,
                            decoration: const InputDecoration(
                              labelText: 'Receipt/reference number',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Enter the receipt/reference.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: amount,
                            enabled: !saving,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Verified amount paid (PHP)',
                            ),
                            validator: (v) {
                              final text = v?.trim() ?? '';
                              if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$')
                                      .hasMatch(text) ||
                                  (num.tryParse(text) ?? 0) <= 0) {
                                return 'Enter an amount greater than zero, with up to two decimal places.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: saving ? null : chooseDate,
                            child: Text(
                              'Payment date: ${paymentDate == null ? 'Choose date' : dateText(paymentDate!)}',
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: verified,
                            onChanged: saving
                                ? null
                                : (value) =>
                                      setState(() => verified = value ?? false),
                            title: const Text(
                              'I verified this payment against the corresponding records.',
                            ),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ),
                          FilledButton(
                            onPressed: saving || bills.isEmpty
                                ? null
                                : savePayment,
                            child: Text(
                              saving ? 'Saving...' : 'Record verified payment',
                            ),
                          ),
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

class ConcernsPage extends StatefulWidget {
  const ConcernsPage({super.key, required this.isAdmin});
  final bool isAdmin;
  @override
  State<ConcernsPage> createState() => _ConcernsPageState();
}

class _ConcernsPageState extends State<ConcernsPage> {
  List<Map<String, dynamic>> concerns = [];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    loadConcerns();
  }

  Future<void> loadConcerns() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await supabase
          .from('service_concerns')
          .select(
            'id, account_id, category, subject, description, status, admin_response, '
            'created_at, reviewed_at, service_accounts(account_number)',
          )
          .order('created_at', ascending: false);
      if (mounted) setState(() => concerns = rows);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not load concerns. Check your connection and database access.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> openConcern([Map<String, dynamic>? concern]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ConcernFormPage(concern: concern)),
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: SuccessNotice(
          concern == null ? 'Concern submitted.' : 'Review saved.',
        ),
      ),
    );
    await loadConcerns();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'Manage concerns' : 'My concerns'),
        actions: [
          IconButton(
            tooltip: 'Refresh concerns',
            onPressed: loading ? null : loadConcerns,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: widget.isAdmin
          ? null
          : FloatingActionButton.extended(
              onPressed: loading ? null : () => openConcern(),
              icon: const Icon(Icons.add),
              label: const Text('Submit concern'),
            ),
      body: Column(
        children: [
          if (loading && concerns.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (error != null && concerns.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(child: Text(error!)),
                  TextButton(
                    onPressed: loading ? null : loadConcerns,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: loading && concerns.isEmpty
                ? const Center(
                    child: SingleChildScrollView(child: LoadingCards()),
                  )
                : error != null && concerns.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error!, textAlign: TextAlign.center),
                          TextButton(
                            onPressed: loadConcerns,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : concerns.isEmpty
                ? EmptyState(
                    title: 'No concerns yet',
                    message: widget.isAdmin
                        ? 'New client concerns will appear here.'
                        : 'Need help with your water service?',
                    icon: Icons.chat_bubble_outline,
                    actionLabel: widget.isAdmin ? null : 'Submit concern',
                    onAction: widget.isAdmin ? null : () => openConcern(),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: concerns.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final c = concerns[index];
                      final account =
                          c['service_accounts'] as Map<String, dynamic>?;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${c['subject']}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              StatusBadge('${c['status']}'),
                              Text(
                                'Account: ${account?['account_number'] ?? 'Unavailable'}',
                              ),
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                expandedCrossAxisAlignment:
                                    CrossAxisAlignment.start,
                                title: const Text(
                                  'Request details and response',
                                ),
                                children: [
                                  Text('Category: ${c['category']}'),
                                  Text(
                                    'Submitted: ${DateTime.parse(c['created_at'] as String).toLocal().toString().split('.').first}',
                                  ),
                                  const SizedBox(height: 12),
                                  Text('${c['description']}'),
                                  const Divider(height: 24),
                                  Text(
                                    'District response',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  Text(
                                    (c['admin_response'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? c['admin_response'] as String
                                        : 'No response recorded yet.',
                                  ),
                                  if (c['reviewed_at'] != null)
                                    Text(
                                      'Reviewed: ${DateTime.parse(c['reviewed_at'] as String).toLocal().toString().split('.').first}',
                                    ),
                                ],
                              ),
                              if (widget.isAdmin) ...[
                                const SizedBox(height: 12),
                                FilledButton.tonal(
                                  onPressed: () => openConcern(c),
                                  child: const Text('Review concern'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class ConcernFormPage extends StatefulWidget {
  const ConcernFormPage({super.key, this.concern});
  final Map<String, dynamic>? concern;
  @override
  State<ConcernFormPage> createState() => _ConcernFormPageState();
}

class _ConcernFormPageState extends State<ConcernFormPage> {
  final form = GlobalKey<FormState>();
  final subject = TextEditingController();
  final description = TextEditingController();
  final response = TextEditingController();
  String category = 'Water supply';
  String status = 'Submitted';
  String? accountId, accountNumber, error;
  bool loading = true, saving = false;
  bool get reviewing => widget.concern != null;

  @override
  void initState() {
    super.initState();
    final concern = widget.concern;
    if (concern != null) {
      status = concern['status'] as String;
      response.text = concern['admin_response'] as String? ?? '';
      loading = false;
    } else {
      loadAccount();
    }
  }

  @override
  void dispose() {
    subject.dispose();
    description.dispose();
    response.dispose();
    super.dispose();
  }

  Future<void> loadAccount() async {
    setState(() {
      loading = true;
      error = null;
      accountId = null;
    });
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw StateError('No session');
      final link = await supabase
          .from('account_access')
          .select('account_id, service_accounts(account_number)')
          .eq('user_id', user.id)
          .eq('active', true)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        accountId = link?['account_id'] as String?;
        accountNumber =
            (link?['service_accounts']
                    as Map<String, dynamic>?)?['account_number']
                as String?;
        if (accountId == null) error = 'No active account link is available. Contact authorized district personnel.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not load your linked account. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> saveConcern() async {
    if (saving || !form.currentState!.validate()) return;
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => error = 'Your session has ended. Sign in again.');
      return;
    }
    if (!reviewing && accountId == null) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (reviewing) {
        // Request a returned row so an RLS-denied zero-row update is not called success.
        final updated = await supabase
            .from('service_concerns')
            .update({
              'status': status,
              'admin_response': response.text.trim().isEmpty
                  ? null
                  : response.text.trim(),
              'reviewed_by': user.id,
              'reviewed_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', widget.concern!['id'])
            .select('id')
            .maybeSingle();
        if (updated == null) throw StateError('No accessible concern updated');
      } else {
        await supabase.from('service_concerns').insert({
          'account_id': accountId,
          'submitted_by': user.id,
          'category': category,
          'subject': subject.text.trim(),
          'description': description.text.trim(),
        });
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = e.code == '42501'
            ? 'Access denied. Check your active profile, account link, and database policies.'
            : 'Could not save the concern. Check the entered values and database setup.';
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = 'Save could not be confirmed. Return to the concerns list and refresh before retrying.';
      });
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(reviewing ? 'Review concern' : 'Submit concern'),
          backgroundColor: royalBlue,
          foregroundColor: Colors.white,
        ),
        bottomNavigationBar: reviewing ? null : const ClientDesignNav(index: 2),
        body: loading
            ? const Center(child: SingleChildScrollView(child: LoadingCards()))
            : Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (reviewing) ...[
                            Text(
                              '${widget.concern!['subject']}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            Text('${widget.concern!['description']}'),
                            const SizedBox(height: 24),
                            DropdownButtonFormField<String>(
                              initialValue: status,
                              decoration: const InputDecoration(
                                labelText: 'Concern status',
                              ),
                              items:
                                  [
                                        'Submitted',
                                        'Under review',
                                        'Resolved',
                                        'Closed',
                                      ]
                                      .map(
                                        (s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(s),
                                        ),
                                      )
                                      .toList(),
                              onChanged: saving
                                  ? null
                                  : (value) => setState(() => status = value!),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: response,
                              enabled: !saving,
                              minLines: 3,
                              maxLines: 8,
                              maxLength: 3000,
                              decoration: const InputDecoration(
                                labelText: 'Response to client',
                              ),
                              validator: (v) =>
                                  (status == 'Resolved' ||
                                          status == 'Closed') &&
                                      (v == null || v.trim().isEmpty)
                                  ? 'Explain the resolution or closure.'
                                  : null,
                            ),
                          ] else ...[
                            Text(
                              'Water-service account: ${accountNumber ?? 'Unavailable'}',
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: category,
                              decoration: const InputDecoration(
                                labelText: 'What is your concern?',
                              ),
                              items:
                                  [
                                        'Water supply',
                                        'Billing inquiry',
                                        'Repair request',
                                        'Other',
                                      ]
                                      .map(
                                        (c) => DropdownMenuItem(
                                          value: c,
                                          child: Text(c),
                                        ),
                                      )
                                      .toList(),
                              onChanged: saving
                                  ? null
                                  : (value) =>
                                        setState(() => category = value!),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: subject,
                              enabled: !saving,
                              maxLength: 150,
                              decoration: const InputDecoration(
                                labelText: 'Subject',
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Enter a subject.'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: description,
                              enabled: !saving,
                              minLines: 4,
                              maxLines: 10,
                              maxLength: 3000,
                              decoration: const InputDecoration(
                                labelText: 'Description',
                                helperText:
                                    'Describe the issue and when it started.',
                                helperMaxLines: 2,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Describe your concern.'
                                  : null,
                            ),
                            if (accountId == null)
                              TextButton(
                                onPressed: loadAccount,
                                child: const Text('Reload linked account'),
                              ),
                          ],
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed:
                                saving || (!reviewing && accountId == null)
                                ? null
                                : saveConcern,
                            child: Text(
                              saving
                                  ? 'Saving...'
                                  : reviewing
                                  ? 'Save review'
                                  : 'Submit concern',
                            ),
                          ),
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

class RepairTicketsPage extends StatefulWidget {
  const RepairTicketsPage({super.key, required this.isAdmin});
  final bool isAdmin;
  @override
  State<RepairTicketsPage> createState() => _RepairTicketsPageState();
}

class _RepairTicketsPageState extends State<RepairTicketsPage> {
  List<Map<String, dynamic>> tickets = [];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    loadTickets();
  }

  Future<void> loadTickets() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await supabase
          .from('repair_tickets')
          .select(
            'id, concern_id, assigned_to, status, latest_update, updated_at, '
            'service_concerns(subject, service_accounts(account_number))',
          )
          .order('updated_at', ascending: false);
      if (mounted) setState(() => tickets = rows);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not load repair tickets. Check your connection and database access.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> editTicket([Map<String, dynamic>? ticket]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RepairTicketFormPage(ticket: ticket)),
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: SuccessNotice('Repair ticket saved.')),
    );
    await loadTickets();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isAdmin ? 'Manage repair tickets' : 'Repair updates',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh tickets',
            onPressed: loading ? null : loadTickets,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: widget.isAdmin
          ? null
          : const ClientDesignNav(index: 2),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: loading ? null : () => editTicket(),
              icon: const Icon(Icons.add),
              label: const Text('Create ticket'),
            )
          : null,
      body: Column(
        children: [
          if (loading && tickets.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (error != null && tickets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(child: Text(error!)),
                  TextButton(
                    onPressed: loading ? null : loadTickets,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: loading && tickets.isEmpty
                ? const Center(
                    child: SingleChildScrollView(child: LoadingCards()),
                  )
                : error != null && tickets.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error!, textAlign: TextAlign.center),
                          TextButton(
                            onPressed: loadTickets,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : tickets.isEmpty
                ? EmptyState(
                    title: 'No repair tickets yet',
                    message: 'Recorded repair assignments and updates will appear here.',
                    icon: Icons.build_outlined,
                    actionLabel: widget.isAdmin ? 'Create ticket' : null,
                    onAction: widget.isAdmin ? () => editTicket() : null,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: tickets.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final t = tickets[index];
                      final concern =
                          t['service_concerns'] as Map<String, dynamic>?;
                      final account =
                          concern?['service_accounts'] as Map<String, dynamic>?;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${concern?['subject'] ?? 'Repair ticket'}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              StatusBadge('${t['status']}'),
                              DesignRepairStages(status: '${t['status']}'),
                              SelectableText('Ticket ID: ${t['id']}'),
                              Text(
                                'Account: ${account?['account_number'] ?? 'Unavailable'}',
                              ),
                              Text(
                                'Assigned to: ${t['assigned_to'] ?? 'Not assigned'}',
                              ),
                              const Divider(height: 24),
                              Text(
                                'Latest recorded update',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text('${t['latest_update']}'),
                              const SizedBox(height: 8),
                              Text(
                                'Updated: ${DateTime.parse(t['updated_at'] as String).toLocal().toString().split('.').first}',
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Updates are entered by district personnel. This is not live repair tracking.',
                              ),
                              if (widget.isAdmin) ...[
                                const SizedBox(height: 12),
                                FilledButton.tonal(
                                  onPressed: () => editTicket(t),
                                  child: const Text('Update ticket'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class RepairTicketFormPage extends StatefulWidget {
  const RepairTicketFormPage({super.key, this.ticket});
  final Map<String, dynamic>? ticket;
  @override
  State<RepairTicketFormPage> createState() => _RepairTicketFormPageState();
}

class _RepairTicketFormPageState extends State<RepairTicketFormPage> {
  final form = GlobalKey<FormState>();
  final assignment = TextEditingController();
  final update = TextEditingController();
  List<Map<String, dynamic>> concerns = [];
  String? concernId, error;
  String status = 'Open';
  bool loading = true, saving = false;
  bool get editing => widget.ticket != null;

  @override
  void initState() {
    super.initState();
    final ticket = widget.ticket;
    if (ticket != null) {
      status = ticket['status'] as String;
      assignment.text = ticket['assigned_to'] as String? ?? '';
      update.text = ticket['latest_update'] as String;
      concernId = ticket['concern_id'] as String;
      loading = false;
    } else {
      loadConcerns();
    }
  }

  @override
  void dispose() {
    assignment.dispose();
    update.dispose();
    super.dispose();
  }

  Future<void> loadConcerns() async {
    setState(() {
      loading = true;
      error = null;
      concernId = null;
    });
    try {
      final rows = await supabase
          .from('service_concerns')
          .select(
            'id, subject, status, service_accounts(account_number), repair_tickets(id)',
          )
          .inFilter('status', ['Submitted', 'Under review'])
          .order('created_at', ascending: false);
      // UNIQUE(concern_id) may embed the relationship as a map, not a list.
      final available = rows.where((c) {
        final linked = c['repair_tickets'];
        return linked == null || (linked is List && linked.isEmpty);
      }).toList();
      if (mounted) setState(() => concerns = available);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not load eligible concerns. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> saveTicket() async {
    if (saving || !form.currentState!.validate()) return;
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => error = 'Your session has ended. Sign in again.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final values = <String, dynamic>{
      'assigned_to': assignment.text.trim().isEmpty
          ? null
          : assignment.text.trim(),
      'status': status,
      'latest_update': update.text.trim(),
      'updated_by': user.id,
    };
    try {
      if (editing) {
        values['updated_at'] = DateTime.now().toUtc().toIso8601String();
        final saved = await supabase
            .from('repair_tickets')
            .update(values)
            .eq('id', widget.ticket!['id'])
            .select('id')
            .maybeSingle();
        if (saved == null) throw StateError('No accessible ticket updated');
      } else {
        values['concern_id'] = concernId;
        values['created_by'] = user.id;
        await supabase.from('repair_tickets').insert(values);
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = e.code == '23505'
            ? 'A ticket already exists for this concern. Return to the ticket list and refresh.'
            : e.code == '42501'
            ? 'Access denied. Check your active administrator profile and database policies.'
            : 'Could not save the ticket. Check the entered values and database setup.';
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = 'Save could not be confirmed. Return to the ticket list and refresh before retrying.';
      });
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            editing ? 'Update repair ticket' : 'Create repair ticket',
          ),
        ),
        body: loading
            ? const Center(child: SingleChildScrollView(child: LoadingCards()))
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!editing) ...[
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Concern requiring repair',
                              ),
                              items: concerns.map((c) {
                                final account =
                                    c['service_accounts']
                                        as Map<String, dynamic>?;
                                return DropdownMenuItem(
                                  value: c['id'] as String,
                                  child: Text(
                                    '${account?['account_number'] ?? ''} — ${c['subject']}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: saving
                                  ? null
                                  : (value) =>
                                        setState(() => concernId = value),
                              validator: (_) => concernId == null
                                  ? 'Choose a concern.'
                                  : null,
                            ),
                            if (concerns.isEmpty) ...[
                              const Text(
                                'No open concerns without a repair ticket are available.',
                              ),
                              TextButton(
                                onPressed: loadConcerns,
                                child: const Text('Reload concerns'),
                              ),
                            ],
                            const SizedBox(height: 16),
                          ],
                          DropdownButtonFormField<String>(
                            initialValue: status,
                            decoration: const InputDecoration(
                              labelText: 'Ticket status',
                            ),
                            items:
                                ['Open', 'Assigned', 'In progress', 'Resolved']
                                    .map(
                                      (s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(s),
                                      ),
                                    )
                                    .toList(),
                            onChanged: saving
                                ? null
                                : (value) => setState(() => status = value!),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: assignment,
                            enabled: !saving,
                            maxLength: 150,
                            decoration: const InputDecoration(
                              labelText: 'Assigned personnel or team',
                            ),
                            validator: (v) =>
                                ['Assigned', 'In progress'].contains(status) &&
                                    (v == null || v.trim().isEmpty)
                                ? 'Record the assigned personnel or team.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: update,
                            enabled: !saving,
                            minLines: 4,
                            maxLines: 10,
                            maxLength: 3000,
                            decoration: const InputDecoration(
                              labelText: 'Latest update visible to the client',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Enter a progress update or resolution.'
                                : null,
                          ),
                          const Text(
                            'Saving replaces the latest update. Review the original concern separately when closing it.',
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: saving || (!editing && concerns.isEmpty)
                                ? null
                                : saveTicket,
                            child: Text(saving ? 'Saving...' : 'Save ticket'),
                          ),
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

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key, required this.isAdmin});
  final bool isAdmin;
  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  List<Map<String, dynamic>> announcements = [];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    loadAnnouncements();
  }

  Future<void> loadAnnouncements() async {
    setState(() {
      loading = true;
      error = null;
      announcements = [];
    });
    try {
      // RLS hides drafts from clients even if a request omits the filter.
      var query = supabase
          .from('announcements')
          .select('id, title, message, published, updated_at');
      if (!widget.isAdmin) query = query.eq('published', true);
      final rows = await query.order('updated_at', ascending: false);
      if (mounted) setState(() => announcements = rows);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not load announcements. Check your connection and database access.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> editAnnouncement([Map<String, dynamic>? announcement]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AnnouncementFormPage(announcement: announcement),
      ),
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: SuccessNotice('Announcement saved.')),
    );
    await loadAnnouncements();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'Manage announcements' : 'Announcements'),
        actions: [
          IconButton(
            tooltip: 'Refresh announcements',
            onPressed: loading ? null : loadAnnouncements,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: loading ? null : () => editAnnouncement(),
              icon: const Icon(Icons.add),
              label: const Text('Create announcement'),
            )
          : null,
      body: Column(
        children: [
          if (loading && announcements.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (error != null && announcements.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(child: Text(error!)),
                  TextButton(
                    onPressed: loading ? null : loadAnnouncements,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: loading && announcements.isEmpty
                ? const Center(
                    child: SingleChildScrollView(child: LoadingCards()),
                  )
                : error != null && announcements.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error!, textAlign: TextAlign.center),
                          TextButton(
                            onPressed: loadAnnouncements,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : announcements.isEmpty
                ? EmptyState(
                    title: 'No notices yet',
                    message: 'District notices and service interruptions will appear here.',
                    icon: Icons.campaign_outlined,
                    actionLabel: widget.isAdmin ? 'Create announcement' : null,
                    onAction: widget.isAdmin ? () => editAnnouncement() : null,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: announcements.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final a = announcements[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                noticeTitle(a['title']),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (isInterruption(a['title']))
                                const StatusBadge('Service interruption'),
                              if (widget.isAdmin)
                                Chip(
                                  label: Text(
                                    a['published'] == true
                                        ? 'Published'
                                        : 'Draft',
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Text('${a['message']}'),
                              const SizedBox(height: 16),
                              Text(
                                'Updated: ${DateTime.parse(a['updated_at'] as String).toLocal().toString().split('.').first}',
                              ),
                              if (widget.isAdmin) ...[
                                const SizedBox(height: 12),
                                FilledButton.tonal(
                                  onPressed: () => editAnnouncement(a),
                                  child: const Text(
                                    'Edit / change publication',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class AnnouncementFormPage extends StatefulWidget {
  const AnnouncementFormPage({super.key, this.announcement});
  final Map<String, dynamic>? announcement;
  @override
  State<AnnouncementFormPage> createState() => _AnnouncementFormPageState();
}

class _AnnouncementFormPageState extends State<AnnouncementFormPage> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final message = TextEditingController();
  bool published = false, saving = false, interruption = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final a = widget.announcement;
    if (a != null) {
      interruption = isInterruption(a['title']);
      title.text = noticeTitle(a['title']);
      message.text = a['message'] as String;
      published = a['published'] as bool;
    }
  }

  @override
  void dispose() {
    title.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> saveAnnouncement() async {
    if (saving || !form.currentState!.validate()) return;
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => error = 'Your session has ended. Sign in again.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final values = <String, dynamic>{
      'title': '${interruption ? interruptionPrefix : ''}${title.text.trim()}',
      'message': message.text.trim(),
      'published': published,
      'updated_by': user.id,
    };
    try {
      final existing = widget.announcement;
      if (existing == null) {
        values['created_by'] = user.id;
        await supabase.from('announcements').insert(values);
      } else {
        values['updated_at'] = DateTime.now().toUtc().toIso8601String();
        final saved = await supabase
            .from('announcements')
            .update(values)
            .eq('id', existing['id'])
            .select('id')
            .maybeSingle();
        if (saved == null) {
          throw StateError('No accessible announcement updated');
        }
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = e.code == '42501'
            ? 'Access denied. Check your active administrator profile and database policies.'
            : 'Could not save the announcement. Check the entered values and database setup.';
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = 'Save could not be confirmed. Return to the announcements list and refresh before retrying.';
      });
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.announcement == null
                ? 'Create announcement'
                : 'Edit announcement',
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Clearly label fictional notices as prototype samples during testing.',
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: title,
                      enabled: !saving,
                      maxLength: interruption
                          ? 150 - interruptionPrefix.length
                          : 150,
                      decoration: const InputDecoration(labelText: 'Title'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter a title.'
                          : v.trim().length +
                                    (interruption
                                        ? interruptionPrefix.length
                                        : 0) >
                                150
                          ? 'Shorten the title to fit the notice type.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: message,
                      enabled: !saving,
                      minLines: 5,
                      maxLines: 15,
                      maxLength: 5000,
                      decoration: const InputDecoration(
                        labelText: 'Announcement message',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter an announcement message.'
                          : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Service interruption'),
                      subtitle: const Text(
                        'Highlight this notice as a water-service interruption.',
                      ),
                      value: interruption,
                      onChanged: saving
                          ? null
                          : (value) => setState(() => interruption = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Publish to clients'),
                      subtitle: Text(
                        published
                            ? 'Saving makes this notice visible to active clients.'
                            : 'Saving keeps this notice visible only to administrators.',
                      ),
                      value: published,
                      onChanged: saving
                          ? null
                          : (value) => setState(() => published = value),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: saving ? null : saveAnnouncement,
                      child: Text(
                        saving
                            ? 'Saving...'
                            : published
                            ? 'Save and publish'
                            : 'Save as draft',
                      ),
                    ),
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

const royalBlue = Color(0xFF1A4FD6);
const ink = Color(0xFF324C82);
const muted = Color(0xFF526077);

ThemeData waterTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: royalBlue).copyWith(
    primary: royalBlue,
    onPrimary: Colors.white,
    surface: const Color(0xFFFFFFFF),
    onSurface: ink,
    onSurfaceVariant: muted,
    secondary: royalBlue,
    primaryContainer: const Color(0xFFE6EDFF),
    onPrimaryContainer: royalBlue,
    secondaryContainer: const Color(0xFFE6EDFF),
    onSecondaryContainer: royalBlue,
    outline: const Color(0xFFE1E6EB),
    outlineVariant: const Color(0xFFE1E6EB),
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'DM Sans',
    splashFactory: InkRipple.splashFactory,
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
    ),
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF6F9FC),
    textTheme: ThemeData.light().textTheme.apply(
      fontFamily: 'DM Sans',
      bodyColor: ink,
      displayColor: ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF6F9FC),
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE1E6EB)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF2F5F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      labelStyle: const TextStyle(color: muted),
      prefixIconColor: muted,
      suffixIconColor: muted,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE1E6EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: royalBlue, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFamily: 'DM Sans',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xFFFFFFFF),
      indicatorColor: Color(0xFFE6EDFF),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(
        fontFamily: 'DM Sans',
        fontWeight: FontWeight.w600,
        fontSize: 11,
        color: muted,
      )),
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: royalBlue)),
      elevation: 0,
      height: 76,
    ),
  );
}

class WaterArtwork extends StatefulWidget {
  const WaterArtwork({super.key});
  @override
  State<WaterArtwork> createState() => _WaterArtworkState();
}

class _WaterArtworkState extends State<WaterArtwork>
    with TickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  late final AnimationController water = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );
  late final AnimationController logo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool started = false;

  @override
  void initState() {
    super.initState();
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) logo.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      water.stop();
      controller.stop();
      controller.value = 1;
      logo.stop();
      logo.value = 1;
      started = true;
    } else {
      if (!water.isAnimating) water.repeat();
      if (!started) {
        started = true;
        controller.forward(); // The droplet falls once per login-screen mount.
      }
    }
  }

  @override
  void dispose() {
    logo.dispose();
    water.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRect(
      child: AnimatedBuilder(
        animation: Listenable.merge([controller, water, logo]),
        child: Image.asset(
          'assets/images/maramag-water-district-logo.png',
          fit: BoxFit.contain,
          cacheWidth: 512,
          excludeFromSemantics: true,
        ),
        builder: (_, child) => LayoutBuilder(
          builder: (_, constraints) {
            final diameter = math.min(
              constraints.maxWidth * .42,
              constraints.maxHeight * .44,
            );
            final landingTop = constraints.maxHeight * .77 - diameter / 2;
            final descent = Curves.easeOutCubic.transform(logo.value);
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: WaterPainter(
                      progress: controller.value,
                      waterPhase: water.value,
                    ),
                  ),
                ),
                if (logo.value > 0)
                  Positioned(
                    key: const ValueKey('water-district-logo'),
                    left: (constraints.maxWidth - diameter) / 2,
                    top: -diameter + (landingTop + diameter) * descent,
                    width: diameter,
                    height: diameter,
                    child: IgnorePointer(child: child!),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class WaterPainter extends CustomPainter {
  const WaterPainter({this.progress = 1, this.waterPhase = 0});
  final double waterPhase;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .77);
    // Periodic sine motion joins smoothly across the repeating cycle.
    for (var i = 0; i < 4; i++) {
      final y =
          size.height * (.34 + i * .09) +
          math.sin(waterPhase * math.pi * 2 + i * .8) * 4;
      final path = Path()
        ..moveTo(0, y)
        ..cubicTo(
          size.width * .24,
          y - 65,
          size.width * .37,
          y + 90,
          size.width * .64,
          y + 18,
        )
        ..cubicTo(
          size.width * .82,
          y - 20,
          size.width * .92,
          y - 10,
          size.width,
          y - 24,
        )
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.lerp(
            const Color(0xFFEDF2FF),
            const Color(0xFFD7E1FA),
            i / 4,
          )!.withValues(alpha: .65),
      );
    }
    // Static surface remains when all motion has finished.
    final pool = Rect.fromCenter(
      center: center,
      width: size.width * .94,
      height: size.height * .33,
    );
    canvas.drawOval(
      pool,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFD7E1FA), Color(0xFFEDF2FF)],
        ).createShader(pool),
    );
    for (var i = 1; i <= 4; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width:
              size.width * (.16 + i * .16) +
              math.sin(waterPhase * math.pi * 2 + i) * 9,
          height:
              size.height * (.025 + i * .045) +
              math.sin(waterPhase * math.pi * 2 + i) * 2,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: .35),
      );
    }

    // 0–1 s: one droplet accelerates downwards and merges into the surface.
    if (progress < .25) {
      final fall = (progress / .25).clamp(0.0, 1.0);
      final eased = Curves.easeInQuad.transform(fall);
      final merge = ((fall - .78) / .22).clamp(0.0, 1.0);
      final height = size.height * .43 * (1 - merge);
      final width = size.height * .30 * (1 - merge * .65);
      final bottom =
          size.height * .43 + (center.dy - size.height * .43) * eased;
      final x = center.dx;
      final top = bottom - height;
      final path = Path()
        ..moveTo(x, top)
        ..cubicTo(
          x - width * .12,
          top + height * .30,
          x - width * .64,
          top + height * .57,
          x - width * .47,
          top + height * .81,
        )
        ..cubicTo(
          x - width * .32,
          bottom + height * .10,
          x + width * .32,
          bottom + height * .10,
          x + width * .47,
          top + height * .81,
        )
        ..cubicTo(
          x + width * .64,
          top + height * .57,
          x + width * .12,
          top + height * .30,
          x,
          top,
        )
        ..close();
      final bounds = Rect.fromLTWH(
        x - width * .6,
        top,
        width * 1.2,
        height + 1,
      );
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFFE6EDFF), royalBlue, const Color(0xFF324C82)],
          ).createShader(bounds),
      );
      if (merge < .8) {
        final highlight = Path()
          ..moveTo(x - width * .30, top + height * .65)
          ..quadraticBezierTo(
            x - width * .32,
            top + height * .86,
            x - width * .08,
            top + height * .88,
          );
        canvas.drawPath(
          highlight,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 4 * (1 - merge)
            ..color = Colors.white.withValues(alpha: .9 * (1 - merge)),
        );
      }
    }

    // 1–3.4 s: expanding rings damp out. 3.4–4 s and later are identical.
    if (progress >= .25 && progress < .85) {
      final elapsed = (progress - .25) / .60;
      for (var i = 0; i < 4; i++) {
        final t = ((elapsed - i * .09) / (1 - i * .09)).clamp(0.0, 1.0);
        if (t <= 0) continue;
        final spread = Curves.easeOutCubic.transform(t);
        final alpha = (1 - t) * (1 - t) * .8;
        final ring = Rect.fromCenter(
          center: center,
          width: size.width * (.06 + .92 * spread),
          height: size.height * (.02 + .36 * spread),
        );
        canvas.drawOval(
          ring,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * (1 - t) + .5
            ..color = royalBlue.withValues(alpha: alpha * .55),
        );
        canvas.drawOval(
          ring.inflate(2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white.withValues(alpha: alpha),
        );
      }
    }
    // Blend the artwork into the page instead of ending at a hard rectangle.
    final fadeArea = Rect.fromLTRB(
      0,
      size.height * .67,
      size.width,
      size.height,
    );
    canvas.drawRect(
      fadeArea,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00F6F9FC), Color(0x99F6F9FC), Color(0xFFF6F9FC)],
          stops: [0, .58, 1],
        ).createShader(fadeArea),
    );
  }

  @override
  bool shouldRepaint(covariant WaterPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.waterPhase != waterPhase;
}

class ModernDashboard extends StatefulWidget {
  const ModernDashboard({
    super.key,
    required this.profile,
    required this.onSignOut,
    required this.signingOut,
  });
  final Map<String, dynamic> profile;
  final Future<void> Function() onSignOut;
  final bool signingOut;
  @override
  State<ModernDashboard> createState() => _ModernDashboardState();
}

class _ModernDashboardState extends State<ModernDashboard> {
  bool get admin => widget.profile['role'] == 'admin';
  int tab = 0;
  bool loading = true;
  String? error, accountNumber, nextDueDate;
  bool hasLoaded = false;
  bool get initialLoading => loading && !hasLoaded;
  int remaining = 0, billCount = 0;
  int? pendingConcerns, activeRepairs;
  List<Map<String, dynamic>> recent = [], notices = [];
  @override
  void initState() {
    super.initState();
    clientDesignTab.addListener(selectClientTab);
    refresh();
  }

  void selectClientTab() {
    if (mounted && !admin) setState(() => tab = clientDesignTab.value);
  }

  @override
  void dispose() {
    clientDesignTab.removeListener(selectClientTab);
    super.dispose();
  }

  Future<void> refresh() async {
    if (loading && hasLoaded) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final concernsQuery = supabase
          .from('service_concerns')
          .select(
            'subject, status, created_at, service_accounts(account_number)',
          );
      final concernRows =
          await (admin
                  ? concernsQuery.inFilter('status', [
                      'Submitted',
                      'Under review',
                    ])
                  : concernsQuery)
              .order('created_at', ascending: false)
              .limit(2);
      final noticeRows = await supabase
          .from('announcements')
          .select('title, message, updated_at')
          .eq('published', true)
          .order('updated_at', ascending: false)
          .limit(10);
      noticeRows.sort(
        (a, b) => (isInterruption(b['title']) ? 1 : 0).compareTo(
          isInterruption(a['title']) ? 1 : 0,
        ),
      );
      String? number;
      int balance = 0, count = 0;
      String? upcoming;
      int? pending, repairs;
      if (admin) {
        pending = await supabase.from('service_concerns').count(CountOption.exact)
            .inFilter('status', ['Submitted', 'Under review']);
        repairs = await supabase.from('repair_tickets').count(CountOption.exact)
            .inFilter('status', ['Open', 'Assigned', 'In progress']);
      }
      if (!admin) {
        final uid = supabase.auth.currentUser?.id;
        if (uid == null) throw StateError('Signed out');
        final link = await supabase
            .from('account_access')
            .select('service_accounts(account_number)')
            .eq('user_id', uid)
            .eq('active', true)
            .maybeSingle();
        number =
            (link?['service_accounts']
                    as Map<String, dynamic>?)?['account_number']
                as String?;
        final rows = await supabase
            .from('bills')
            .select('amount_due, due_date, offline_payments(amount_paid)');
        count = rows.length;
        for (final bill in rows) {
          final due = moneyCentavos(bill['amount_due']) - billPayments(bill);
          if (due > 0) {
            balance += due;
            final date = bill['due_date'] as String?;
            if (date != null &&
                (upcoming == null || date.compareTo(upcoming) < 0)) {
              upcoming = date;
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        pendingConcerns = pending;
        activeRepairs = repairs;
        recent = concernRows;
        notices = noticeRows.take(2).toList();
        accountNumber = number;
        remaining = balance;
        billCount = count;
        nextDueDate = upcoming;
        hasLoaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not refresh the overview. Your records are available through the menu.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> open(Widget page) async {
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: SuccessNotice('Changes saved.')));
    }
    await refresh();
  }

  Widget iconBubble(IconData icon) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: royalBlue,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Icon(icon, color: Colors.white, size: 27),
  );

  Widget tile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback action, {
    bool compact = false,
  }) {
    return PressFeedback(
      child: Card(
        child: InkWell(
          onTap: action,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: royalBlue, size: 26),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget pair(Widget left, Widget right) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 400 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 12), right],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              const SizedBox(width: 12),
              Expanded(child: right),
            ],
          ),
        );
      },
    ),
  );

  Widget groupHeading(String title, String description) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        Text(description, style: const TextStyle(color: muted, height: 1.4)),
      ],
    ),
  );
  Widget rowTile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback action,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: PressFeedback(
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: action,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                iconBubble(icon),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: const TextStyle(color: muted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: royalBlue),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget sectionTitle(String title, VoidCallback action) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      TextButton(onPressed: action, child: const Text('View all')),
    ],
  );

  Widget requests() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      sectionTitle(
        admin ? 'Needs attention' : 'Recent request',
        () => open(ConcernsPage(isAdmin: admin)),
      ),
      if (initialLoading)
        const LoadingCards(count: 1)
      else if (hasLoaded && recent.isEmpty)
        EmptyState(
          title: admin ? 'You’re all caught up' : 'No concerns yet',
          message: admin
              ? 'No new concerns need review.'
              : 'Your submitted concerns and responses will appear here.',
          actionLabel: admin ? null : 'Submit concern',
          onAction: admin ? null : () => open(const ConcernFormPage()),
        )
      else if (hasLoaded)
        for (final c in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => open(ConcernsPage(isAdmin: admin)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      iconBubble(Icons.chat_bubble_outline),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${c['subject']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Account ${(c['service_accounts'] as Map<String, dynamic>?)?['account_number'] ?? '—'}',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            StatusBadge('${c['status']}'),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: royalBlue),
                    ],
                  ),
                ),
              ),
            ),
          ),
    ],
  );

  Widget announcements() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      sectionTitle(
        'Announcements',
        () => open(AnnouncementsPage(isAdmin: admin)),
      ),
      if (hasLoaded && notices.isEmpty)
        const Text(
          'No published announcements.',
          style: TextStyle(color: muted),
        ),
      if (hasLoaded)
        for (final n in notices) ...[
          if (isInterruption(n['title']))
            const StatusBadge('Service interruption'),
          rowTile(
            noticeTitle(n['title']),
            (n['message'] as String).length > 120
                ? '${(n['message'] as String).substring(0, 120)}…'
                : n['message'] as String,
            isInterruption(n['title'])
                ? Icons.warning_amber_rounded
                : Icons.campaign_outlined,
            () => open(AnnouncementsPage(isAdmin: admin)),
          ),
        ],
    ],
  );

  Widget adminOverview() => Container(
    margin: const EdgeInsets.only(bottom: 20),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: const Color(0xFFEDF2FF),
      border: Border.all(color: const Color(0xFFD7E1FA)),
    ),
    child: Stack(children: [
      Positioned(right: -35, bottom: -65, child: IgnorePointer(child: Container(
        width: 230, height: 160, decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: royalBlue.withValues(alpha: .08), width: 22)),
      ))),
      Padding(padding: const EdgeInsets.all(20), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [Icon(Icons.assignment_outlined, color: royalBlue, size: 25),
          SizedBox(width: 10), Expanded(child: Text('District overview',
            style: TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w700)))]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: overviewMetric(pendingConcerns, 'Pending concerns',
            () => open(const ConcernsPage(isAdmin: true)))),
          Container(height: 58, width: 1, color: const Color(0xFFD7E1FA)),
          Expanded(child: overviewMetric(activeRepairs, 'Active repairs',
            () => open(const RepairTicketsPage(isAdmin: true)))),
        ]),
        if (error != null) const Padding(padding: EdgeInsets.only(top: 10),
          child: Text('Overview could not refresh. Pull down to retry.',
            style: TextStyle(color: muted, fontSize: 13))),
      ])),
    ]),
  );

  Widget overviewMetric(int? value, String label, VoidCallback action) => InkWell(
    onTap: action,
    borderRadius: BorderRadius.circular(12),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Column(children: [
      Text(value?.toString() ?? '—', style: const TextStyle(
        color: royalBlue, fontSize: 30, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text(label, textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF455571), fontSize: 14)),
    ])),
  );

  Widget balanceCard() => Container(
    padding: const EdgeInsets.all(20),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      color: const Color(0xFFEDF2FF),
      border: Border.all(color: const Color(0xFFD7E1FA)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Remaining balance',
          style: TextStyle(color: ink, fontSize: 18),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: motionDuration(context, 200),
          child: Align(
            alignment: Alignment.centerLeft,
            key: ValueKey('$initialLoading/$hasLoaded/$remaining'),
            child: Text(
              initialLoading
                  ? 'Loading…'
                  : !hasLoaded && error != null
                  ? 'Unavailable'
                  : '₱${formatCentavos(remaining)}',
              style: const TextStyle(
                color: royalBlue,
                fontSize: 38,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          initialLoading
              ? 'Updating records'
              : !hasLoaded && error != null
              ? 'Please refresh'
              : nextDueDate != null
              ? 'Earliest due date: $nextDueDate'
              : billCount == 0
              ? 'No bills recorded'
              : 'All bills paid',
          style: const TextStyle(color: Color(0xFF455571), fontSize: 16),
        ),
        const SizedBox(height: 18),
        FilledButton.tonal(
          onPressed: () => open(const BillsPage(isAdmin: false)),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: ink,
          ),
          child: const Row(
            children: [
              Expanded(
                child: Text(
                  'View bills',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.chevron_right),
            ],
          ),
        ),
      ],
    ),
  );

  List<Widget> homeContent() => admin
      ? [
          adminOverview(),
          requests(),
          groupHeading(
            'Accounts & billing',
            'Customer records, bills, and verified payments',
          ),
          rowTile(
            'Service accounts',
            'Manage customer records',
            Icons.people_outline,
            () => open(const ServiceAccountsPage()),
          ),
          rowTile(
            'Billing records',
            'View and manage bills',
            Icons.receipt_long_outlined,
            () => open(const BillsPage(isAdmin: true)),
          ),
          rowTile(
            'Verified payments',
            'Record verified offline payments',
            Icons.payments_outlined,
            () => open(const PaymentsPage(isAdmin: true)),
          ),
          groupHeading(
            'Service operations',
            'Review concerns and coordinate repair work',
          ),
          rowTile(
            'Repair updates',
            'Assign work and record progress',
            Icons.build_outlined,
            () => open(const RepairTicketsPage(isAdmin: true)),
          ),
          rowTile(
            'Service concerns',
            'Review and respond to clients',
            Icons.chat_bubble_outline,
            () => open(const ConcernsPage(isAdmin: true)),
          ),
          groupHeading(
            'Communications',
            'Keep customers informed about district services',
          ),
          rowTile(
            'Announcements',
            'Create and manage notices',
            Icons.campaign_outlined,
            () => open(const AnnouncementsPage(isAdmin: true)),
          ),
        ]
      : [
          balanceCard(),
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Payments are recorded after district verification.',
              style: TextStyle(color: muted, fontSize: 14),
            ),
          ),
          groupHeading(
            'Account activity',
            'Payment history and your registered details',
          ),
          pair(
            tile(
              'Payments',
              'View verified payment records.',
              Icons.receipt_outlined,
              () => open(const PaymentsPage(isAdmin: false)),
              compact: true,
            ),
            tile(
              'My account',
              'View your registered account details.',
              Icons.people_outline,
              () => open(const ClientAccountPage()),
              compact: true,
            ),
          ),
          groupHeading(
            'Service support',
            'Report an issue or follow repair progress',
          ),
          pair(
            tile(
              'Submit concern',
              'Report a service concern',
              Icons.chat_bubble_outline,
              () => open(const ConcernFormPage()),
              compact: true,
            ),
            tile(
              'Repair updates',
              'View recorded repair updates',
              Icons.build_outlined,
              () => open(const RepairTicketsPage(isAdmin: false)),
              compact: true,
            ),
          ),
          const SizedBox(height: 12),
          requests(),
          const SizedBox(height: 20),
          announcements(),
        ];

  List<Widget> tabContent() {
    if (tab == 0) return homeContent();
    if (tab == 1) {
      return admin
          ? [
              rowTile(
                'Service accounts',
                'Create and view water-service records',
                Icons.people_outline,
                () => open(const ServiceAccountsPage()),
              ),
              rowTile(
                'Billing records',
                'Add and view district-computed bills',
                Icons.receipt_long_outlined,
                () => open(const BillsPage(isAdmin: true)),
              ),
              rowTile(
                'Verified payments',
                'Record verified offline payments',
                Icons.payments_outlined,
                () => open(const PaymentsPage(isAdmin: true)),
              ),
            ]
          : [
              balanceCard(),
              rowTile(
                'My bills',
                'Outstanding bills and billing history',
                Icons.receipt_long_outlined,
                () => open(const BillsPage(isAdmin: false)),
              ),
              rowTile(
                'Payments',
                'Verified offline payment records',
                Icons.payments_outlined,
                () => open(const PaymentsPage(isAdmin: false)),
              ),
            ];
    }
    if (tab == 2) {
      return [
        if (!admin)
          rowTile(
            'Submit concern',
            'Tell the district about a service issue',
            Icons.add_comment_outlined,
            () => open(const ConcernFormPage()),
          ),
        rowTile(
          admin ? 'Service concerns' : 'My concerns',
          'Responses and concern status',
          Icons.chat_bubble_outline,
          () => open(ConcernsPage(isAdmin: admin)),
        ),
        rowTile(
          'Repair updates',
          'Assignments and latest recorded updates',
          Icons.build_outlined,
          () => open(RepairTicketsPage(isAdmin: admin)),
        ),
      ];
    }
    return [
      if (!admin)
        rowTile(
          'My water-service account',
          'Registered holder and service address',
          Icons.person_outline,
          () => open(const ClientAccountPage()),
        ),
      rowTile(
        'Announcements',
        'Read district notices',
        Icons.campaign_outlined,
        () => open(AnnouncementsPage(isAdmin: admin)),
      ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: widget.signingOut ? null : widget.onSignOut,
        icon: const Icon(Icons.logout),
        label: Text(widget.signingOut ? 'Signing out…' : 'Sign out'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.profile['display_name'] as String? ?? 'Client';
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0])
        .join()
        .toUpperCase();
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    final heading = tab == 0
        ? (admin ? 'Administrator' : '$greeting, ${name.split(' ').first}')
        : tab == 1
        ? (admin ? 'Accounts & billing' : 'Bills & payments')
        : tab == 2
        ? 'Services'
        : admin
        ? 'More'
        : 'My account';
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        animationDuration: motionDuration(context, 220),
        selectedIndex: tab,
        onDestinationSelected: (value) {
          if (value != tab) setState(() => tab = value);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(
              admin ? Icons.people_outline : Icons.receipt_long_outlined,
            ),
            label: admin ? 'Accounts' : 'Bills',
          ),
          const NavigationDestination(
            icon: Icon(Icons.build_outlined),
            label: 'Services',
          ),
          NavigationDestination(
            icon: Icon(admin ? Icons.more_horiz : Icons.person_outline),
            label: admin ? 'More' : 'Account',
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, admin ? 40 : 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.water_drop, color: royalBlue, size: 40),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Water District Connect',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'Maramag, Philippines',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Account menu',
                              onPressed: () => setState(() => tab = 3),
                              icon: CircleAvatar(
                                backgroundColor: const Color(0xFF1A4FD6),
                                foregroundColor: Colors.white,
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (!admin) const Divider(),
                        const SizedBox(height: 20),
                        Text(
                          heading,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          admin
                              ? const [
                                  'Manage accounts and district services.',
                                  'Manage customer accounts, billing, and payments.',
                                  'Review concerns and track repair progress.',
                                  'District notices and session settings.',
                                ][tab]
                              : accountNumber == null
                              ? 'Your water-service information'
                              : 'Account $accountNumber',
                          style: const TextStyle(color: muted, fontSize: 15),
                        ),
                        const SizedBox(height: 20),
                        if (error != null)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text(error!),
                                  TextButton(
                                    onPressed: refresh,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (loading && hasLoaded)
                          const LinearProgressIndicator(minHeight: 2),
                        AnimatedSwitcher(
                          duration: motionDuration(context, 220),
                          child: Column(
                            key: ValueKey(tab),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: tabContent(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WaterStartup extends StatefulWidget {
  const WaterStartup({super.key, this.initialize, this.destination});
  final Future<void> Function()? initialize;
  final Widget? destination;
  @override
  State<WaterStartup> createState() => _WaterStartupState();
}

class _WaterStartupState extends State<WaterStartup>
    with SingleTickerProviderStateMixin {
  late final AnimationController pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  bool ready = false;
  String? error;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      pulse.stop();
    } else if (!ready && error == null && !pulse.isAnimating) {
      pulse.repeat(reverse: true);
    }
  }

  Future<void> initialize() async {
    final splashDelay = Future<void>.delayed(const Duration(seconds: 3));
    try {
      if (widget.initialize != null) {
        await widget.initialize!();
      } else {
        if (publishableKey.isEmpty) throw StateError('Missing configuration');
        await Supabase.initialize(
          url: projectUrl,
          publishableKey: publishableKey,
        );
      }
      if (!mounted) return;
      // Keep the spinner visible for at least three seconds while initializing.
      await splashDelay;
      if (!mounted) return;
      pulse.stop();
      setState(() => ready = true);
    } catch (e) {
      if (!mounted) return;
      pulse.stop();
      setState(
        () => error = e is StateError && e.message == 'Missing configuration'
            ? 'Database access is not configured. Contact the app administrator to finish setup.'
            : 'Unable to start the app (${e.runtimeType}). Check your connection and launch configuration, then restart.',
      );
    }
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: reduced ? Duration.zero : const Duration(milliseconds: 600),
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic.flipped,
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween<Offset>(
            begin: child.key == const ValueKey('loading')
                ? const Offset(-1, 0)
                : const Offset(1, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
        child: ready
            ? KeyedSubtree(
                key: const ValueKey('ready'),
                child: widget.destination ?? const AccountPage(),
              )
            : Scaffold(
                key: const ValueKey('loading'),
                backgroundColor: const Color(0xFF1A4FD6),
                body: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: pulse,
                              builder: (_, child) => Transform.scale(
                                scale: 1 + pulse.value * .06,
                                child: Container(
                                  width: 122,
                                  height: 122,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: .12),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: .22,
                                      ),
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.water_drop,
                                    color: Colors.white,
                                    size: 70,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            const Text(
                              'Water District\nConnect',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 32,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Maramag, Philippines',
                              style: TextStyle(
                                color: Color(0xFFE6EDFF),
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 38),
                            if (error == null) ...[
                              const SizedBox(
                                width: 25,
                                height: 25,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                  semanticsLabel: 'Loading',
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Preparing your water-service app…',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white),
                              ),
                            ] else
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

final clientDesignTab = DesignTabController();

class DesignTabController extends ChangeNotifier {
  int value = 0;
  void select(int index) {
    value = index;
    notifyListeners();
  }
}

class ClientDesignNav extends StatelessWidget {
  const ClientDesignNav({super.key, required this.index});
  final int index;
  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: index,
    onDestinationSelected: (i) {
      clientDesignTab.select(i);
      Navigator.of(context).popUntil((r) => r.isFirst);
    },
    destinations: const [
      NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
      NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        label: 'Bills',
      ),
      NavigationDestination(
        icon: Icon(Icons.build_outlined),
        label: 'Services',
      ),
      NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
    ],
  );
}

class DesignValue extends StatelessWidget {
  const DesignValue(this.label, this.value, {super.key, this.strong = false});
  final String label, value;
  final bool strong;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: strong ? ink : muted,
            fontSize: 16,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 16,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class DesignHelp extends StatelessWidget {
  const DesignHelp({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title, text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: royalBlue, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  text,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class DesignRepairStages extends StatelessWidget {
  const DesignRepairStages({super.key, required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    const stages = ['Open', 'Assigned', 'In progress', 'Resolved'];
    final current = stages.indexOf(status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          for (var i = 0; i < stages.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Icon(
                      i == current
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: i == current ? royalBlue : Colors.blueGrey,
                      size: 27,
                    ),
                    if (i < stages.length - 1)
                      Container(
                        width: 2,
                        height: 24,
                        color: const Color(0xFFE1E6EB),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      stages[i] + (i == current ? ' • Current status' : ''),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: i == current
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
