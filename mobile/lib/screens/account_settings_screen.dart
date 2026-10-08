import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/profile_preferences.dart';
import '../providers/app_providers.dart';
import '../providers/notification_provider.dart';
import '../providers/phase15_providers.dart';
import '../theme/shipdehop_colors.dart';
import '../widgets/profile/profile_components.dart';

class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _seeded = false;
  bool _savingProfile = false;
  bool _loadingPrefs = true;
  bool _journeyUpdates = true;
  bool _messageAlerts = true;
  bool _paymentAlerts = true;

  ProfilePreferencesStore get _store => ProfilePreferencesStore(ref.read(currentUserIdProvider) ?? 'anonymous');

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadPrefs);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await _store.loadAccountPreferences();
    if (!mounted) return;
    setState(() {
      _journeyUpdates = prefs.journeyUpdates;
      _messageAlerts = prefs.messageAlerts;
      _paymentAlerts = prefs.paymentAlerts;
      _loadingPrefs = false;
    });
  }

  Future<void> _saveProfile() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your name.')));
      return;
    }
    setState(() => _savingProfile = true);
    try {
      await ref.read(apiClientProvider).patch('/profile/me', {'fullName': name, 'phone': _phone.text.trim()});
      ref.invalidate(ownProfileProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated.')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update profile. Try again.')));
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _saveNotifications() async {
    await _store.saveAccountPreferences(AccountPreferences(
      journeyUpdates: _journeyUpdates,
      messageAlerts: _messageAlerts,
      paymentAlerts: _paymentAlerts,
    ));
    ref.invalidate(notificationsProvider);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notification preferences saved.')));
  }

  Future<void> _clearLocalData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear saved preferences?'),
        content: const Text('This removes saved places and device-specific Profile preferences for this account. It does not delete your ShipdeHop account or transaction history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirm != true) return;
    await _store.clearLocalProfileData();
    ref.invalidate(notificationsProvider);
    if (!mounted) return;
    setState(() {
      _journeyUpdates = true;
      _messageAlerts = true;
      _paymentAlerts = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Local Profile preferences cleared.')));
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete ShipdeHop Account?'),
        content: const Text(
          'This action deactivates your account and purges your personal profile data. '
          'Transaction records required by regulatory compliance will be retained securely.\n\n'
          'Are you sure you want to proceed?'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: ShipdeHopColors.error),
            child: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      await ref.read(apiClientProvider).post('/profile/delete-account', {});
      await ref.read(sessionManagerProvider.notifier).signOut();
      try {
        await ref.read(supabaseProvider).auth.signOut();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your account deletion request has been processed.'))
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account deletion request failed. Please try again.'))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(ownProfileProvider);
    final profile = profileAsync.value;
    if (!_seeded && profile != null) {
      _name.text = profile['fullName']?.toString() ?? '';
      _phone.text = profile['phone']?.toString() ?? '';
      _seeded = true;
    }
    final email = profile?['email']?.toString() ?? ref.watch(authUserProvider).value?.email ?? '';

    return ProfileDetailScaffold(
      title: 'Settings',
      children: [
        const ProfileSectionTitle('Account'),
        const SizedBox(height: 8),
        ProfileControlCard(children: [
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded))),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined), hintText: 'Optional')),
          const SizedBox(height: 12),
          TextFormField(initialValue: email, enabled: false, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined))),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: profile == null || _savingProfile ? null : _saveProfile,
            icon: _savingProfile ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
            label: Text(_savingProfile ? 'Saving…' : 'Save account details'),
          ),
        ]),
        const SizedBox(height: 20),
        const ProfileSectionTitle('Notification Center'),
        const SizedBox(height: 8),
        if (_loadingPrefs)
          const ProfileLoadingCard(label: 'Loading notification preferences…')
        else
          ProfileControlCard(children: [
            SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _journeyUpdates, onChanged: (v) => setState(() => _journeyUpdates = v), title: const Text('Journey updates'), subtitle: const Text('Pickup, arrival, handoff and delivery progress.')),
            const Divider(height: 1),
            SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _messageAlerts, onChanged: (v) => setState(() => _messageAlerts = v), title: const Text('Messages'), subtitle: const Text('New message and chat activity.')),
            const Divider(height: 1),
            SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _paymentAlerts, onChanged: (v) => setState(() => _paymentAlerts = v), title: const Text('Payments'), subtitle: const Text('Payment protected, released, refunded or disputed.')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _saveNotifications, icon: const Icon(Icons.notifications_active_outlined), label: const Text('Save notification preferences')),
          ]),
        const SizedBox(height: 20),
        const ProfileSectionTitle('Account actions'),
        const SizedBox(height: 8),
        ProfileControlCard(children: [
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.delete_sweep_outlined), title: const Text('Clear local Profile preferences'), subtitle: const Text('Saved places and preferences on this device'), onTap: _clearLocalData),
          const Divider(height: 1),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.person_remove_outlined, color: ShipdeHopColors.error), title: const Text('Delete account & data', style: TextStyle(color: ShipdeHopColors.error, fontWeight: FontWeight.w600)), subtitle: const Text('Request account deactivation and PII erasure'), onTap: _deleteAccount),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout_rounded, color: ShipdeHopColors.error),
            title: const Text('Sign out', style: TextStyle(color: ShipdeHopColors.error, fontWeight: FontWeight.w700)),
            onTap: () async {
              await ref.read(supabaseProvider).auth.signOut();
              if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ]),
      ],
    );
  }
}
