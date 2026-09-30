import 'package:flutter/material.dart';
import '../../core/a11y/access.dart';
import '../../core/theme/even_colors.dart';
import '../../core/theme/even_fonts.dart';
import '../../core/utils/sensory_feedback.dart';
import '../../services/local_storage_service.dart';
import '../../services/onesignal_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/glass_card.dart';

// Data

const _kAccent = EvenColors.netSage;

class _Option {
  final String label;
  final String value;
  const _Option(this.label, this.value);
}

final _screen1Options = [
  const _Option(
    'Afternoons hit a wall. I need energy that lasts.',
    'Understand My Meal Patterns',
  ),
  const _Option(
    'I eat fine but still feel foggy all day',
    'Steady Energy All Day',
  ),
  const _Option(
    "I'm tired of counting. I just want to feel good",
    'Nourish Without Counting Calories',
  ),
  const _Option(
    "I need consistent fuel. I'm building something.",
    'Lean Fuel & Athletic Vitality',
  ),
];

final _screen2Options = [
  const _Option(
    "Mid-morning. Breakfast didn't last.",
    'Mid-Morning Dip (10:30-11:30 AM)',
  ),
  const _Option(
    'Post-lunch. Every. Single. Day.',
    'Afternoon Slump (2:00-3:30 PM)',
  ),
  const _Option(
    'Evening. Tired but snacking anyway.',
    'Late-Night Snacking (8:00-10:00 PM)',
  ),
  const _Option("All day. It's basically chaos.", 'All-Day Rollercoaster'),
];

final _screen3Options = [
  const _Option("A bit of everything, life's too short", 'Omnivore / Balanced'),
  const _Option('Mostly plants, flexibly', 'Plant-Forward & Flexitarian'),
  const _Option('Strictly plant-based', '100% Plant-Based / Vegan'),
  const _Option('High protein, low carb', 'Low-Carb & High-Protein'),
];

String _valueFor(List<_Option> options, String label) {
  for (final option in options) {
    if (option.label == label) return option.value;
  }
  return options.first.value;
}

// Screen

class OnboardingScreen extends StatefulWidget {
  final LocalStorageService storage;
  final SupabaseService? supabase;
  final OneSignalService? oneSignal;

  /// Called after onboarding completes - caller handles navigation.
  final VoidCallback? onComplete;

