import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_textfield.dart';

/// Teacher application form. Submitting creates a "pending" account that
/// cannot log in until an admin approves it (see auth backend).
///
/// Resume/certificate upload isn't included yet - that needs a file
/// storage service (e.g. Cloudinary) to be set up first.
class TeacherApplyScreen extends StatefulWidget {
  const TeacherApplyScreen({super.key});

  @override
  State<TeacherApplyScreen> createState() => _TeacherApplyScreenState();
}

class _TeacherApplyScreenState extends State<TeacherApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _qualificationController = TextEditingController();
  final _experienceController = TextEditingController();
  final _subjectsController = TextEditingController();
  final _bioController = TextEditingController();

  bool _submitted = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _qualificationController.dispose();
    _experienceController.dispose();
    _subjectsController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      SnackbarUtils.showError(context, 'Passwords do not match');
      return;
    }

    final auth = context.read<AuthProvider>();
    final success = await auth.applyAsTeacher(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      phone: _phoneController.text.trim(),
      qualification: _qualificationController.text.trim(),
      experience: _experienceController.text.trim(),
      subjects: _subjectsController.text.trim(),
      bio: _bioController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      setState(() => _submitted = true);
    } else {
      SnackbarUtils.showError(context, auth.errorMessage ?? 'Application failed. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (_submitted) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.hourglass_top_rounded, size: 64, color: AppColors.primary),
                const SizedBox(height: 20),
                const Text('Application Submitted!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 10),
                const Text(
                  "Thanks for applying to teach. We're reviewing your application - you'll be able to log in once it's approved.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 28),
                CustomButton(label: 'Back to Login', onPressed: () => context.go('/login')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Become a Teacher')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Teacher Application', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text(
                  "Tell us about yourself. An admin will review your application before you can log in.",
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                CustomTextField(
                  label: 'Full Name',
                  hint: 'Your full name',
                  controller: _nameController,
                  prefixIcon: Icons.person_outline,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                CustomTextField(
                  label: 'Email',
                  hint: 'you@example.com',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.email_outlined,
                  validator: Validators.validateEmail,
                ),
                CustomTextField(
                  label: 'Password',
                  hint: 'Create a password',
                  controller: _passwordController,
                  isPassword: true,
                  prefixIcon: Icons.lock_outline,
                  validator: Validators.validatePassword,
                ),
                CustomTextField(
                  label: 'Confirm Password',
                  hint: 'Re-enter your password',
                  controller: _confirmPasswordController,
                  isPassword: true,
                  prefixIcon: Icons.lock_outline,
                  validator: (value) {
                      final formatError = Validators.validatePassword(value);
                      if (formatError != null) return formatError;
                      if (value != _passwordController.text) return 'Passwords do not match';
                      return null;
                    },
                ),
                CustomTextField(
                  label: 'Phone Number',
                  hint: 'Your phone number',
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  prefixIcon: Icons.phone_outlined,
                ),
                CustomTextField(
                  label: 'Qualification',
                  hint: 'e.g. M.Sc. Mathematics',
                  controller: _qualificationController,
                  prefixIcon: Icons.school_outlined,
                ),
                CustomTextField(
                  label: 'Experience',
                  hint: 'e.g. 5 years teaching high school',
                  controller: _experienceController,
                  prefixIcon: Icons.work_outline,
                ),
                CustomTextField(
                  label: 'Subjects You Teach',
                  hint: 'e.g. Mathematics, Physics',
                  controller: _subjectsController,
                  prefixIcon: Icons.menu_book_outlined,
                ),
                CustomTextField(
                  label: 'Bio',
                  hint: 'A short introduction about yourself',
                  controller: _bioController,
                  prefixIcon: Icons.info_outline,
                ),
                const SizedBox(height: 8),
                CustomButton(
                  label: 'Submit Application',
                  isLoading: auth.isLoading,
                  onPressed: _handleSubmit,
                ),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: () => context.go('/login'),
                    child: const Text('Back to Login', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
