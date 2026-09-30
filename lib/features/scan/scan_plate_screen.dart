import '../../widgets/analysis_consent_prompt.dart';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../../services/photo_privacy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/errors/telemetry.dart';
import '../../core/theme/even_colors.dart';
import '../../core/utils/sensory_feedback.dart';
import '../../services/gemini_vision_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/revenuecat_service.dart';
import '../../widgets/ai_thinking_orb.dart';
import '../../widgets/glass_card.dart';
import '../insights/satiety_insight_modal.dart';
import '../insights/satiety_insight_state.dart';
import '../settings/paywall_screen.dart';
import 'plate_analysis_screen.dart';

/// Camera & Gallery Pipeline Screen
/// Provides zero-shutter-lag capture, client-side pre-compression, and instant photo preview with retake/confirm.
class ScanPlateScreen extends StatefulWidget {
  final LocalStorageService storage;
  final GeminiVisionService visionService;
  final RevenueCatService? revenueCat;
  final Future<void> Function()? refreshQuota;
  final Uint8List? initialPreviewBytes;
  final String? initialImagePath;

  const ScanPlateScreen({
    super.key,
    required this.storage,
    required this.visionService,
    this.revenueCat,
    this.refreshQuota,
    this.initialPreviewBytes,
    this.initialImagePath,
  });

  @override
  State<ScanPlateScreen> createState() => _ScanPlateScreenState();
}

