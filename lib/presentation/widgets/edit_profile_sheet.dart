import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/identity_state.dart';
import '../theme/signal_theme.dart';

/// Modal bottom sheet for editing the user's display name and optional phone number.
class EditProfileSheet extends ConsumerStatefulWidget {
  const EditProfileSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SignalTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const EditProfileSheet(),
    );
  }

  @override
  ConsumerState<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<EditProfileSheet> {
  late TextEditingController _nicknameCtrl;
  late TextEditingController _phoneCtrl;
  String? _nicknameError;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    final identity = ref.read(identityProvider);
    _nicknameCtrl = TextEditingController(text: identity.nickname);
    _phoneCtrl = TextEditingController(text: identity.phoneNumber ?? '');
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  String? _validateNickname(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return 'Nickname cannot be empty';
    if (clean.length < 2) return 'At least 2 characters required';
    if (clean.length > 20) return 'Max 20 characters';
    if (!RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(clean)) {
      return 'Only letters, numbers, _ and - allowed';
    }
    return null;
  }

  String? _validatePhone(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return null; // optional
    if (!RegExp(r'^[\d\s\+\-\(\)]{6,20}$').hasMatch(clean)) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  void _save() async {
    final nicknameErr = _validateNickname(_nicknameCtrl.text);
    final phoneErr = _validatePhone(_phoneCtrl.text);
    setState(() {
      _nicknameError = nicknameErr;
      _phoneError = phoneErr;
    });
    if (nicknameErr != null || phoneErr != null) return;

    final notifier = ref.read(identityProvider.notifier);
    final phone = _phoneCtrl.text.trim();
    await notifier.updateProfile(
      nickname: _nicknameCtrl.text.trim(),
      phoneNumber: phone.isEmpty ? null : phone,
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: SignalTheme.signalBlueDark,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: SignalTheme.darkBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const Text(
            'Edit Profile',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: SignalTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 20),

          // Nickname field
          const Text(
            'Display Name',
            style: TextStyle(fontSize: 12, color: SignalTheme.textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _nicknameCtrl,
            autofocus: true,
            maxLength: 20,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'Your name',
              errorText: _nicknameError,
              counterText: '',
              prefixIcon: const Icon(Icons.badge_outlined, color: SignalTheme.textSecondary, size: 20),
            ),
            onChanged: (_) {
              if (_nicknameError != null) setState(() => _nicknameError = null);
            },
          ),
          const SizedBox(height: 16),

          // Phone number field
          const Text(
            'Phone Number  (optional — shared with nearby peers)',
            style: TextStyle(fontSize: 12, color: SignalTheme.textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: '+91 98765 43210',
              errorText: _phoneError,
              prefixIcon: const Icon(Icons.phone_outlined, color: SignalTheme.textSecondary, size: 20),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _phoneCtrl,
                builder: (_, val, __) => val.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: SignalTheme.textSecondary),
                        onPressed: () {
                          _phoneCtrl.clear();
                          setState(() => _phoneError = null);
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            onChanged: (_) {
              if (_phoneError != null) setState(() => _phoneError = null);
            },
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SignalTheme.textSecondary,
                    side: const BorderSide(color: SignalTheme.darkBorder),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SignalTheme.signalBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
