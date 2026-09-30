import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../core/theme/even_colors.dart';
import '../../core/legal/legal_document_screen.dart';
import '../../core/utils/sensory_feedback.dart';
import '../../services/local_storage_service.dart';
import '../../services/revenuecat_service.dart';
import '../../widgets/even_brand_lockup.dart';
import '../../widgets/even_snack.dart';
import '../../widgets/glass_card.dart';

class PaywallScreen extends StatefulWidget {
  final LocalStorageService storage;
  final RevenueCatService? revenueCatService;

  const PaywallScreen({
    super.key,
    required this.storage,
    this.revenueCatService,
  });

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  PackageType _selectedPlanType = PackageType.annual;
  bool _isLoading = false;
  SubscriptionRenewalState? _subscriptionState;

  @override
  void initState() {
    super.initState();
    widget.revenueCatService?.addListener(_onOfferingsChanged);
    _syncSelectedPlan();
    _refreshSubscriptionState();
    // Offerings may have failed to load at startup. Retry on open so a
    // transient failure does not leave the paywall permanently empty.
    if (widget.revenueCatService?.availablePackages.isEmpty ?? false) {
      widget.revenueCatService?.fetchOfferings();
    }
  }

  @override
  void dispose() {
    widget.revenueCatService?.removeListener(_onOfferingsChanged);
    super.dispose();
  }

  void _onOfferingsChanged() {
    if (mounted) setState(_syncSelectedPlan);
  }

  /// Fall back to whichever plan actually exists, so a partially configured
  /// offering does not leave the paywall with nothing to sell.
  void _syncSelectedPlan() {
    if (_packageFor(_selectedPlanType) != null) return;
    for (final type in const [PackageType.annual, PackageType.monthly]) {
      if (_packageFor(type) != null) {
        _selectedPlanType = type;
        return;
      }
    }
  }

  Package? _packageFor(PackageType type) =>
      widget.revenueCatService?.packageFor(type);

  Future<void> _refreshSubscriptionState() async {
    final state = await widget.revenueCatService?.subscriptionRenewalState();
    if (mounted) setState(() => _subscriptionState = state);
  }

  /// A genuinely free introductory offer, or null. A discounted intro price is
  /// not a trial and must not be advertised as one.
  IntroductoryPrice? _freeTrial(Package? package) {
    if (package == null ||
        !(widget.revenueCatService?.trialEligible(package) ?? false)) {
      return null;
    }
    final intro = package.storeProduct.introductoryPrice;
    if (intro == null || intro.price != 0) return null;
    return intro;
  }

  String _trialLabel(IntroductoryPrice trial) {
    final unit = switch (trial.periodUnit) {
      PeriodUnit.day => 'Day',
      PeriodUnit.week => 'Week',
      PeriodUnit.month => 'Month',
      PeriodUnit.year => 'Year',
      PeriodUnit.unknown => 'Period',
    };
    return '${trial.periodNumberOfUnits}-$unit Free Trial';
  }

  String _priceLabel(Package? package, String suffix) {
    final price = package?.storeProduct.priceString;
    if (price == null) return 'Unavailable';
    return '$price / $suffix';
  }

  /// Savings computed from the live prices. Advertising a fixed percentage
  /// would be a false claim as soon as either price is changed in the
  /// RevenueCat dashboard.
  String? _savingsBadge(Package? annual, Package? monthly) {
    if (annual == null || monthly == null) return null;
    final yearOfMonthlies = monthly.storeProduct.price * 12;
    if (yearOfMonthlies <= 0) return null;
    final saved = 1 - (annual.storeProduct.price / yearOfMonthlies);
    if (saved < 0.01) return null;
    return 'SAVE ${(saved * 100).round()}%';
  }

  String _annualSubtext(Package? package) {
    if (package == null) return 'Pricing unavailable';
    final trial = _freeTrial(package);
    final perMonth = package.storeProduct.pricePerMonthString;
    if (trial != null) {
      return perMonth == null
          ? _trialLabel(trial)
          : '${_trialLabel(trial)}, then ${package.storeProduct.priceString} per year';
    }
    return perMonth == null ? 'Billed yearly' : 'Works out to $perMonth/mo';
  }