  const OnboardingScreen({
    super.key,
    required this.storage,
    this.supabase,
    this.oneSignal,
    this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Selections (default to first option)
  String _sel1 = _screen1Options.first.label;
  String _sel2 = _screen2Options.first.label;
  String _sel3 = _screen3Options.first.label;
  bool _enableNotifications = false;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _goNext() {
    SensoryFeedback.gentleTap();
    if (_currentPage < 3) {
      _fadeCtrl.forward(from: 0);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  void _goBack() {
    SensoryFeedback.gentleTap();
    if (_currentPage > 0) {
      _fadeCtrl.forward(from: 0);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _finish() async {
    if (_enableNotifications && widget.oneSignal != null) {
      await widget.oneSignal!.grantPushConsent();
    }

    final goal = _valueFor(_screen1Options, _sel1);
    final updated = widget.storage.userProfile
        .withPrimaryGoal(goal)
        .copyWith(
          primaryGoal: goal,
          crashPattern: _valueFor(_screen2Options, _sel2),
          dietaryPreference: _valueFor(_screen3Options, _sel3),
          eatingStyle: _valueFor(_screen3Options, _sel3),
          coachingStyle: '30-Second Pantry Sprinkles',
          hasCompletedOnboarding: true,
          checkInRemindersEnabled: _enableNotifications,
          preMealNudgesEnabled: _enableNotifications,
          weeklyRecapEnabled: _enableNotifications,
          pushConsentGranted: _enableNotifications,
        );
    await widget.storage.saveUserProfile(updated);
    await widget.oneSignal?.syncUserTags();
    SensoryFeedback.zenBloomPulse();

    if (mounted) {
      widget.onComplete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EvenColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            _TopBar(
              currentPage: _currentPage,
              totalQuestions: 3,
              onBack: (_currentPage > 0 || Navigator.of(context).canPop())
                  ? _goBack
                  : null,
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (p) => setState(() => _currentPage = p),
                children: [
                  _QuestionPage(
                    illustrationPath:
                        'assets/images/onboarding/illus_slump.jpg',
                    eyebrow: '1 of 3',
                    headline: 'What are we actually\nfixing here?',
                    subtitle: 'No judgment. We\'ve all been there.',
                    options: _screen1Options,
                    selected: _sel1,
                    onSelect: (v) => setState(() => _sel1 = v),
                    fadeAnim: _fadeAnim,
                  ),
                  _QuestionPage(
                    illustrationPath:
                        'assets/images/onboarding/illus_glazed.jpg',
                    eyebrow: '2 of 3',
                    headline: 'When does your energy\nbetray you?',
                    subtitle: 'Be honest. This is confidential.',
                    options: _screen2Options,
                    selected: _sel2,
                    onSelect: (v) => setState(() => _sel2 = v),
                    fadeAnim: _fadeAnim,
                  ),
                  _QuestionPage(
                    illustrationPath: 'assets/images/onboarding/illus_food.jpg',
                    eyebrow: '3 of 3',
                    headline: 'How do you typically\neat?',
                    subtitle: 'Every suggestion will stay within this.',
                    options: _screen3Options,
                    selected: _sel3,
                    onSelect: (v) => setState(() => _sel3 = v),
                    fadeAnim: _fadeAnim,
                  ),
                  _BlueprintPage(
                    goal: _valueFor(_screen1Options, _sel1),
                    crash: _valueFor(_screen2Options, _sel2),
                    diet: _valueFor(_screen3Options, _sel3),
                    enableNotifications: _enableNotifications,
                    onNotifToggle: (v) =>
                        setState(() => _enableNotifications = v),
                  ),
                ],
              ),
            ),

            // CTA Button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: _CTAButton(
                label: _currentPage == 3 ? 'Enter EvenPlate' : 'Next',
                onTap: _goNext,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// _TopBar
class _TopBar extends StatelessWidget {
  final int currentPage;
  final int totalQuestions;
  final VoidCallback? onBack;

  const _TopBar({
    required this.currentPage,
    required this.totalQuestions,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          // Back button
          if (onBack != null)
            GestureDetector(
              key: const ValueKey('btn_onboarding_back'),
              onTap: onBack,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: EvenColors.darkSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 15,
                  color: EvenColors.textDarkPrimary,
                ),
              ),
            )
          else
            const SizedBox(width: 36),
          const SizedBox(width: 12),
          // Wordmark
          Text(
            'evenplate',
            style: evenPoppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: EvenColors.netSageLight,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          // Step pill dots
          Row(
            children: List.generate(totalQuestions + 1, (i) {
              final active = i == currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                width: active ? 20 : 6,
                height: 6,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  color: active ? _kAccent : EvenColors.darkSurfaceElevated,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _QuestionPage extends StatelessWidget {
  final String illustrationPath;
  final String eyebrow;
  final String headline;
  final String subtitle;
  final List<_Option> options;
  final String selected;
  final ValueChanged<String> onSelect;
  final Animation<double> fadeAnim;

  const _QuestionPage({
    required this.illustrationPath,
    required this.eyebrow,
    required this.headline,
    required this.subtitle,
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.fadeAnim,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fadeAnim,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 180,
                  maxWidth: 260,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(illustrationPath, fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Eyebrow badge
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  eyebrow.toUpperCase(),
                  style: evenPoppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: _kAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Headline
            Text(
              headline,
              textAlign: TextAlign.center,
              style: evenPoppins(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: EvenColors.textDarkPrimary,
                letterSpacing: -0.5,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),

            // Subtitle
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: evenPoppins(
                fontSize: 13,
                color: EvenColors.textDarkSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),

            // Options
            ...options.asMap().entries.map((entry) {
              final i = entry.key;
              final opt = entry.value;
              final isSelected = opt.label == selected;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OptionTile(
                  key: ValueKey('opt_${i}_${opt.label}'),
                  label: opt.label,
                  isSelected: isSelected,
                  onTap: () => onSelect(opt.label),
                ),
              );
            }),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

// Option Tile

class _OptionTile extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _OptionTile({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        SensoryFeedback.gentleTap();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? _kAccent.withValues(alpha: 0.22)
              : EvenColors.darkSurface,
          border: Border.all(
            color: isSelected ? _kAccent : EvenColors.darkGlassBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: safeBoxShadows([
            BoxShadow(
              color: isSelected
                  ? _kAccent.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.25),
              blurRadius: isSelected ? 8 : 4,
              offset: const Offset(0, 2),
            ),
          ]),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: evenPoppins(
                  fontSize: 14.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? EvenColors.textDarkPrimary
                      : EvenColors.textDarkSecondary,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 14),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSelected ? _kAccent : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? _kAccent : EvenColors.textDarkMuted,
                  width: isSelected ? 2 : 1.5,
                ),
              ),
              child: isSelected
                  ? const Center(
                      child: Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// Blueprint Reveal Page

class _BlueprintPage extends StatelessWidget {
  final String goal;
  final String crash;
  final String diet;
  final bool enableNotifications;
  final ValueChanged<bool> onNotifToggle;

  const _BlueprintPage({
    required this.goal,
    required this.crash,
    required this.diet,
    required this.enableNotifications,
    required this.onNotifToggle,
  });

  @override
  Widget build(BuildContext context) {
    final crashTitle = crash.contains('(')
        ? crash.split('(').first.trim()
        : crash;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      physics: const BouncingScrollPhysics(),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: _kAccent,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Your Satiety\nBlueprint',
          textAlign: TextAlign.center,
          style: evenPoppins(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: EvenColors.textDarkPrimary,
            letterSpacing: -0.6,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Protein, fiber, and fat is the combo. Volume is how the plate feels finished. Zero calorie math.',
          textAlign: TextAlign.center,
          style: evenPoppins(
            fontSize: 13.5,
            color: EvenColors.textDarkSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),

        // Blueprint card
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: _kAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Blueprint ready',
                        style: evenPoppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: EvenColors.textDarkPrimary,
                        ),
                      ),
                      Text(
                        'Tailored to your answers',
                        style: evenPoppins(
                          fontSize: 11.5,
                          color: _kAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 28, color: EvenColors.darkGlassBorder),
              _BlueprintRow(
                icon: Icons.track_changes_rounded,
                label: 'Goal',
                value: goal,
                color: _kAccent,
              ),
              const SizedBox(height: 14),
              _BlueprintRow(
                icon: Icons.bolt_rounded,
                label: 'Energy dip',
                value: crashTitle,
                color: const Color(0xFFF97316),
              ),
              const SizedBox(height: 14),
              _BlueprintRow(
                icon: Icons.restaurant_rounded,
                label: 'Food style',
                value: diet,
                color: const Color(0xFF6366F1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Editable note
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 16,
                color: EvenColors.textDarkMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Everything here is adjustable anytime in Settings.',
                  style: evenPoppins(
                    fontSize: 12,
                    height: 1.4,
                    color: EvenColors.textDarkMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Notifications opt-in
        GlassCard(
          key: const ValueKey('card_notification_opt_in'),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: _kAccent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mindful Check-in Nudges',
                      style: evenPoppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: EvenColors.textDarkPrimary,
                      ),
                    ),
                    Text(
                      'Gentle alerts after meals to log how your energy held. Off until you opt in. The system prompt appears only after this switch is on.',
                      style: evenPoppins(
                        fontSize: 11.5,
                        color: EvenColors.textDarkMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                key: const ValueKey('push_opt_in_switch'),
                value: enableNotifications,
                activeTrackColor: _kAccent,
                onChanged: onNotifToggle,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _BlueprintRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _BlueprintRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Icon(icon, size: 16, color: color)),
        ),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: evenPoppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: EvenColors.textDarkMuted,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: evenPoppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: EvenColors.textDarkPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

// CTA Button

class _CTAButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CTAButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        key: const ValueKey('btn_onboarding_next'),
        height: 56,
        decoration: BoxDecoration(
          color: _kAccent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: safeBoxShadows([
            BoxShadow(
              color: _kAccent.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ]),
        ),
        child: Center(
          child: Text(
            label,
            style: evenPoppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
