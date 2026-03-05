import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _ageController = TextEditingController();
  final _heightController = TextEditingController(); // in cm
  final _weightController = TextEditingController(); // in kg

  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _ageFocus = FocusNode();
  final _heightFocus = FocusNode();
  final _weightFocus = FocusNode();

  String? _selectedGender;
  bool _isLoading = false;
  bool _obscurePassword = true; // true = hidden, false = visible

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();

    _emailFocus.dispose();
    _passwordFocus.dispose();
    _ageFocus.dispose();
    _heightFocus.dispose();
    _weightFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final auth = Provider.of<AuthService>(context, listen: false);

    final errorMessage = await auth.register(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      age: int.tryParse(_ageController.text.trim()) ?? 0,
      gender: _selectedGender ?? '',
      heightCm: double.tryParse(_heightController.text.trim()) ?? 0.0,
      weightKg: double.tryParse(_weightController.text.trim()) ?? 0.0,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(); // Back to login
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.height < 700;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D47A1),
              Color(0xFF1976D2),
              Color(0xFF42A5F5),
              Color(0xFFBBDEFB),
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AnimationLimiter(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: AnimationConfiguration.toStaggeredList(
                      duration: const Duration(milliseconds: 600),
                      childAnimationBuilder: (widget) => SlideAnimation(
                        verticalOffset: 40.0,
                        child: FadeInAnimation(child: widget),
                      ),
                      children: [
                        Image.asset(
                          'assets/icons/app_icon.png',
                          height: isSmallScreen ? 160 : 200,
                          fit: BoxFit.contain,
                        ),
                        SizedBox(height: isSmallScreen ? 8 : 12),
                        Text(
                          'Smart Helmet',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: isSmallScreen ? 26 : 32,
                                letterSpacing: 1.2,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: isSmallScreen ? 6 : 8),
                        Text(
                          'Create your account',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: isSmallScreen ? 15 : 17,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: isSmallScreen ? 28 : 40),
                        SlideAnimation(
                          delay: const Duration(milliseconds: 150),
                          child: FadeInAnimation(
                            child: Container(
                              padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.12),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  children: [
                                    // Email
                                    TextFormField(
                                      controller: _emailController,
                                      focusNode: _emailFocus,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [
                                        AutofillHints.newUsername,
                                        AutofillHints.email
                                      ],
                                      decoration: _inputDecoration(
                                        'Email',
                                        'you@example.com',
                                        Icons.email_outlined,
                                      ),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) {
                                          return 'Please enter your email';
                                        }
                                        if (!RegExp(
                                                r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                            .hasMatch(v.trim())) {
                                          return 'Enter a valid email';
                                        }
                                        return null;
                                      },
                                      onFieldSubmitted: (_) =>
                                          _ageFocus.requestFocus(),
                                    ),
                                    SizedBox(height: isSmallScreen ? 14 : 18),

                                    // Age
                                    TextFormField(
                                      controller: _ageController,
                                      focusNode: _ageFocus,
                                      keyboardType: TextInputType.number,
                                      textInputAction: TextInputAction.next,
                                      decoration: _inputDecoration(
                                        'Age',
                                        '25',
                                        Icons.calendar_today_outlined,
                                      ),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty)
                                          return 'Required';
                                        final age = int.tryParse(v.trim());
                                        if (age == null ||
                                            age < 10 ||
                                            age > 120) {
                                          return 'Enter valid age (10-120)';
                                        }
                                        return null;
                                      },
                                      onFieldSubmitted: (_) =>
                                          _heightFocus.requestFocus(),
                                    ),
                                    SizedBox(height: isSmallScreen ? 14 : 18),

                                    // Gender
                                    DropdownButtonFormField<String>(
                                      value: _selectedGender,
                                      decoration: _inputDecoration(
                                        'Gender',
                                        'Select gender',
                                        Icons.wc_outlined,
                                      ).copyWith(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          vertical: 16,
                                          horizontal: 16,
                                        ),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'Male', child: Text('Male')),
                                        DropdownMenuItem(
                                            value: 'Female',
                                            child: Text('Female')),
                                        DropdownMenuItem(
                                            value: 'Other',
                                            child: Text('Other')),
                                      ],
                                      onChanged: _isLoading
                                          ? null
                                          : (val) => setState(
                                              () => _selectedGender = val),
                                      validator: (v) => v == null
                                          ? 'Please select gender'
                                          : null,
                                    ),
                                    SizedBox(height: isSmallScreen ? 14 : 18),

                                    // Height
                                    TextFormField(
                                      controller: _heightController,
                                      focusNode: _heightFocus,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      textInputAction: TextInputAction.next,
                                      decoration: _inputDecoration(
                                        'Height (cm)',
                                        '175.5',
                                        Icons.straighten_outlined,
                                      ),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty)
                                          return 'Required';
                                        final h = double.tryParse(v.trim());
                                        if (h == null || h < 100 || h > 250) {
                                          return 'Enter valid height (100-250 cm)';
                                        }
                                        return null;
                                      },
                                      onFieldSubmitted: (_) =>
                                          _weightFocus.requestFocus(),
                                    ),
                                    SizedBox(height: isSmallScreen ? 14 : 18),

                                    TextFormField(
                                      controller: _weightController,
                                      focusNode: _weightFocus,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      textInputAction: TextInputAction.done,
                                      decoration: _inputDecoration(
                                        'Weight (kg)',
                                        '70.0',
                                        Icons.monitor_weight_outlined,
                                      ),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty)
                                          return 'Required';
                                        final w = double.tryParse(v.trim());
                                        if (w == null || w < 30 || w > 300)
                                          return 'Enter valid weight (30-300 kg)';
                                        return null;
                                      },
                                      onFieldSubmitted: (_) => _submit(),
                                    ),

                                    SizedBox(height: isSmallScreen ? 24 : 32),

                                    // Password ── FIXED VISIBILITY TOGGLE ────────
                                    TextFormField(
                                      controller: _passwordController,
                                      focusNode: _passwordFocus,
                                      obscureText:
                                          _obscurePassword, // ← this controls visibility
                                      textInputAction: TextInputAction.done,
                                      autofillHints: const [
                                        AutofillHints.newPassword
                                      ],
                                      decoration: _inputDecoration(
                                        'Password',
                                        '••••••••',
                                        Icons.lock_outline,
                                      ).copyWith(
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                            color: Colors.grey.shade700,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _obscurePassword =
                                                  !_obscurePassword;
                                            });
                                          },
                                          tooltip: _obscurePassword
                                              ? 'Show password'
                                              : 'Hide password',
                                        ),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please enter a password';
                                        }
                                        if (value.length < 6) {
                                          return 'Password must be at least 6 characters';
                                        }
                                        return null;
                                      },
                                      onFieldSubmitted: (_) => _submit(),
                                    ),

                                    SizedBox(height: isSmallScreen ? 24 : 32),

                                    // Create Account Button
                                    ScaleAnimation(
                                      child: SizedBox(
                                        width: double.infinity,
                                        height: 54,
                                        child: ElevatedButton(
                                          onPressed:
                                              _isLoading ? null : _submit,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF1976D2),
                                            foregroundColor: Colors.white,
                                            elevation: 4,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                          child: _isLoading
                                              ? const SizedBox(
                                                  height: 24,
                                                  width: 24,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 3,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : const Text(
                                                  'Create Account',
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),

                                    SizedBox(height: isSmallScreen ? 20 : 24),

                                    TextButton(
                                      onPressed: _isLoading
                                          ? null
                                          : () => Navigator.of(context).pop(),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: RichText(
                                        text: const TextSpan(
                                          children: [
                                            TextSpan(
                                              text: 'Already have an account? ',
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            TextSpan(
                                              text: 'Sign in',
                                              style: TextStyle(
                                                color: Color(0xFF1976D2),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 20 : 32),
                        Text(
                          '© 2026 Smart Helmet. All rights reserved.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.8),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
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

  InputDecoration _inputDecoration(String label, String hint, IconData icon) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    );
  }
}
