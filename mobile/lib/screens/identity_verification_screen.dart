import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../providers/phase15_providers.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';

class IdentityVerificationScreen extends ConsumerStatefulWidget {
  const IdentityVerificationScreen({super.key, this.phoneE164});

  final String? phoneE164;

  @override
  ConsumerState<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends ConsumerState<IdentityVerificationScreen> {
  static const _supportEmail = 'shipsterheadquarter@gmail.com';

  bool _loading = true;
  bool _submitting = false;
  bool _consent = false;
  String _status = 'NOT_STARTED';
  String _method = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadStatus);
  }

  Future<void> _loadStatus() async {
    try {
      final response = await ref.read(apiClientProvider).get('/identity/status');
      if (!mounted) return;
      setState(() {
        _status = response['verificationStatus']?.toString() ?? 'NOT_STARTED';
        _method = response['identityMethod']?.toString() ?? '';
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your verification status. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _requestManualReview() async {
    if (!_consent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please confirm that you want ShipdeHop to review your identity.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final response = await ref.read(apiClientProvider).post(
        '/identity/consent',
        {'consentVersion': '1.0'},
      );
      if (!mounted) return;
      setState(() {
        _status = response['status']?.toString() ?? 'PENDING_REVIEW';
      });
      ref.invalidate(ownProfileProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'Could not start manual identity review. Please try again or contact support.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _copySupportEmail() async {
    await Clipboard.setData(const ClipboardData(text: _supportEmail));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Support email copied.')),
    );
  }

  bool get _verified => _status == 'VERIFIED';
  bool get _pending =>
      _status == 'PENDING_REVIEW' || _status == 'IN_PROGRESS';
  bool get _restricted => _status == 'REJECTED' || _status == 'BLOCKED';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      appBar: AppBar(
        backgroundColor: ShipdeHopColors.background,
        title: const Text('Identity verification'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadStatus,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
                  children: [
                    _statusHero(),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _errorCard(),
                    ],
                    const SizedBox(height: 16),
                    if (_verified)
                      _verifiedContent()
                    else if (_pending)
                      _pendingContent()
                    else if (_restricted)
                      _restrictedContent()
                    else
                      _notStartedContent(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _statusHero() {
    final icon = _verified
        ? Icons.verified_user_rounded
        : _pending
            ? Icons.hourglass_top_rounded
            : _restricted
                ? Icons.report_gmailerrorred_rounded
                : Icons.shield_outlined;
    final color = _verified
        ? ShipdeHopColors.success
        : _pending
            ? ShipdeHopColors.warning
            : _restricted
                ? ShipdeHopColors.error
                : ShipdeHopColors.brandPrimary;
    final title = _verified
        ? 'Identity verified'
        : _pending
            ? 'Manual review requested'
            : _restricted
                ? 'Verification needs attention'
                : 'Verify before protected actions';
    final body = _verified
        ? 'Your ShipdeHop identity verification is active.'
        : _pending
            ? 'Your verification request is awaiting manual review. Protected actions remain unavailable until the server reports VERIFIED.'
            : _restricted
                ? 'Your previous identity review is not approved. Protected actions remain unavailable until ShipdeHop support resolves the review.'
                : 'Marketplace listings and protected journey actions require a verified identity.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ShipdeHopColors.borderLight),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 34),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: ShipdeHopTypography.displayMedium,
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: ShipdeHopTypography.bodyMedium,
          ),
          if (_verified && _method.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              'Method: ${_humanize(_method)}',
              style: ShipdeHopTypography.labelMedium.copyWith(
                color: ShipdeHopColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _notStartedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoCard(
          Icons.info_outline_rounded,
          'Online Aadhaar verification is not active',
          'ShipdeHop does not offer production Aadhaar OTP verification in the current release. Do not enter your Aadhaar number into this app.',
        ),
        const SizedBox(height: 10),
        _infoCard(
          Icons.fact_check_outlined,
          'Manual identity review',
          'You can request manual review. After requesting it, contact ShipdeHop support from your registered email so the team can complete the required identity checks.',
        ),
        const SizedBox(height: 14),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _consent,
          onChanged: (value) => setState(() => _consent = value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'I want to request ShipdeHop identity verification and consent to the manual review process.',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _submitting ? null : _requestManualReview,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.verified_user_outlined),
          label: Text(
            _submitting ? 'Requesting review…' : 'Request manual review',
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: ShipdeHopColors.brandPrimary,
          ),
        ),
        const SizedBox(height: 10),
        _supportButton(),
      ],
    );
  }

  Widget _pendingContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoCard(
          Icons.mark_email_read_outlined,
          'Next step: contact support',
          'Email $_supportEmail from the email you use with ShipdeHop. Include that you have requested identity review. Do not send passwords or OTPs.',
        ),
        const SizedBox(height: 12),
        _supportButton(),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _loadStatus,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh verification status'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  Widget _restrictedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoCard(
          Icons.lock_outline_rounded,
          'Protected actions are unavailable',
          'Do not retry with Aadhaar numbers, OTPs or biometric data in the app. Online Aadhaar verification is not active in this release.',
        ),
        const SizedBox(height: 10),
        _infoCard(
          Icons.support_agent_rounded,
          'Contact support for review',
          'Contact ShipdeHop support from your registered email and ask for the current review reason and next supported step.',
        ),
        const SizedBox(height: 12),
        _supportButton(),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _loadStatus,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh verification status'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  Widget _verifiedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoCard(
          Icons.check_circle_outline_rounded,
          'You can continue',
          'Your account has the verified identity status required for protected ShipdeHop actions.',
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to ShipdeHop'),
        ),
      ],
    );
  }

  Widget _supportButton() {
    return OutlinedButton.icon(
      onPressed: _copySupportEmail,
      icon: const Icon(Icons.email_outlined),
      label: const Text('Copy support email'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: ShipdeHopColors.errorBg,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: ShipdeHopColors.error),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _error!,
              style: ShipdeHopTypography.bodySmall.copyWith(
                color: ShipdeHopColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(IconData icon, String title, String body) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShipdeHopColors.borderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ShipdeHopColors.brandPrimary),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: ShipdeHopTypography.titleSmall),
                const SizedBox(height: 4),
                Text(body, style: ShipdeHopTypography.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _humanize(String value) {
    return value
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
