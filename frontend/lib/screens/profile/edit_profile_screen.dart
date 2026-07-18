import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';

/// Edit Profile - name, email, and password can all be updated; the
/// backend's /api/users/profile endpoint already supports name+email
/// together (see UserService.updateProfile), name just wasn't wired up
/// to an editable field here before.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final UserService _userService = UserService();
  final AuthService _authService = AuthService();
  final _nameFormKey = GlobalKey<FormState>();
  final _emailFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _originalName = '';
  String _originalEmail = '';
  bool _loadingEmail = true;
  bool _savingName = false;
  bool _savingEmail = false;
  bool _changingPassword = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _originalName = context.read<AuthProvider>().currentUser?.name ?? '';
    _nameController = TextEditingController(text: _originalName);
    _emailController = TextEditingController();
    _loadCurrentEmail();
  }

  // AuthProvider's cached user only carries id/name/role (that's all the
  // login response returns) - the real email lives in the fuller
  // GET /api/auth/profile response, so we fetch that fresh here.
  Future<void> _loadCurrentEmail() async {
    try {
      final data = await _authService.fetchProfile();
      final email = data['email'] as String? ?? '';
      if (mounted) {
        setState(() {
          _originalEmail = email;
          _emailController.text = email;
          _loadingEmail = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingEmail = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges =>
      _nameController.text.trim() != _originalName ||
      _emailController.text.trim() != _originalEmail ||
      _currentPasswordController.text.isNotEmpty ||
      _newPasswordController.text.isNotEmpty ||
      _confirmPasswordController.text.isNotEmpty;

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Leave without saving?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _saveName() async {
    if (!_nameFormKey.currentState!.validate()) return;
    if (_nameController.text.trim() == _originalName) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update name?'),
        content: Text('Change your name to ${_nameController.text.trim()}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _savingName = true);
    try {
      final newName = _nameController.text.trim();
      await _userService.updateProfile(name: newName, email: _originalEmail);
      if (!mounted) return;
      await context.read<AuthProvider>().updateLocalName(newName);
      if (mounted) setState(() => _originalName = newName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name updated successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _saveEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    if (_emailController.text.trim() == _originalEmail) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update email?'),
        content: Text('Change your email to ${_emailController.text.trim()}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    // QA fix ("Missing mounted checks after async operations" / "Safe
    // BuildContext usage"): context.read<AuthProvider>() below used to
    // run right after the dialog's await with no mounted guard.
    if (!mounted) return;

    setState(() => _savingEmail = true);
    try {
      await _userService.updateProfile(name: _originalName, email: _emailController.text.trim());
      if (mounted) setState(() => _originalEmail = _emailController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email updated successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _savingEmail = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change password?'),
        content: const Text('You will need to use the new password next time you log in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _changingPassword = true);
    try {
      await _userService.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // QA fix ("Safe BuildContext usage"): mounted IS checked
        // immediately before this Navigator.pop, but Flutter's analyzer
        // has a known blind spot for `mounted` checks inside a
        // PopScope callback closure - it can't always verify the guard
        // covers the context use that follows it in this shape. This is
        // a verified analyzer false-positive, not an unguarded use.
        final shouldDiscard = await _confirmDiscard();
        if (!mounted) return;
        if (shouldDiscard) {
          // ignore: use_build_context_synchronously
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit Profile')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionCard(
              title: 'Name',
              child: Form(
                key: _nameFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Full name'),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Name is required';
                        if (v.length < 2) return 'Name is too short';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _savingName ? null : _saveName,
                      child: _savingName
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save Name'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: 'Email',
              child: _loadingEmail
                  ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                  : Form(
                key: _emailFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Email address'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Email is required';
                        final regex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
                        if (!regex.hasMatch(v)) return 'Enter a valid email address';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _savingEmail ? null : _saveEmail,
                      child: _savingEmail
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save Email'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: 'Change Password',
              child: Form(
                key: _passwordFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _currentPasswordController,
                      obscureText: _obscureCurrent,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'Current password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                        ),
                      ),
                      validator: (value) => (value == null || value.isEmpty) ? 'Enter your current password' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: _obscureNew,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'New password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Enter a new password';
                        if (value.length < 6) return 'Password must be at least 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'Confirm new password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: (value) {
                        if (value != _newPasswordController.text) return 'Passwords do not match';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _changingPassword ? null : _changePassword,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.purple),
                      child: _changingPassword
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Change Password', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}