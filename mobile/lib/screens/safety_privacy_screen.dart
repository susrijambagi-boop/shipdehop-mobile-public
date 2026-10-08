import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/profile_preferences.dart';
import '../providers/app_providers.dart';
import '../providers/phase15_providers.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import '../widgets/profile/profile_components.dart';

class SafetyPrivacyScreen extends ConsumerStatefulWidget {
  const SafetyPrivacyScreen({super.key});

  @override
  ConsumerState<SafetyPrivacyScreen> createState() => _SafetyPrivacyScreenState();
}

class _SafetyPrivacyScreenState extends ConsumerState<SafetyPrivacyScreen> {
  final _contactName = TextEditingController();
  final _contactPhone = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _shareLive = true;
  bool _checkIns = true;

  ProfilePreferencesStore get _store => ProfilePreferencesStore(ref.read(currentUserIdProvider) ?? 'anonymous');

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    _contactName.dispose();
    _contactPhone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final value = await _store.loadSafetyPreferences();
    if (!mounted) return;
    _contactName.text = value.emergencyName;
    _contactPhone.text = value.emergencyPhone;
    setState(() {
      _shareLive = value.shareLiveLocation;
      _checkIns = value.safetyCheckIns;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final name = _contactName.text.trim();
    final phone = _contactPhone.text.trim();
    if ((name.isEmpty) != (phone.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter both emergency contact name and phone, or leave both empty.')));
      return;
    }
    setState(() => _saving = true);
    await _store.saveSafetyPreferences(SafetyPreferences(
      emergencyName: name,
      emergencyPhone: phone,
      shareLiveLocation: _shareLive,
      safetyCheckIns: _checkIns,
    ));
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Safety preferences saved.')));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(ownProfileProvider).value;
    final tier = profile?['ekycTier']?.toString() ?? 'UNVERIFIED';
    final verified = tier.startsWith('TIER_') && tier != 'TIER_0';
    final trust = ((profile?['trustScore'] as num?)?.toDouble() ?? 0).round();

    return ProfileDetailScaffold(
      title: 'Safety & privacy',
      children: [
        const ProfileSectionTitle('Your safety status'),
        const SizedBox(height: 8),
        ProfileControlCard(children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(verified ? Icons.verified_user_rounded : Icons.shield_outlined, color: verified ? ShipdeHopColors.success : ShipdeHopColors.warning),
            title: Text(verified ? 'Identity verification active' : 'Identity verification incomplete'),
            subtitle: Text('Verification level: ${profileHumanize(tier)}'),
          ),
          const Divider(height: 1),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.shield_moon_outlined), title: Text('Trust Score: $trust / 100'), subtitle: const Text('Trust is based on transaction and verification signals. XP and Hop Club progress stay separate.')),
        ]),
        const SizedBox(height: 20),
        const ProfileSectionTitle('Emergency contact'),
        const SizedBox(height: 8),
        if (_loading)
          const ProfileLoadingCard(label: 'Loading safety preferences…')
        else ...[
          ProfileControlCard(children: [
            TextField(controller: _contactName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Contact name', prefixIcon: Icon(Icons.person_outline_rounded))),
            const SizedBox(height: 12),
            TextField(controller: _contactPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone_outlined))),
            const SizedBox(height: 8),
            Text('Keep this as someone you would want contacted if you need help during a journey.', style: ShipdeHopTypography.bodySmall),
          ]),
          const SizedBox(height: 20),
          const ProfileSectionTitle('Journey privacy'),
          const SizedBox(height: 8),
          ProfileControlCard(children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _shareLive,
              onChanged: (value) => setState(() => _shareLive = value),
              title: const Text('Live location during active journeys'),
              subtitle: const Text('Allow operational location sharing while a matched journey is active. Exact location should not be exposed during discovery.'),
            ),
            const Divider(height: 1),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _checkIns,
              onChanged: (value) => setState(() => _checkIns = value),
              title: const Text('Safety check-ins'),
              subtitle: const Text('Keep safety prompts enabled around pickup, handoff and arrival moments.'),
            ),
          ]),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.shield_outlined),
            label: Text(_saving ? 'Saving…' : 'Save safety preferences'),
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          ),
          const SizedBox(height: 8),
          Text('These preferences are stored for this signed-in account on this device. They do not override emergency services or device-level location permissions.', style: ShipdeHopTypography.bodySmall),
        ],
        const SizedBox(height: 20),
        const ProfileSectionTitle('What ShipdeHop keeps private'),
        const SizedBox(height: 8),
        const ProfileInfoCard(
          icon: Icons.visibility_off_outlined,
          title: 'Private account details stay private',
          body: 'Email, phone number and payment account details are not part of your public counterparty profile.',
        ),
        const SizedBox(height: 10),
        const ProfileInfoCard(
          icon: Icons.location_on_outlined,
          title: 'Location is stage-appropriate',
          body: 'Discovery should use only the location precision needed to match. Exact operational location belongs to an active journey when required for pickup, tracking or handoff.',
        ),
      ],
    );
  }
}
