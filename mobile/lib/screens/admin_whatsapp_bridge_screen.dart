import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

class AdminWhatsAppBridgeScreen extends ConsumerStatefulWidget {
  const AdminWhatsAppBridgeScreen({super.key});

  @override
  ConsumerState<AdminWhatsAppBridgeScreen> createState() => _AdminWhatsAppBridgeScreenState();
}

class _AdminWhatsAppBridgeScreenState extends ConsumerState<AdminWhatsAppBridgeScreen> {
  final phoneController = TextEditingController(text: '91');
  bool loading = true;
  bool pairing = false;
  Map<String, dynamic>? status;
  String? error;
  String? pairingCode;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final result = await ref.read(apiClientProvider).get('/admin/whatsapp/status');
      if (!mounted) return;
      setState(() {
        status = (result as Map).cast<String, dynamic>();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Could not load WhatsApp OTP sender status.';
        loading = false;
      });
    }
  }

  Future<void> _pair() async {
    final phone = phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (phone.length < 10) {
      _snack('Enter the WhatsApp sender number with country code.');
      return;
    }

    setState(() {
      pairing = true;
      pairingCode = null;
      error = null;
    });

    try {
      final result = await ref.read(apiClientProvider).post(
        '/admin/whatsapp/pairing-code',
        {'phoneNumber': phone},
      );
      if (!mounted) return;
      setState(() {
        pairingCode = result['pairingCode']?.toString();
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => error = 'Could not generate a pairing code. Retry once.');
    } finally {
      if (mounted) setState(() => pairing = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final connected = status?['connected'] == true;
    final paired = status?['paired'] == true;
    final statusLabel = status?['status']?.toString() ?? 'UNKNOWN';
    final lastError = status?['lastError']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp OTP sender'),
        actions: [
          IconButton(
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(
                    connected ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                    color: connected ? Colors.green : Colors.orange,
                    size: 34,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          connected ? 'OTP sender connected' : 'OTP sender not connected',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text('Status: $statusLabel'),
                        Text('Paired: ${paired ? 'Yes' : 'No'}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (lastError != null && lastError.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(lastError),
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (!paired) ...[
            const Text(
              'Link the ShipdeHop WhatsApp sender',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use a dedicated WhatsApp number. Enter it with country code, then link ShipdeHop as a companion device.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Sender WhatsApp number',
                hintText: '919876543210',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: pairing ? null : _pair,
              child: Text(pairing ? 'Generating…' : 'Generate pairing code'),
            ),
          ],
          if (pairingCode != null && pairingCode!.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Pairing code',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SelectableText(
              pairingCode!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'On the sender phone: WhatsApp → Settings → Linked Devices → Link a Device → Link with phone number instead → enter this code.',
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Reliability',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'ShipdeHop persists the linked-device credentials in Supabase, reconnects automatically after backend restarts, and retries each OTP send up to three times before returning an error.',
          ),
        ],
      ),
    );
  }
}
