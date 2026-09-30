import '../../widgets/analysis_consent_prompt.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/material.dart';
import '../../core/billing/scan_allowance.dart';
import '../../core/legal/legal_copy.dart';
import '../../core/legal/legal_document_screen.dart';
import '../../core/theme/even_colors.dart';
import '../../core/utils/sensory_feedback.dart';
import '../../models/user_profile.dart';
import '../../services/local_storage_service.dart';
import '../../services/onesignal_service.dart';
import '../../services/revenuecat_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/delete_account_prompt.dart';
import '../../widgets/even_brand_lockup.dart';
import '../../widgets/even_snack.dart';
import '../../widgets/glass_card.dart';
import '../onboarding/onboarding_screen.dart';
import 'paywall_screen.dart';
import 'plan_credits_screen.dart';

class SettingsScreen extends StatefulWidget {
  final LocalStorageService storage;
  final OneSignalService? oneSignal;
  final SupabaseService? supabase;
  final RevenueCatService? revenueCat;

  const SettingsScreen({
    super.key,
    required this.storage,
    this.oneSignal,
    this.supabase,
    this.revenueCat,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _promoController = TextEditingController();
  @override
  void initState() {
    super.initState();
    unawaited(_syncEntitlement());
  }

  Future<void> _syncEntitlement() async {
    await widget.revenueCat?.checkProStatus();
    await widget.supabase?.pullProfileQuota();
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _confirmSignOut() async {
    SensoryFeedback.gentleTap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EvenColors.darkSurfaceElevated,
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again to sync plates to this account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (widget.supabase != null) {
      await widget.supabase!.signOut();
    }
  }

  void _showPromoBypassDialog() {
    _promoController.clear();
    showDialog(
      context: context,
      builder: (ctx) {
        var busy = false;
        String? error;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> submit() async {
              if (busy) return;
              setDialogState(() {
                busy = true;
                error = null;
              });
              final supabase = widget.supabase;
              if (supabase == null) {
                setDialogState(() {
                  busy = false;
                  error = 'Sign in to redeem a promo code.';
                });
                return;
              }
              final result = await supabase.redeemPromoCode(
                _promoController.text,
              );
              if (!ctx.mounted) return;
              if (result.redeemed) {
                await SensoryFeedback.zenBloomPulse();
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (!mounted) return;
                EvenSnack.show(
                  context,
                  'Pro unlocked. Weekly photo and food scores apply.',
                  icon: Icons.check_circle_rounded,
                );
                return;
              }
              setDialogState(() {
                busy = false;
                error = result.message ?? 'That code is not valid.';
              });
            }

            return AlertDialog(
              backgroundColor: EvenColors.darkSurfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.verified_outlined,
                    color: EvenColors.bufferAmber,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text('Promo code'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter a promo code to unlock Pro.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _promoController,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      hintText: 'Promo code',
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: const TextStyle(
                        color: EvenColors.crashWarning,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: busy ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EvenColors.netSage,
                  ),
                  child: Text(busy ? 'Checking...' : 'Unlock Pro'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _setReminderFlag({
    required bool value,
    required UserProfile Function() update,
  }) async {
    SensoryFeedback.gentleTap();
    if (value && !widget.storage.userProfile.pushConsentGranted) {
      await widget.oneSignal?.grantPushConsent();
    }
    await widget.storage.saveUserProfile(update());
    await widget.oneSignal?.syncUserTags();
    setState(() {});
  }

  void _showSelectionSheet({
    required String title,
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onSelected,
  }) {
    SensoryFeedback.gentleTap();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ...options.map((opt) {
                  final isSelected = opt == currentValue;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      opt,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected
                            ? EvenColors.netSageLight
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: EvenColors.netSageLight,
                            size: 20,
                          )
                        : null,
                    onTap: () {
                      SensoryFeedback.gentleTap();
                      onSelected(opt);
                      Navigator.of(ctx).pop();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.storage.profileChanges,
        if (widget.revenueCat != null) widget.revenueCat!,
      ]),
      builder: (context, _) => _buildSettings(context),
    );
  }

  Widget _buildSettings(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = widget.storage.userProfile;
    final isPro = widget.storage.hasPro;
    final accountEmail = widget.supabase?.currentUser?.email ?? profile.email;
    final accountId = widget.supabase?.currentUser?.id ?? profile.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // Pro Status Card
            GlassCard(
              padding: const EdgeInsets.all(16),
              customBorder: isPro
                  ? EvenColors.bufferAmber.withValues(alpha: 0.5)
                  : null,
              customFill: isPro
                  ? EvenColors.bufferAmber.withValues(alpha: 0.12)
                  : null,
              child: Row(
                children: [
                  isPro
                      ? ClipOval(
                          child: Image.asset(
                            EvenBrandLockup.assetPath,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: EvenColors.netSage.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock_outline_rounded,
                            color: EvenColors.netSageLight,
                          ),
                        ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPro ? 'EvenPlate Pro Active' : 'EvenPlate Free',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${profile.freeScansRemaining} of ${ScanAllowance.includedPhotoWeekly(isPro: isPro)} photo scans and ${profile.textRemaining} of ${ScanAllowance.includedTextWeekly(isPro: isPro)} food scores left this week.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? EvenColors.textDarkSecondary
                                : EvenColors.textLightSecondary,
                          ),
                        ),
                        if (profile.photoPurchased > 0 ||
                            profile.textPurchased > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Extra credits: ${profile.photoPurchased} photo scans and ${profile.textPurchased} food assessments.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? EvenColors.textDarkSecondary
                                    : EvenColors.textLightSecondary,
                              ),
                            ),
                          ),
                        if (ScanAllowance.photoLow(
                              profile.freeScansRemaining,
                              isPro: isPro,
                            ) ||
                            ScanAllowance.textLow(
                              profile.textRemaining,
                              isPro: isPro,
                            ))
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'This week\'s included credits are almost gone.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: EvenColors.primaryGreen,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isPro)
                    ElevatedButton(
                      onPressed: () {
                        SensoryFeedback.gentleTap();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PaywallScreen(
                              storage: widget.storage,
                              revenueCatService: widget.revenueCat,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: EvenColors.netSage,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Upgrade',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            GlassCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: EvenColors.primaryGreen,
                ),
                title: const Text('Wallet'),
                subtitle: const Text(
                  'Manage subscription, restore, or add credits',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlanCreditsScreen(
                      storage: widget.storage,
                      revenueCat: widget.revenueCat,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Profile & Preferences Section
            Text(
              'Nutrition Profile & Blueprint',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Primary Satiety Goal'),
                    subtitle: Text(profile.primaryGoal),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      _showSelectionSheet(
                        title: 'Primary Satiety Goal',
                        options: [
                          'Steady Energy All Day',
                          'Understand My Meal Patterns',
                          'Nourish Without Counting Calories',
                          'Lean Fuel & Athletic Vitality',
                        ],
                        currentValue: profile.primaryGoal,
                        onSelected: (val) async {
                          final updated = widget.storage.userProfile
                              .withPrimaryGoal(val);
                          await widget.storage.saveUserProfile(updated);
                          setState(() {});
                        },
                      );
                    },
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  ListTile(
                    leading: const Icon(Icons.bolt_outlined),
                    title: const Text('Crash / Slump Window'),
                    subtitle: Text(profile.crashPattern),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      _showSelectionSheet(
                        title: 'Energy Slump & Crash Window',
                        options: [
                          'Afternoon Slump (2:00-3:30 PM)',
                          'Mid-Morning Dip (10:30-11:30 AM)',
                          'Late-Night Snacking (8:00-10:00 PM)',
                          'All-Day Rollercoaster',
                        ],
                        currentValue: profile.crashPattern,
                        onSelected: (val) async {
                          final updated = profile.copyWith(crashPattern: val);
                          await widget.storage.saveUserProfile(updated);
                          setState(() {});
                        },
                      );
                    },
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  ListTile(
                    leading: const Icon(Icons.eco_outlined),
                    title: const Text('Dietary Protocol'),
                    subtitle: Text(profile.dietaryPreference),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      _showSelectionSheet(
                        title: 'Dietary Identity & Boundaries',
                        options: [
                          'Omnivore / Balanced',
                          'Plant-Forward & Flexitarian',
                          '100% Plant-Based / Vegan',
                          'Low-Carb & High-Protein',
                          'Sensitive / Simple Ingredients',
                        ],
                        currentValue: profile.dietaryPreference,
                        onSelected: (val) async {
                          final updated = profile.copyWith(
                            dietaryPreference: val,
                            eatingStyle: val,
                          );
                          await widget.storage.saveUserProfile(updated);
                          setState(() {});
                        },
                      );
                    },
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  ListTile(
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('Daily Meal Schedule'),
                    subtitle: Text(
                      '${profile.mealSchedule} (${profile.targetMealsPerDay} meals / ${profile.targetSatietyHoursDaily.toStringAsFixed(0)}h)',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      _showSelectionSheet(
                        title: 'Daily Meal Rhythm & Frequency',
                        options: [
                          '3 Balanced Meals',
                          '2 Substantial Meals (Intermittent Fasting)',
                          '3 Meals + Mindful Afternoon Snack',
                          'Variable / Shift Schedule',
                        ],
                        currentValue: profile.mealSchedule,
                        onSelected: (val) async {
                          final isTwo =
                              val.contains('2 Meals') ||
                              val.contains('Intermittent');
                          final updated = widget.storage.userProfile.copyWith(
                            mealSchedule: val,
                            targetMealsPerDay: isTwo ? 2 : 3,
                            targetSatietyHoursDaily: isTwo ? 9.0 : 12.0,
                          );
                          await widget.storage.saveUserProfile(updated);
                          setState(() {});
                        },
                      );
                    },
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  ListTile(
                    leading: const Icon(Icons.auto_fix_high_rounded),
                    title: const Text('Coaching Style'),
                    subtitle: Text(profile.coachingStyle),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      _showSelectionSheet(
                        title: 'Coaching & Upgrade Style',
                        options: [
                          '30-Second Pantry Sprinkles',
                          'Smart Whole-Food Swaps',
                          'Mindful Eating & Gut Pace',
                        ],
                        currentValue: profile.coachingStyle,
                        onSelected: (val) async {
                          final updated = profile.copyWith(coachingStyle: val);
                          await widget.storage.saveUserProfile(updated);
                          setState(() {});
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                SensoryFeedback.gentleTap();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OnboardingScreen(
                      storage: widget.storage,
                      oneSignal: widget.oneSignal,
                      onComplete: () => Navigator.of(context).pop(),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retake Satiety Questionnaire'),
              style: OutlinedButton.styleFrom(
                foregroundColor: EvenColors.netSageLight,
                side: BorderSide(
                  color: EvenColors.netSage.withValues(alpha: 0.4),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 20),

            // OneSignal Mindful Retention Notifications Section
            Text(
              'Mindful Retention Notifications',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.bolt_rounded,
                      color: EvenColors.stableHorizon,
                    ),
                    title: const Text('Post-Meal Satiety Check-In'),
                    subtitle: const Text(
                      'Interactive prompt 3.5h after logging (Steady vs Dip)',
                    ),
                    trailing: Switch.adaptive(
                      value: profile.checkInRemindersEnabled,
                      activeTrackColor: EvenColors.netSageLight,
                      onChanged: (val) async {
                        await _setReminderFlag(
                          value: val,
                          update: () => widget.storage.userProfile.copyWith(
                            checkInRemindersEnabled: val,
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  ListTile(
                    leading: const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: EvenColors.bufferAmber,
                    ),
                    title: const Text('Pre-Meal Anchor Nudges'),
                    subtitle: const Text(
                      'Mindful reminders at 12:15 PM and 6:45 PM',
                    ),
                    trailing: Switch.adaptive(
                      value: profile.preMealNudgesEnabled,
                      activeTrackColor: EvenColors.netSageLight,
                      onChanged: (val) async {
                        await _setReminderFlag(
                          value: val,
                          update: () => widget.storage.userProfile.copyWith(
                            preMealNudgesEnabled: val,
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  ListTile(
                    leading: const Icon(
                      Icons.calendar_today_outlined,
                      color: EvenColors.netSageLight,
                    ),
                    title: const Text('Sunday Satiety Harmony Recap'),
                    subtitle: const Text(
                      'Weekly summary of steady energy and held plates',
                    ),
                    trailing: Switch.adaptive(
                      value: profile.weeklyRecapEnabled,
                      activeTrackColor: EvenColors.netSageLight,
                      onChanged: (val) async {
                        await _setReminderFlag(
                          value: val,
                          update: () => widget.storage.userProfile.copyWith(
                            weeklyRecapEnabled: val,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Contact support'),
              subtitle: const Text('evenplatesupport@gmail.com'),
              onTap: () async {
                final opened = await launchUrl(
                  Uri(
                    scheme: 'mailto',
                    path: 'evenplatesupport@gmail.com',
                    queryParameters: {'subject': 'EvenPlate support'},
                  ),
                );
                if (!opened && context.mounted) {
                  EvenSnack.show(
                    context,
                    'Email evenplatesupport@gmail.com for help.',
                  );
                }
              },
            ),
            Text('Legal', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.privacy_tip_outlined,
                      color: EvenColors.netSageLight,
                    ),
                    title: const Text('Privacy Policy'),
                    onTap: () {
                      SensoryFeedback.gentleTap();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LegalDocumentScreen.privacy(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  ListTile(
                    leading: const Icon(
                      Icons.description_outlined,
                      color: EvenColors.netSageLight,
                    ),
                    title: const Text('Terms of Use'),
                    onTap: () {
                      SensoryFeedback.gentleTap();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LegalDocumentScreen.terms(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  ListTile(
                    leading: const Icon(
                      Icons.health_and_safety_outlined,
                      color: EvenColors.bufferAmber,
                    ),
                    title: const Text('Nutrition disclaimer'),
                    subtitle: const Text(
                      'Estimates are educational, not medical advice',
                    ),
                    onTap: () {
                      SensoryFeedback.gentleTap();
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Nutrition disclaimer'),
                          content: const Text(LegalCopy.shortDisclaimer),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Account Management
            Text('Account', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: const Text('Signed in as'),
                    subtitle: Text(
                      '${accountEmail?.isNotEmpty == true ? accountEmail : 'Guest account'}\nAccount ID: ${accountId.length > 8 ? accountId.substring(0, 8) : accountId}',
                    ),
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  ListTile(
                    leading: const Icon(
                      Icons.logout_rounded,
                      color: Colors.grey,
                    ),
                    title: const Text('Sign Out'),
                    onTap: _confirmSignOut,
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  ListenableBuilder(
                    listenable: widget.supabase ?? widget.storage,
                    builder: (context, _) => ListTile(
                      title: Text(
                        widget.supabase?.syncIssue ?? 'Cloud diary sync',
                      ),
                      trailing: TextButton(
                        onPressed: () => widget.supabase?.refreshAccount(),
                        child: const Text('Sync now'),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Allow Google Gemini meal analysis'),
                    subtitle: const Text(
                      'Turn off to view saved meals and reuse cached assessments.',
                    ),
                    value: widget.storage.analysisConsentGranted,
                    onChanged: (value) async {
                      if (value) {
                        await AnalysisConsentPrompt.ensure(
                          context,
                          widget.storage,
                        );
                      } else {
                        await widget.storage.setAnalysisConsent(false);
                      }
                      if (mounted) setState(() {});
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_forever_rounded,
                      color: EvenColors.crashWarning,
                    ),
                    title: const Text(
                      'Delete Account & Data',
                      style: TextStyle(color: EvenColors.crashWarning),
                    ),
                    onTap: () async {
                      SensoryFeedback.softWarning();
                      final confirm = await DeleteAccountPrompt.confirm(
                        context,
                      );
                      if (confirm != true || widget.supabase == null) return;
                      try {
                        await widget.supabase!.eraseAccountData();
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Account deletion could not finish. Please try again. Your account has not been cleared on this phone.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Privileged access',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: const Icon(
                  Icons.verified_outlined,
                  color: EvenColors.bufferAmber,
                ),
                title: const Text('Promo Bypass Code'),
                subtitle: const Text('Enter a promo code to unlock Pro'),
                onTap: () {
                  SensoryFeedback.gentleTap();
                  _showPromoBypassDialog();
                },
              ),
            ),
            const SizedBox(height: 110),
          ],
        ),
      ),
    );
  }
}