class _ScanPlateScreenState extends State<ScanPlateScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isAnalyzing = false;
  String _statusMessage = 'Align your plate in frame';
  String? _permissionError;
  bool _permissionDenied = false;

  File? _capturedFile;
  Uint8List? _capturedBytes;
  String _requestId = const Uuid().v4();

  Future<bool> _ensureScanCredit() async {
    if (widget.storage.canScanPlate()) return true;
    await widget.refreshQuota?.call();
    if (!mounted) return false;
    if (widget.storage.canScanPlate()) return true;
    _showQuotaExceededDialog();
    return false;
  }

  @override
  void initState() {
    super.initState();
    _recoverLostPhoto();
    if (widget.initialPreviewBytes != null) {
      _capturedBytes = widget.initialPreviewBytes;
    }
    if (widget.initialImagePath != null) {
      _capturedFile = File(widget.initialImagePath!);
    }
  }

  Future<void> _captureOrPick(ImageSource source) async {
    if (!await _ensureScanCredit()) return;

    setState(() {
      _permissionError = null;
      _permissionDenied = false;
    });
    SensoryFeedback.gentleTap();

    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (file == null) return;

      final bytes = await stripPhotoMetadata(
        await File(file.path).readAsBytes(),
      );
      if (!mounted) return;
      setState(() {
        _capturedFile = File(file.path);
        _capturedBytes = bytes;
        _requestId = const Uuid().v4();
      });

      SensoryFeedback.resonanceSnap();
    } on PlatformException catch (e) {
      debugPrint('Camera/Gallery platform exception: $e');
      if (!mounted) return;
      setState(() {
        _permissionDenied =
            e.code == 'camera_access_denied' ||
            e.code == 'photo_access_denied' ||
            e.code == 'camera_access_restricted' ||
            e.code == 'photo_access_restricted';
        _permissionError = _permissionDenied
            ? 'Permission was denied. Please allow access in System Settings.'
            : 'Could not open the camera or photos. Please try again.';
      });
    } catch (e) {
      debugPrint('Photo capture exception: $e');
      if (!mounted) return;
      setState(() {
        _permissionError = 'Could not load the photo. Please try again.';
      });
    }
  }

  Future<void> _openPermissionSettings() async {
    try {
      final opened = await const MethodChannel(
        'evenplate/permissions',
      ).invokeMethod<bool>('openSettings');
      if (opened == true || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Open System Settings and select EvenPlate to review access.',
        ),
      ),
    );
  }

  Future<void> _recoverLostPhoto() async {
    if (!Platform.isAndroid) return;
    try {
      final recovered = await _picker.retrieveLostData();
      final file = recovered.files?.firstOrNull;
      if (file == null) return;
      final bytes = await stripPhotoMetadata(await file.readAsBytes());
      if (!mounted) return;
      setState(() {
        _capturedBytes = bytes;
        _requestId = const Uuid().v4();
        _capturedFile = File(file.path);
      });
    } catch (e) {
      Telemetry.report(name: 'camera.recovery_failed', error: e);
    }
  }

  void _retakePhoto() {
    SensoryFeedback.gentleTap();
    setState(() {
      _capturedFile = null;
      _capturedBytes = null;
      _requestId = const Uuid().v4();
      _statusMessage = 'Align your plate in frame';
    });
  }

  Future<void> _analyzeCapturedPhoto() async {
    if (!await AnalysisConsentPrompt.ensure(context, widget.storage) ||
        !mounted) {
      return;
    }
    if (_capturedBytes == null) return;

    if (!await _ensureScanCredit()) return;

    setState(() {
      _isAnalyzing = true;
      _statusMessage =
          'Just a minute. Our in-house chef is analyzing your meal.';
    });

    SensoryFeedback.gentleTap();

    try {
      final analysis = await Telemetry.traceScan(
        () => widget.visionService.analyzePlate(
          imageBytes: _capturedBytes!,
          requestId: _requestId,
          mimeType: 'image/jpeg',
        ),
        outcomeOf: (value) => value.result.captureIssue ?? 'ok',
      );

      if (!mounted) return;
      // The profile ledger consumes the credit and returns the real count.
      final quota = analysis.quota;
      if (quota != null) {
        await widget.storage.applyServerQuota(
          isPro: quota.isPro,
          freeScansRemaining: quota.freeScansRemaining,
          photoPurchased: quota.photoPurchased,
        );
      } else if (analysis.result.captureIssue == null) {
        await widget.storage.consumeScanCredit();
      }

      if (!mounted) return;
      setState(() => _isAnalyzing = false);

      SensoryFeedback.zenBloomPulse();

      if (!mounted) return;
      if (analysis.result.captureIssue != null) {
        await showDialog<void>(
          context: context,
          builder: (_) => SatietyInsightModal(
            insightState: SatietyInsightState.fromResult(analysis.result),
          ),
        );
        return;
      }

      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PlateAnalysisScreen(
            result: analysis.result,
            diaryId: analysis.diaryId,
            imagePath: _capturedFile?.path,
            imageBytes: _capturedBytes,
            storage: widget.storage,
          ),
        ),
      );

      if (saved == true && mounted) {
        Navigator.of(context).pop();
      }
    } on ScanQuotaExceededException catch (e) {
      final quota = e.quota;
      if (quota != null) {
        await widget.storage.applyServerQuota(
          isPro: quota.isPro,
          freeScansRemaining: quota.freeScansRemaining,
          photoPurchased: quota.photoPurchased,
        );
      }
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _statusMessage = 'Weekly photo scans used.';
      });
      _showQuotaExceededDialog();
    } on PlateAnalysisException catch (e) {
      if (e.code != 'REQUEST_PENDING' &&
          e.kind != PlateAnalysisFailureKind.timeout &&
          e.kind != PlateAnalysisFailureKind.network) {
        _requestId = const Uuid().v4();
      }
      if (e.alert) {
        Telemetry.report(
          name: e.telemetryName,
          error: e,
          tags: {
            'source': 'app',
            if (e.code != null) 'code': e.code!,
            if (e.statusCode != null) 'http_status': '${e.statusCode}',
          },
        );
      }
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _statusMessage = 'Analysis failed. Tap confirm to retry.';
        });

        SensoryFeedback.softWarning();
        showDialog(
          context: context,
          builder: (_) => SatietyInsightModal(
            insightState: SatietyInsightState.apiError(e.toString()),
          ),
        );
      }
    } catch (e, st) {
      Telemetry.report(name: 'scan.unknown', error: e, stack: st);
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _statusMessage = 'Analysis failed. Tap confirm to retry.';
        });

        // Premium Fallback UI instead of generic error
        SensoryFeedback.softWarning();
        showDialog(
          context: context,
          builder: (_) => SatietyInsightModal(
            insightState: SatietyInsightState.apiError(e.toString()),
          ),
        );
      }
    }
  }

  void _showQuotaExceededDialog() {
    Telemetry.report(name: 'scan.quota', alert: false);
    showDialog(
      context: context,
      builder: (ctx) => SatietyInsightModal(
        insightState: SatietyInsightState.weeklyLimit(),
        confirmLabel: 'View Pro Plans',
        secondaryLabel: 'Later',
        onSecondary: () => Navigator.of(ctx).pop(),
        onConfirm: () {
          Navigator.of(ctx).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PaywallScreen(
                storage: widget.storage,
                revenueCatService: widget.revenueCat,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasCaptured = _capturedBytes != null || _capturedFile != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          hasCaptured ? 'Plate Preview' : 'Scan a plate',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              // Permission Error Banner
              if (_permissionError != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: EvenColors.anchorTerracotta.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: EvenColors.anchorTerracotta.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: EvenColors.anchorTerracotta,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _permissionError!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: EvenColors.anchorTerracotta,
                              ),
                            ),
                            if (_permissionDenied)
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: EvenColors.primaryGreen,
                                  padding: EdgeInsets.zero,
                                  alignment: Alignment.centerLeft,
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                onPressed: _openPermissionSettings,
                                child: const Text('Open Settings'),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () =>
                            setState(() => _permissionError = null),
                      ),
                    ],
                  ),
                ),

              // Main Frame: Viewfinder, Instant Preview, or Analyzing Loader
              Expanded(
                child: GlassCard(
                  key: ValueKey(
                    hasCaptured ? 'preview_container' : 'viewfinder_container',
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: _isAnalyzing
                        ? _buildAnalyzingState()
                        : (hasCaptured
                              ? _buildInstantPreviewState(isDark)
                              : _buildViewfinderState(context, isDark)),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Bottom Action Buttons
              if (!_isAnalyzing)
                (hasCaptured ? _buildPreviewActions() : _buildCaptureActions()),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Disclaimer: EvenPlate is not a medical device. This analysis is for informational purposes only and should not replace professional medical advice.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.black54,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyzingState() {
    return Center(child: AiThinkingOrb(statusText: _statusMessage));
  }

  Widget _buildInstantPreviewState(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Preview Image Frame
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? Colors.black38 : Colors.white24,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: EvenColors.netSageLight.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: _capturedBytes != null
                  ? Image.memory(_capturedBytes!, fit: BoxFit.contain)
                  : (_capturedFile != null
                        ? Image.file(_capturedFile!, fit: BoxFit.contain)
                        : const Icon(Icons.fastfood_rounded, size: 64)),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Optimization & Status Tag
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: EvenColors.netSage.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: EvenColors.netSageLight.withValues(alpha: 0.3),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: EvenColors.netSageLight,
                size: 14,
              ),
              SizedBox(width: 6),
              Text(
                'Full photo. Ready for analysis',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: EvenColors.netSageLight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildViewfinderState(BuildContext context, bool isDark) {
    // Centers when there is room, scrolls when the content is taller than the card.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Camera Viewfinder Reticle
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: EvenColors.netSageLight.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: EvenColors.netSage.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      size: 46,
                      color: EvenColors.netSageLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Align Meal in Frame',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Protein, fiber, and fat is the combo. Volume is the bonus.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCaptureActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('btn_pick_gallery'),
            onPressed: () => _captureOrPick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('Gallery'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            key: const ValueKey('btn_capture_camera'),
            onPressed: () => _captureOrPick(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_rounded, size: 20),
            label: const Text('Capture Plate'),
            style: ElevatedButton.styleFrom(
              backgroundColor: EvenColors.netSage,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewActions() {
    return Row(
      children: [
        // Retake Button
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('btn_retake_photo'),
            onPressed: _retakePhoto,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retake'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Confirm & Analyze Button
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            key: const ValueKey('btn_confirm_analyze'),
            onPressed: _analyzeCapturedPhoto,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('Analyze Satiety'),
            style: ElevatedButton.styleFrom(
              backgroundColor: EvenColors.netSage,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
