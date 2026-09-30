import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../core/billing/scan_allowance.dart';
import '../../core/theme/even_colors.dart';
import '../../services/revenuecat_service.dart';
import '../../widgets/even_snack.dart';
import '../../widgets/glass_card.dart';

class CreditPacksSection extends StatefulWidget {
  final RevenueCatService? service;
  final bool disabled;
  const CreditPacksSection({super.key, this.service, this.disabled = false});

  @override
  State<CreditPacksSection> createState() => _CreditPacksSectionState();
}

class _CreditPacksSectionState extends State<CreditPacksSection> {
  bool _loading = false;
  String? _purchasing;

  @override
  void initState() {
    super.initState();
    widget.service?.addListener(_changed);
    if (widget.service?.creditPackages.isEmpty ?? false) _load();
  }

  @override
  void didUpdateWidget(CreditPacksSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      oldWidget.service?.removeListener(_changed);
      widget.service?.addListener(_changed);
      if (widget.service?.creditPackages.isEmpty ?? false) _load();
    }
  }

  @override
  void dispose() {
    widget.service?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (_loading || widget.service == null) return;
    setState(() => _loading = true);
    try {
      await widget.service!.fetchOfferings();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buy(Package package) async {
    final service = widget.service;
    if (service == null ||
        _purchasing != null ||
        service.isLoading ||
        widget.disabled) {
      return;
    }
    setState(() => _purchasing = package.storeProduct.identifier);
    try {
      final success = await service.purchasePackage(package);
      if (!mounted) return;
      EvenSnack.show(
        context,
        success
            ? 'Purchase confirmed. Credits may take a moment to sync.'
            : 'Purchase could not be confirmed. Check your store account before trying again.',
      );
    } finally {
      if (mounted) setState(() => _purchasing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packages = {
      for (final package in widget.service?.creditPackages ?? <Package>[])
        if (RevenueCatService.creditProductIds.contains(
          package.storeProduct.identifier,
        ))
          package.storeProduct.identifier: package,
    };
    final busy =
        widget.disabled ||
        _purchasing != null ||
        (widget.service?.isLoading ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Extra credits', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'One-time purchases for Free and Pro. No subscription required.',
        ),
        const SizedBox(height: 12),
        for (final id in const [
          ScanAllowance.photoPack25Id,
          ScanAllowance.photoPack80Id,
          ScanAllowance.textPack40Id,
        ])
          if (packages[id] case final package?) ...[
            GlassCard(
              customBorder: EvenColors.primaryGreen.withValues(alpha: 0.3),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        id == ScanAllowance.textPack40Id
                            ? Icons.restaurant_rounded
                            : Icons.camera_alt_outlined,
                        color: EvenColors.primaryGreen,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(switch (id) {
                          ScanAllowance.photoPack25Id => '25 photo scans',
                          ScanAllowance.photoPack80Id => '80 photo scans',
                          _ => '40 food assessments',
                        }, style: Theme.of(context).textTheme.titleSmall),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    id == ScanAllowance.textPack40Id
                        ? 'Assess meals built or edited with food names.'
                        : 'Analyze meals from your camera or photo library.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: busy ? null : () => _buy(package),
                    style: FilledButton.styleFrom(
                      backgroundColor: EvenColors.primaryGreen,
                      foregroundColor: EvenColors.darkBackground,
                    ),
                    child: Text(
                      _purchasing == id
                          ? 'Purchasing...'
                          : 'Buy for ${package.storeProduct.priceString}',
                    ),
                  ),
                  const Text(
                    'One-time payment',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        if (packages.isEmpty) ...[
          Text(
            _loading
                ? 'Loading store prices...'
                : 'Credit packs are temporarily unavailable.',
          ),
          if (!_loading && widget.service != null)
            OutlinedButton(
              onPressed: busy ? null : _load,
              child: const Text('Retry loading packs'),
            ),
        ],
      ],
    );
  }
}
