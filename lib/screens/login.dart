import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_size_matters/flutter_size_matters.dart';
import 'package:go_router/go_router.dart';
import 'package:icare/providers/auth_provider.dart';
import 'package:icare/screens/forget_password.dart';
import 'package:icare/screens/privacy_policy.dart';
import 'package:icare/screens/lab_profile_setup.dart';
import 'package:icare/screens/pharmacy_profile_setup.dart';
import 'package:icare/screens/student_profile_setup.dart';
import 'package:icare/services/auth_service.dart';
import 'package:icare/services/biometric_service.dart';
import 'package:icare/services/user_service.dart';
import 'package:icare/utils/shared_pref.dart';
import 'package:icare/models/user.dart' as app_user;
import 'package:icare/utils/imagePaths.dart';
import 'package:icare/utils/theme.dart';
import 'package:icare/utils/utils.dart';
import 'package:icare/widgets/custom_text.dart';
import 'package:icare/widgets/custom_text_input.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _fadeAnimation;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController licenseController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController orgNameController = TextEditingController();
  final TextEditingController credentialsController = TextEditingController();

  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final BiometricService _biometricService = BiometricService();

  bool rememberMe = false;
  bool isLogin = true;
  // bool isLogin = true; // signup toggle removed — always login
  bool isLoading = false;
  bool agreedToTerms = false;
  String selectedSignupRole = 'Patient';

  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _biometricLoading = false;

  bool _googleLoading = false;
  bool _appleLoading = false;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _logoScaleAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );
    _logoController.forward();
    _checkExistingRole();
    _initBiometrics();
  }

  @override
  void dispose() {
    _logoController.dispose();
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    phoneController.dispose();
    licenseController.dispose();
    locationController.dispose();
    orgNameController.dispose();
    credentialsController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingRole() async {
    final authState = ref.read(authProvider);
    final existingRole = authState.userRole;
    if (existingRole.isNotEmpty) {
      setState(() {
        isLogin = true;
      });
    }
  }

  Future<void> _initBiometrics() async {
    final available = await _biometricService.isAvailable();
    final enabled = await _biometricService.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
    });
    if (available && enabled) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) _triggerBiometricLogin();
    }
  }

  Future<void> _triggerBiometricLogin() async {
    if (_biometricLoading) return;
    setState(() => _biometricLoading = true);

    try {
      final result = await _biometricService.authenticate(
        reason: 'Sign in to iCare',
      );

      if (!mounted) return;
      setState(() => _biometricLoading = false);

      switch (result) {
        case BiometricResult.success:
          final token = await SharedPref().getBiometricToken();
          if (token != null && token.isNotEmpty) {
            final user = await SharedPref().getBiometricUserData();
            if (user != null && mounted) {
              await ref.read(authProvider.notifier).setUserToken(token);
              await ref.read(authProvider.notifier).setUser(user);
              if (mounted) context.go('/dashboard');
            } else {
              _showError('Session expired. Please sign in with your password.');
            }
          } else {
            _showError('Biometric not set up. Please sign in with your password first.');
          }
          break;
        case BiometricResult.notAvailable:
          _showError('Biometric not available on this device.');
          break;
        case BiometricResult.lockedOut:
          _showError('Too many attempts. Please use password to sign in.');
          break;
        case BiometricResult.cancelled:
        case BiometricResult.failed:
          break;
      }
    } catch (e) {
      debugPrint('Biometric login error: $e');
      if (!mounted) return;
      setState(() => _biometricLoading = false);
      _showError('Biometric authentication failed. Please use your password.');
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_googleLoading) return;
    setState(() => _googleLoading = true);
    try {
      final result = await _authService.loginWithGoogle();
      if (!mounted) return;
      if (result['success'] == true) {
        await _completeSocialLogin(result);
      } else {
        _showError(result['message'] ?? 'Google sign-in failed');
      }
    } catch (e) {
      if (mounted) _showError('Google sign-in error: $e');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _handleAppleSignIn() async {
    if (_appleLoading) return;
    setState(() => _appleLoading = true);
    try {
      final result = await _authService.loginWithApple();
      if (!mounted) return;
      if (result['success'] == true) {
        await _completeSocialLogin(result);
      } else {
        _showError(result['message'] ?? 'Apple sign-in failed');
      }
    } catch (e) {
      if (mounted) _showError('Apple sign-in error: $e');
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  Future<void> _completeSocialLogin(Map<String, dynamic> authResult) async {
    final data = authResult['data'] as Map<String, dynamic>? ?? {};
    final token = data['token']?.toString() ?? '';
    if (token.isEmpty) {
      _showError('Sign-in failed: no token received');
      return;
    }
    final profileResult = await _userService.getUserProfile(token: token);
    if (!mounted) return;
    if (profileResult['success'] == true) {
      final user = app_user.User.fromJson(profileResult['user'] as Map<String, dynamic>);
      await ref.read(authProvider.notifier).setUserToken(token);
      await ref.read(authProvider.notifier).setUser(user);
      if (mounted) context.go('/dashboard');
    } else {
      _showError('Could not load profile: ${profileResult['message']}');
    }
  }

  Future<void> _offerBiometricSetup(String email) async {
    if (!_biometricAvailable) return;
    final savedEmail = await _biometricService.getBiometricEmail();
    if (_biometricEnabled && savedEmail == email) return;
    final label = await _biometricService.getBiometricLabel();
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            label == 'Face Unlock' ? Icons.face_retouching_natural : Icons.fingerprint,
            color: AppColors.primaryColor,
            size: 36,
          ),
        ),
        title: Text(
          'Enable $label Sign-In?',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Text(
          'Sign in faster next time using $label instead of your password.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Now', style: TextStyle(color: Color(0xFF64748B))),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () async {
              final token = await SharedPref().getToken();
              final user = await SharedPref().getUserData();
              await _biometricService.enableBiometrics(
                email,
                token: token,
                user: user,
              );
              if (mounted) setState(() => _biometricEnabled = true);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 0,
            ),
            child: Text('Enable $label'),
          ),
        ],
      ),
    );
  }

  // ── _buildDynamicFields kept but only used if signup is re-enabled ───────
  // List<Widget> _buildDynamicFields({bool isMobile = false}) { ... }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final isDesktop = ResponsiveHelper.isDesktop(context);

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: isDesktop
          ? _buildDesktopLayout()
          : _buildMobileLayout(isTablet: isTablet),
    );
  }

  Widget _buildDesktopLayout() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return SizedBox(
      width: screenWidth,
      height: screenHeight,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              height: screenHeight,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF001E6C), Color(0xFF0036BC), Color(0xFF035BE5)],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -80, left: -80,
                    child: Container(
                      width: 300, height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.04),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -100, right: -50,
                    child: Container(
                      width: 350, height: 350,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.03),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 24, left: 24,
                    child: GestureDetector(
                      onTap: () => context.go('/home'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_rounded, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text('Home', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 50),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.10),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/Asset 1.png',
                              height: 80,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "by",
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white70),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Image.asset(
                              'assets/images/health.jpeg',
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Text('RM Health Solutions', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0036BC))),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            "Your Trusted Healthcare Platform",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Secure consultations, prescriptions\n& health records",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.7),
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 44),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildHeroTrust(Icons.shield_rounded, "Data Protected & Secure", "End-to-end encrypted health records", color: const Color(0xFFEF4444)),
                                    const SizedBox(height: 18),
                                    _buildHeroTrust(Icons.verified_user_rounded, "HIPAA Compliant", "Meeting US healthcare data security standards", color: const Color(0xFF10B981)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildHeroTrust(Icons.local_hospital_rounded, "Complete Digital Health Care Platform", "Consult, prescribe & manage all-in-one", color: const Color(0xFF8B5CF6)),
                                    const SizedBox(height: 18),
                                    _buildHeroTrust(Icons.people_rounded, "Open for Everyone", "For patients, doctors & healthcare providers", color: const Color(0xFFF59E0B)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            flex: 5,
            child: Container(
              color: const Color(0xFFF8FAFD),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Container(
                    width: 480,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 48,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0036BC).withValues(alpha: 0.06),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                          spreadRadius: 0,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF0036BC), Color(0xFF035BE5)],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.health_and_safety_rounded, color: Colors.white, size: 20),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  "Welcome back",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0036BC),
                                    fontFamily: "Gilroy-Medium",
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              "Sign in to\nyour account",
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0B2D6E),
                                fontFamily: "Gilroy-Bold",
                                letterSpacing: -1.0,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF0036BC), Color(0xFF035BE5)],
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 8,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF035BE5).withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "Access your health dashboard securely".tr(),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF94A3B8),
                                fontFamily: "Gilroy-Medium",
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              CustomInputField(
                                hintText: "Username or Email".tr(),
                                leadingIcon: const Icon(
                                  Icons.person_outline_rounded,
                                  color: Color(0xFF94A3B8),
                                  size: 22,
                                ),
                                controller: usernameController,
                                bgColor: const Color(0xFFF8FAFC),
                                borderRadius: 14,
                                borderColor: const Color(0xFFE2E8F0),
                                borderWidth: 1.5,
                                validator: (val) {
                                  if (val == null || val.isEmpty) {
                                    return "Please enter your username";
                                  }
                                  return null;
                                },
                              ),

                              // ── Signup-only fields COMMENTED OUT ─────────────
                              // if (!isLogin) ...[
                              //   const SizedBox(height: 16),
                              //   CustomInputField(hintText: "Email Address".tr(), ...),
                              //   const SizedBox(height: 16),
                              //   CustomInputField(hintText: "Phone Number".tr(), ...),
                              // ],

                              const SizedBox(height: 16),

                              CustomInputField(
                                hintText: "Password".tr(),
                                leadingIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                  color: Color(0xFF94A3B8),
                                  size: 22,
                                ),
                                controller: passwordController,
                                isPassword: true,
                                bgColor: const Color(0xFFF8FAFC),
                                borderRadius: 14,
                                borderColor: const Color(0xFFE2E8F0),
                                borderWidth: 1.5,
                                textInputAction: TextInputAction.done,
                                onEditingComplete: isLoading ? null : _handleSubmit,
                                validator: (val) {
                                  if (val == null || val.isEmpty) {
                                    return "Please enter your password";
                                  }
                                  return null;
                                },
                              ),

                              // ── Confirm password + terms COMMENTED OUT ────────
                              // if (!isLogin) ...[
                              //   const SizedBox(height: 16),
                              //   CustomInputField(controller: confirmPasswordController, hintText: "Confirm Password".tr(), ...),
                              //   const SizedBox(height: 16),
                              //   Row(children: [ Checkbox agreedToTerms ... ]),
                              // ],

                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: Checkbox(
                                          value: rememberMe,
                                          onChanged: (val) {
                                            setState(() => rememberMe = val!);
                                          },
                                          activeColor: AppColors.primaryColor,
                                          checkColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFFCBD5E1),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        "Remember me".tr(),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF64748B),
                                          fontFamily: "Gilroy-Medium",
                                        ),
                                      ),
                                    ],
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (ctx) => ForgetPassword(),
                                        ),
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 0),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      "Forgot Password?".tr(),
                                      style: const TextStyle(
                                        color: AppColors.primaryColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        fontFamily: "Gilroy-SemiBold",
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 28),

                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                    shadowColor: Colors.transparent,
                                  ),
                                  onPressed: isLoading ? null : _handleSubmit,
                                  child: isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          "Sign In".tr(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            fontFamily: "Gilroy-Bold",
                                          ),
                                        ),
                                ),
                              ),

                              const SizedBox(height: 20),
                              RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontFamily: "Gilroy-Medium"),
                                  children: [
                                    const TextSpan(text: "Don't have an account? "),
                                    TextSpan(
                                      text: "Sign Up",
                                      style: const TextStyle(color: AppColors.primaryColor, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                                      recognizer: TapGestureRecognizer()..onTap = () => context.go('/signup'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontFamily: "Gilroy-Medium"),
                                  children: [
                                    const TextSpan(text: "Are you a healthcare provider? "),
                                    TextSpan(
                                      text: "Work With Us",
                                      style: const TextStyle(color: AppColors.primaryColor, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                                      recognizer: TapGestureRecognizer()..onTap = () => context.go('/work-with-us'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),
                              Row(
                                children: [
                                  Expanded(child: Divider(color: Colors.grey[300], thickness: 1)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(
                                      "Or continue with".tr(),
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: "Gilroy-Medium",
                                      ),
                                    ),
                                  ),
                                  Expanded(child: Divider(color: Colors.grey[300], thickness: 1)),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _webSocialButton(
                                ImagePaths.google_icon,
                                "Continue with Google",
                                onTap: _handleGoogleSignIn,
                                isLoading: _googleLoading,
                              ),
                              if (!kIsWeb && Platform.isIOS) ...[
                                const SizedBox(height: 10),
                                _webAppleButton(
                                  onTap: _handleAppleSignIn,
                                  isLoading: _appleLoading,
                                ),
                              ],
                              if (_biometricAvailable) ...[
                                const SizedBox(height: 12),
                                _buildBiometricButton(isDesktop: true),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout({bool isTablet = false}) {
    return Container(
      width: Utils.windowWidth(context),
      height: Utils.windowHeight(context),
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(ImagePaths.backgroundImage),
          fit: BoxFit.cover,
        ),
      ),
      child: Stack(
        children: [
          Container(
            width: Utils.windowWidth(context),
            height: isTablet
                ? Utils.windowHeight(context) * 0.35
                : double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: ScallingConfig.moderateScale(15),
              vertical: ScallingConfig.moderateScale(isTablet ? 12 : 80),
            ),
            child: Column(
              mainAxisAlignment: isTablet
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: ScallingConfig.moderateScale(isTablet ? 5 : 30),
                ),
                CustomText(
                  text: "Go Ahead & Set Up Your Account",
                  fontWeight: FontWeight.bold,
                  maxLines: 2,
                  textAlign: isTablet ? TextAlign.center : TextAlign.start,
                  width: isTablet
                      ? Utils.windowWidth(context)
                      : Utils.windowWidth(context) * 0.6,
                  fontSize: 22,
                  color: AppColors.primaryColor,
                ),
                const SizedBox(height: 3),
                CustomText(
                  text: "Sign In To Get The Best Doctor Consultation Experience",
                  fontSize: 13,
                  textAlign: isTablet ? TextAlign.center : TextAlign.start,
                  width: isTablet
                      ? Utils.windowWidth(context)
                      : Utils.windowHeight(context) * 0.4,
                  color: AppColors.themeBlack,
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: isTablet
                  ? Utils.windowWidth(context) * 0.7
                  : double.infinity,
              height: Utils.windowHeight(context) * 0.67,
              decoration: BoxDecoration(
                color: isTablet
                    ? AppColors.bgColor.withAlpha(70)
                    : AppColors.bgColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: ScallingConfig.moderateScale(isTablet ? 50 : 15),
                  vertical: ScallingConfig.moderateScale(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF0036BC), Color(0xFF035BE5)],
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.health_and_safety_rounded, color: Colors.white, size: 16),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "Welcome back",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryColor,
                                fontFamily: "Gilroy-Medium",
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Sign in to\nyour account",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0B2D6E),
                            fontFamily: "Gilroy-Bold",
                            letterSpacing: -0.8,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 30,
                              height: 3,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF0036BC), Color(0xFF035BE5)],
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Container(
                              width: 6,
                              height: 3,
                              decoration: BoxDecoration(
                                color: const Color(0xFF035BE5).withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 25),

                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // ── Signup-only username field COMMENTED OUT ──────
                          // if (!isLogin)
                          //   CustomInputField(hintText: "Username or Email", ...),
                          // if (!isLogin) SizedBox(height: 5),
                          // if (!isLogin)
                          //   CustomInputField(hintText: "Email Address".tr(), ...),
                          // if (!isLogin) SizedBox(height: 5),
                          // if (!isLogin)
                          //   CustomInputField(hintText: "Phone Number".tr(), ...),
                          // SizedBox(height: 5),

                          CustomInputField(
                            hintText: "Username or Email",
                            leadingIcon: Icon(
                              Icons.person_outline,
                              color: AppColors.primary500,
                            ),
                            controller: usernameController,
                            bgColor: AppColors.white,
                            borderRadius: 30,
                            borderColor: AppColors.veryLightGrey,
                            borderWidth: 2,
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return "Please enter your username";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 5),

                          CustomInputField(
                            hintText: "Enter Your Password".tr(),
                            leadingIcon: Icon(
                              Icons.key,
                              color: AppColors.primary500,
                            ),
                            controller: passwordController,
                            isPassword: true,
                            bgColor: AppColors.white,
                            borderRadius: 30,
                            borderColor: AppColors.veryLightGrey,
                            borderWidth: 2,
                            textInputAction: TextInputAction.done,
                            onEditingComplete: isLoading ? null : _handleSubmit,
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return "Please enter your password";
                              }
                              return null;
                            },
                          ),

                          // ── Confirm password + terms COMMENTED OUT ────────
                          // if (!isLogin) ...[
                          //   SizedBox(height: 5),
                          //   CustomInputField(controller: confirmPasswordController, hintText: "Confirm Password".tr(), ...),
                          //   const SizedBox(height: 12),
                          //   Row(children: [ Checkbox agreedToTerms ... ]),
                          // ],

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Checkbox(
                                    value: rememberMe,
                                    onChanged: (val) {
                                      setState(() => rememberMe = val!);
                                    },
                                    activeColor: AppColors.primary500,
                                    checkColor: Colors.white,
                                    side: BorderSide(
                                      color: isTablet
                                          ? AppColors.white
                                          : AppColors.lightGrey200,
                                      width: 2,
                                    ),
                                  ),
                                  CustomText(
                                    text: "Remember me".tr(),
                                    fontSize: isTablet ? 12 : 15,
                                    color: isTablet
                                        ? AppColors.white
                                        : AppColors.lightGrey200,
                                  ),
                                ],
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (ctx) => ForgetPassword(),
                                    ),
                                  );
                                },
                                child: Text(
                                  "Forgot Password",
                                  style: TextStyle(
                                    color: isTablet
                                        ? AppColors.white
                                        : AppColors.primaryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          SizedBox(
                            width: double.infinity,
                            height: 60,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              onPressed: isLoading ? null : _handleSubmit,
                              child: isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      "Sign In".tr(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontFamily: "Gilroy-Medium"),
                              children: [
                                const TextSpan(text: "Don't have an account? "),
                                TextSpan(
                                  text: "Sign Up",
                                  style: const TextStyle(color: AppColors.primaryColor, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                                  recognizer: TapGestureRecognizer()..onTap = () => context.go('/signup'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontFamily: "Gilroy-Medium"),
                              children: [
                                const TextSpan(text: "Are you a healthcare provider? "),
                                TextSpan(
                                  text: "Work With Us",
                                  style: const TextStyle(color: AppColors.primaryColor, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                                  recognizer: TapGestureRecognizer()..onTap = () => context.go('/work-with-us'),
                                ),
                              ],
                            ),
                          ),
                          _buildMobileSocialRow(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: GestureDetector(
              onTap: () => context.go('/home'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded, color: AppColors.primaryColor, size: 15),
                    const SizedBox(width: 5),
                    Text('Home', style: TextStyle(color: AppColors.primaryColor, fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroTrust(IconData icon, String title, String subtitle, {Color? color}) {
    final iconColor = color ?? Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44, height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: iconColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileSocialRow() {
    return Column(
      children: [
        const SizedBox(height: 25),
        Text("Or Continue With".tr(), style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _socialButton(ImagePaths.google_icon, "Google",
                onTap: _handleGoogleSignIn, isLoading: _googleLoading),
            if (!kIsWeb && Platform.isIOS) ...[
              const SizedBox(width: 12),
              _mobileAppleButton(onTap: _handleAppleSignIn, isLoading: _appleLoading),
            ],
          ],
        ),
        if (_biometricAvailable) ...[
          const SizedBox(height: 12),
          _buildBiometricButton(isDesktop: false),
        ],
      ],
    );
  }

  Widget _buildBiometricButton({required bool isDesktop}) {
    return FutureBuilder<String>(
      future: _biometricService.getBiometricLabel(),
      builder: (ctx, snap) {
        final label = snap.data ?? 'Biometrics';
        final icon = label == 'Face Unlock'
            ? Icons.face_retouching_natural
            : Icons.fingerprint;
        if (isDesktop) {
          return GestureDetector(
            onTap: _biometricLoading ? null : _triggerBiometricLogin,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primaryColor.withValues(alpha: 0.4), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _biometricLoading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(icon, color: AppColors.primaryColor, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    _biometricLoading ? 'Authenticating…' : 'Sign in with $label',
                    style: TextStyle(
                      color: AppColors.primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return GestureDetector(
          onTap: _biometricLoading ? null : _triggerBiometricLogin,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.primaryColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _biometricLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(icon, color: AppColors.primaryColor, size: 22),
                const SizedBox(width: 8),
                Text(
                  _biometricLoading ? 'Authenticating…' : 'Sign in with $label',
                  style: TextStyle(color: AppColors.primaryColor, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _webSocialButton(String assetPath, String label, {VoidCallback? onTap, bool isLoading = false}) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF475569)))
            else
              Image.asset(assetPath, width: 24, height: 24),
            const SizedBox(width: 10),
            Text(
              isLoading ? 'Signing in...' : label,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _webAppleButton({VoidCallback? onTap, bool isLoading = false}) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            else
              const Icon(Icons.apple, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            Text(
              isLoading ? 'Signing in...' : 'Continue with Apple',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _socialButton(String assetPath, String label, {VoidCallback? onTap, bool isLoading = false}) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Image.asset(assetPath, width: 24, height: 24),
            const SizedBox(width: 8),
            Text(isLoading ? 'Signing in...' : label, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _mobileAppleButton({VoidCallback? onTap, bool isLoading = false}) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            else
              const Icon(Icons.apple, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(isLoading ? 'Signing in...' : 'Apple', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 18),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: "Gilroy-Medium",
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 14),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            fontFamily: "Gilroy-Medium",
          ),
        ),
      ],
    );
  }

  void _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);
    try {
      debugPrint("🔐 Starting login process...");

      final result = await _authService.login(
        email: usernameController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (result['requiresOtp'] == true) {
        final tempToken = result['tempToken']?.toString() ?? '';
        if (mounted) await _show2FADialog(tempToken: tempToken);
        if (mounted) setState(() => isLoading = false);
        return;
      }

      if (result['success']) {
        debugPrint("✅ Login successful, token saved");
        debugPrint("🔍 Fetching user profile...");

        final token = result['data']['token'];
        debugPrint("🔑 Token from login: ${token.substring(0, 20)}...");

        final profileResult = await _userService.getUserProfile(token: token);
        debugPrint("📥 Profile result: ${profileResult['success']}");

        if (profileResult['success'] && mounted) {
          debugPrint("✅ Profile fetched successfully");

          final userData = profileResult['user'];
          debugPrint("📋 User data: $userData");

          final user = app_user.User.fromJson(userData);
          debugPrint("👤 User object created: ${user.name}, ${user.email}, ${user.role}");

          await ref.read(authProvider.notifier).setUserToken(result['data']['token']);
          debugPrint("✅ Token set in provider");

          await ref.read(authProvider.notifier).setUser(user);
          debugPrint("✅ User set in provider");

          final currentRole = ref.read(authProvider).userRole;
          debugPrint("🔍 Current role in provider: '$currentRole'");
          debugPrint("✅ Logged in as: ${user.name} (${user.email}) - Role: ${user.role}");

          await _offerBiometricSetup(usernameController.text.trim());

          context.go('/dashboard');
        } else {
          debugPrint("❌ Failed to fetch profile: ${profileResult['message']}");
          _showError('Failed to load user profile: ${profileResult['message']}');
        }
      } else {
        _showError(result['message']);
      }

      // ── Signup branch COMMENTED OUT ─────────────────────────────────────
      // } else {
      //   final selectedRole = ref.read(authProvider).userRole;
      //   if (selectedRole.isEmpty) { _showError('Please select your role first'); ... }
      //   String backendRole = _mapRoleToBackend(selectedRole);
      //   final result = await _authService.register(name: ..., email: ..., ...);
      //   if (result['success']) { ... navigate to profile setup ... }
      //   else { _showError(result['message']); }
      // }

    } catch (e) {
      _showError('An error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ── _showApprovalDialog kept but only used if signup is re-enabled ───────
  // void _showApprovalDialog(String role) { ... }

  // ── _mapRoleToBackend kept but only used if signup is re-enabled ─────────
  // String _mapRoleToBackend(String frontendRole) { ... }

  void _showError(dynamic error) {
    if (!mounted) return;
    Utils.showErrorSnackBar(context, error);
  }

  Future<void> _show2FADialog({required String tempToken}) async {
    final otpController = TextEditingController();
    bool verifying = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF0036BC).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.security_rounded, color: Color(0xFF0036BC), size: 22)),
          const SizedBox(width: 10),
          const Text('Two-Factor Auth', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
        content: SizedBox(width: double.maxFinite, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFBFDBFE))),
            child: const Row(children: [
              Icon(Icons.phonelink_lock_rounded, color: Color(0xFF3B82F6), size: 20),
              SizedBox(width: 10),
              Expanded(child: Text('Open Google Authenticator and enter the 6-digit code for iCare.', style: TextStyle(fontSize: 13, color: Color(0xFF1E40AF), height: 1.4))),
            ]),
          ),
          const SizedBox(height: 16),
          const Text('Authenticator Code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
          const SizedBox(height: 8),
          TextField(
            controller: otpController, keyboardType: TextInputType.number, maxLength: 6, autofocus: true, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 8),
            decoration: InputDecoration(
              hintText: '000000', hintStyle: TextStyle(color: Colors.grey.shade300, letterSpacing: 8), counterText: '',
              filled: true, fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0036BC), width: 1.5)),
            ),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280)))),
          ElevatedButton(
            onPressed: verifying ? null : () async {
              if (otpController.text.length < 6) return;
              setModal(() => verifying = true);
              try {
                final result = await _authService.verify2FA(tempToken: tempToken, otp: otpController.text.trim());
                if (!ctx.mounted) return;
                if (result['success'] == true) {
                  final data = result['data'] as Map<String, dynamic>? ?? {};
                  final token = data['token']?.toString() ?? '';
                  if (token.isEmpty) { setModal(() => verifying = false); return; }
                  Navigator.pop(ctx);
                  final profileResult = await _userService.getUserProfile(token: token);
                  if (!mounted) return;
                  if (profileResult['success']) {
                    final user = app_user.User.fromJson(profileResult['user']);
                    await ref.read(authProvider.notifier).setUserToken(token);
                    await ref.read(authProvider.notifier).setUser(user);
                    if (mounted) context.go('/dashboard');
                  }
                } else {
                  setModal(() => verifying = false);
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(result['message']?.toString() ?? 'Invalid code'), backgroundColor: Colors.red));
                }
              } catch (e) {
                setModal(() => verifying = false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0036BC), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: verifying ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Verify'),
          ),
        ],
      )),
    );
  }
}