  String _subscribeLabel(Package? package, IntroductoryPrice? trial) {
    if (package == null) return 'Plans unavailable';
    if (trial != null) return 'Start ${_trialLabel(trial)}';
    return 'Unlock Pro for ${package.storeProduct.priceString}';
  }

  void _showSnack(
    String message, {
    IconData? icon,
    Color iconColor = EvenColors.primaryGreen,
  }) {
    EvenSnack.show(context, message, icon: icon, iconColor: iconColor);
  }

  void _handleSubscribe() async {
    final service = widget.revenueCatService;
    final package = _packageFor(_selectedPlanType);
    if (service == null || package == null) {
      SensoryFeedback.gentleTap();
      _showSnack('Plans are unavailable right now. Please try again shortly.');
      return;
    }

    setState(() => _isLoading = true);
    SensoryFeedback.gentleTap();

    final state = await service.subscriptionRenewalState();
    if (!mounted) return;
    setState(() => _subscriptionState = state);
    if (state != SubscriptionRenewalState.inactive) {
      setState(() => _isLoading = false);
      _showSnack(
        state == SubscriptionRenewalState.ending
            ? 'Pro is active until your current period ends. To renew, use Manage subscription in the App Store.'
            : state == SubscriptionRenewalState.renewing
            ? 'Your Pro subscription is already active. Manage or change it in the App Store.'
            : 'Subscription status is unavailable. Please try again shortly.',
      );
      return;
    }

    final success = await service.purchasePackage(package);

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!success) {
      _showSnack(
        'Purchase could not be confirmed. Check your store account or restore purchases before trying again.',
      );
      return;
    }

