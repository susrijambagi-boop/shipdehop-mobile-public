import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/app_config.dart';
import '../providers/app_providers.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import '../widgets/hopshield_banner.dart';
import '../widgets/mascot/mascot_empty_state.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.threadId,
    required this.orderId,
    this.counterpartyName = 'Chat Partner',
    this.contextTitle = 'ShipdeHop Transaction',
  });

  final String threadId;
  final String orderId;
  final String counterpartyName;
  final String contextTitle;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final message = TextEditingController();
  final otpInput = TextEditingController();
  Map<String, dynamic>? handoff;
  Map<String, dynamic>? order;
  bool sending = false;
  bool _showSafetyBanner = true;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  @override
  void dispose() {
    message.dispose();
    otpInput.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    if (!AppConfig.isConfigured || widget.orderId.isEmpty) return;
    try {
      final row = await ref
          .read(supabaseProvider)
          .from('escrow_orders')
          .select('id,buyer_id,provider_id,escrow_status,fulfillment_status')
          .eq('id', widget.orderId)
          .maybeSingle();
      if (mounted) setState(() => order = row);
    } catch (_) {}
  }

  bool get isBuyer => order?['buyer_id'] == ref.read(currentUserIdProvider);
  bool get isProvider => order?['provider_id'] == ref.read(currentUserIdProvider);

  Future<void> send() async {
    if (message.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      final result = await ref.read(apiClientProvider).post('/chat/${widget.threadId}/messages', {'text': message.text.trim()});
      message.clear();
      final shield = result['hopShield'] as Map<String, dynamic>?;
      if (mounted && shield?['action'] == 'WARN') {
        ScaffoldMessenger.of(context).showMaterialBanner(
          hopShieldBanner(
            context,
            message: (shield?['reasons'] as List?)?.join(' • ') ?? 'HopShield detected suspicious payment behavior.',
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showMaterialBanner(hopShieldBanner(context, message: '$e', blocked: true));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> reveal() async {
    try {
      final result = await ref.read(apiClientProvider).post('/orders/${widget.orderId}/handoff-secret', {});
      if (mounted) setState(() => handoff = result);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> verifyOtp() async {
    try {
      await ref.read(apiClientProvider).post('/orders/${widget.orderId}/verify-otp', {'otp': otpInput.text});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Handoff verified. Payout released.')));
      await _loadOrder();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> scanQr() async {
    final payload = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _QrScannerScreen()));
    if (payload == null) return;
    try {
      await ref.read(apiClientProvider).post('/orders/${widget.orderId}/verify-qr', {'qrPayload': payload});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('QR verified. Payout released.')));
      await _loadOrder();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> fundOrder() async {
    try {
      final reservation = await ref.read(apiClientProvider).post('/orders/${widget.orderId}/fund', {});
      await ref.read(paymentCoordinatorProvider).completeReservation(reservation);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment submitted via HopPay escrow.')));
      await _loadOrder();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> markInTransit() async {
    try {
      await ref.read(apiClientProvider).post('/orders/${widget.orderId}/in-transit', {});
      await _loadOrder();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = widget.threadId.isNotEmpty
        ? ref.watch(supabaseProvider).from('chat_messages').stream(primaryKey: ['id']).eq('thread_id', widget.threadId).order('created_at')
        : null;

    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      appBar: AppBar(
        backgroundColor: ShipdeHopColors.surfaceCard,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.counterpartyName,
              style: ShipdeHopTypography.titleSmall.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              widget.contextTitle,
              style: ShipdeHopTypography.bodySmall.copyWith(fontSize: 11, color: ShipdeHopColors.brandPrimary),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Dismissible Safety Strip
          if (_showSafetyBanner)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: ShipdeHopColors.surfaceSubtle,
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 16, color: ShipdeHopColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'HopShield active. Keep all communications & payments inside HopPay.',
                      style: ShipdeHopTypography.bodySmall.copyWith(fontSize: 11),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _showSafetyBanner = false),
                    child: const Icon(Icons.close_rounded, size: 16, color: ShipdeHopColors.textMuted),
                  ),
                ],
              ),
            ),

          // Transaction Context Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: ShipdeHopColors.surfaceCard,
            child: Row(
              children: [
                const Icon(Icons.shopping_bag_outlined, color: ShipdeHopColors.brandPrimary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.contextTitle,
                    style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('View Order', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ShipdeHopColors.brandPrimary)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: ShipdeHopColors.borderSubtle),

          // Messages View
          Expanded(
            child: stream == null
                ? MascotEmptyState.noMessages()
                : StreamBuilder<List<Map<String, dynamic>>>(
                    stream: stream,
                    builder: (context, snap) {
                      final rows = snap.data ?? [];
                      if (rows.isEmpty) {
                        return MascotEmptyState.noMessages();
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final m = rows[i];
                          final mine = m['sender_id'] == ref.read(currentUserIdProvider);
                          final body = m['body']?.toString() ?? '';

                          return Align(
                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: mine ? ShipdeHopColors.brandPrimary : ShipdeHopColors.surfaceCard,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(mine ? 16 : 4),
                                  bottomRight: Radius.circular(mine ? 4 : 16),
                                ),
                                boxShadow: const [
                                  BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 4, offset: Offset(0, 1)),
                                ],
                              ),
                              child: Text(
                                body,
                                style: TextStyle(
                                  color: mine ? Colors.white : ShipdeHopColors.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),

          // Actions / OTP / QR Area
          if (isBuyer && order?['escrow_status'] == 'PENDING')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: ShipdeHopColors.brandPrimary, foregroundColor: Colors.white),
                onPressed: fundOrder,
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text('Fund order with HopPay Escrow'),
              ),
            ),

          if (isProvider && order?['escrow_status'] == 'LOCKED' && ['CREATED', 'READY'].contains(order?['fulfillment_status']))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: ShipdeHopColors.success, foregroundColor: Colors.white),
                onPressed: markInTransit,
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                label: const Text('Begin fulfillment / In transit'),
              ),
            ),

          // Safe Input Bar
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: ShipdeHopColors.surfaceCard,
                boxShadow: [
                  BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 6, offset: Offset(0, -2)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: message,
                      decoration: InputDecoration(
                        hintText: 'Type a message safely in-app...',
                        hintStyle: const TextStyle(fontSize: 13, color: ShipdeHopColors.textMuted),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        filled: true,
                        fillColor: ShipdeHopColors.surfaceSubtle,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: sending ? null : send,
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: ShipdeHopColors.brandPrimary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  bool done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan handoff QR')),
        body: MobileScanner(
          onDetect: (capture) {
            if (done) return;
            final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
            if (value != null && value.startsWith('shipdehop://handoff/')) {
              done = true;
              Navigator.pop(context, value);
            }
          },
        ),
      );
}
