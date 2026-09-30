import 'package:flutter/material.dart';
import '../../core/theme/even_colors.dart';
import '../../services/local_storage_service.dart';
import '../../services/revenuecat_service.dart';
import '../../widgets/even_snack.dart';
import '../../widgets/glass_card.dart';
import 'credit_packs_section.dart';

class PlanCreditsScreen extends StatefulWidget {
  final LocalStorageService storage;
  final RevenueCatService? revenueCat;
  const PlanCreditsScreen({super.key, required this.storage, this.revenueCat});

  @override
  State<PlanCreditsScreen> createState() => _PlanCreditsScreenState();
}

class _PlanCreditsScreenState extends State<PlanCreditsScreen> {
  bool _restoringPurchases = false;

  Future<void> _restorePurchases() async {
    final service = widget.revenueCat;
    if (_restoringPurchases || service == null || service.isLoading) return;
    setState(() => _restoringPurchases = true);
    try {
      final restored = await service.restorePurchases();
      if (!mounted) return;
      EvenSnack.show(
        context,
        restored
            ? 'Purchases restored successfully. Pro active.'
            : 'No active purchases found to restore. If you expected a subscription, check your store account and try again.',
        icon: restored
            ? Icons.check_circle_rounded
            : Icons.info_outline_rounded,
      );
    } finally {
      if (mounted) setState(() => _restoringPurchases = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.storage.profileChanges,
      if (widget.revenueCat != null) widget.revenueCat!,
    ]),
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.storage.hasPro ? 'EvenPlate Pro' : 'EvenPlate Free',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Included this week: ${widget.storage.userProfile.freeScansRemaining} photo scans and ${widget.storage.userProfile.textRemaining} food assessments left.',
                ),
                const SizedBox(height: 6),
                Text(
                  'Extra credits: ${widget.storage.userProfile.photoPurchased} photo scans and ${widget.storage.userProfile.textPurchased} food assessments.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(
              Icons.restore_rounded,
              color: EvenColors.primaryGreen,
            ),
            title: Text(
              _restoringPurchases
                  ? 'Restoring purchases...'
                  : 'Restore purchases',
            ),
            subtitle: const Text('Recover purchases from your store account'),
            enabled:
                widget.revenueCat != null &&
                !_restoringPurchases &&
                !(widget.revenueCat?.isLoading ?? false),
            onTap: _restorePurchases,
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(
              Icons.manage_accounts_outlined,
              color: EvenColors.primaryGreen,
            ),
            title: const Text('Manage subscription'),
            subtitle: const Text('View renewal details or cancel in the store'),
            trailing: const Icon(Icons.open_in_new_rounded),
            enabled: widget.revenueCat != null,
            onTap: () => widget.revenueCat?.manageSubscriptions(),
          ),
          const SizedBox(height: 20),
          CreditPacksSection(
            service: widget.revenueCat,
            disabled: _restoringPurchases,
          ),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}