    await SensoryFeedback.zenBloomPulse();
    if (!mounted) return;
    if (!widget.storage.canScanPlate()) {
      _showSnack(
        'Pro is active, but scans have not synced yet. Please reopen Wallet shortly.',
        icon: Icons.info_outline_rounded,
      );
      Navigator.of(context).pop();
      return;
    }
    _showSnack(
      'Welcome to EvenPlate Pro. Weekly photo and food scores are included.',
      icon: Icons.star_rounded,
    );
    Navigator.of(context).pop();
  }

  void _handleRestore() async {
    final service = widget.revenueCatService;
    if (_isLoading || (service?.isLoading ?? false)) return;
    SensoryFeedback.gentleTap();
    if (service == null) {
      _showSnack('No active purchases found to restore.');
      return;
    }

    setState(() => _isLoading = true);
    final success = await service.restorePurchases();

    if (!mounted) return;
    setState(() => _isLoading = false);
    _showSnack(
      success
          ? 'Purchases restored successfully. Pro unlocked.'
          : 'No active purchases found to restore.',
      icon: success ? Icons.check_circle_rounded : Icons.info_outline_rounded,
    );
    if (success) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final annual = _packageFor(PackageType.annual);
    final monthly = _packageFor(PackageType.monthly);
    final selected = _selectedPlanType == PackageType.annual ? annual : monthly;
    final trial = _freeTrial(selected);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            key: const ValueKey('btn_paywall_restore'),
            onPressed:
                (_isLoading || (widget.revenueCatService?.isLoading ?? false))
                ? null
                : _handleRestore,
            child: const Text('Restore', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Image.asset(
                  EvenBrandLockup.assetPath,
                  width: 72,
                  height: 72,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  cacheWidth: 216,
                  cacheHeight: 216,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Unlock EvenPlate Pro',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Master lasting satiety and balance every plate without counting calories.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),

              // Value Props
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildFeatureRow(
                      Icons.camera_alt_outlined,
                      '75 photo scans and 100 food scores each week',
                    ),
                    const SizedBox(height: 14),
                    _buildFeatureRow(
                      Icons.timer_outlined,
                      'Relative Fullness Ratings',
                    ),
                    const SizedBox(height: 14),
                    _buildFeatureRow(
                      Icons.auto_awesome_outlined,
                      'Food pairings and your own energy check-ins',
                    ),
                    const SizedBox(height: 14),
                    _buildFeatureRow(
                      Icons.eco_outlined,
                      'Weekly satiety recaps and check-in reminders',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Plan Options
              Row(
                children: [
                  Expanded(
                    child: _buildPlanCard(
                      key: const ValueKey('paywall_plan_annual'),
                      title: 'Annual',
                      badge: _savingsBadge(annual, monthly),
                      price: _priceLabel(annual, 'yr'),
                      subtext: _annualSubtext(annual),
                      isSelected: _selectedPlanType == PackageType.annual,
                      onTap: () => setState(
                        () => _selectedPlanType = PackageType.annual,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildPlanCard(
                      key: const ValueKey('paywall_plan_monthly'),
                      title: 'Monthly',
                      badge: null,
                      price: _priceLabel(monthly, 'mo'),
                      subtext: monthly == null
                          ? 'Pricing unavailable'
                          : 'Flexible monthly billing',
                      isSelected: _selectedPlanType == PackageType.monthly,
                      onTap: () => setState(
                        () => _selectedPlanType = PackageType.monthly,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_subscriptionState == SubscriptionRenewalState.ending ||
                  _subscriptionState == SubscriptionRenewalState.renewing) ...[
                Text(
                  _subscriptionState == SubscriptionRenewalState.ending
                      ? 'Pro is active until the end of this billing period. Renewal is off. To renew, open Manage subscription in the App Store.'
                      : 'Your Pro subscription is active. Use Manage subscription in the App Store to change or cancel it.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],

              // Subscribe Button
              ElevatedButton(
                key: const ValueKey('btn_paywall_subscribe'),
                onPressed:
                    (_isLoading ||
                        (widget.revenueCatService?.isLoading ?? false) ||
                        (selected == null &&
                            _subscriptionState !=
                                SubscriptionRenewalState.ending &&
                            _subscriptionState !=
                                SubscriptionRenewalState.renewing))
                    ? null
                    : (_subscriptionState == SubscriptionRenewalState.ending ||
                          _subscriptionState ==
                              SubscriptionRenewalState.renewing)
                    ? () => widget.revenueCatService?.manageSubscriptions()
                    : _handleSubscribe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: EvenColors.netSage,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _subscriptionState == SubscriptionRenewalState.ending ||
                                _subscriptionState ==
                                    SubscriptionRenewalState.renewing
                            ? 'Manage subscription'
                            : _subscribeLabel(selected, trial),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                'Included credits renew each Monday at 00:00 UTC.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? EvenColors.textDarkSecondary
                      : EvenColors.textLightSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Payment is charged to your store account. Subscriptions renew automatically unless canceled before renewal. Manage or cancel in your store subscription settings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? EvenColors.textDarkMuted
                      : EvenColors.textLightMuted,
                ),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LegalDocumentScreen.terms(),
                      ),
                    ),
                    child: const Text('Terms of Use'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LegalDocumentScreen.privacy(),
                      ),
                    ),
                    child: const Text('Privacy Policy'),
                  ),
                  TextButton(
                    onPressed: () =>
                        widget.revenueCatService?.manageSubscriptions(),
                    child: const Text('Manage subscription'),
                  ),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: EvenColors.primaryGreen),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildPlanCard({
    Key? key,
    required String title,
    required String? badge,
    required String price,
    required String subtext,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      key: key,
      onTap: () {
        SensoryFeedback.gentleTap();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? EvenColors.netSage.withValues(alpha: isDark ? 0.2 : 0.1)
              : (isDark ? EvenColors.darkSurface : EvenColors.lightSurface),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? EvenColors.netSageLight
                : (isDark
                      ? EvenColors.darkGlassBorder
                      : EvenColors.lightGlassBorder),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (badge != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: EvenColors.bufferAmber,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              subtext,
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? EvenColors.textDarkSecondary
                    : EvenColors.textLightSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
