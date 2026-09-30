import 'package:flutter/material.dart';
import '../core/theme/even_colors.dart';

/// Two-step erase: Cancel is first, then the user must type DELETE.
class DeleteAccountPrompt extends StatefulWidget {
  static const confirmWord = 'DELETE';

  const DeleteAccountPrompt({super.key});

  static Future<bool> confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const DeleteAccountPrompt(),
    );
    return ok == true;
  }

  @override
  State<DeleteAccountPrompt> createState() => _DeleteAccountPromptState();
}

class _DeleteAccountPromptState extends State<DeleteAccountPrompt> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches =>
      _controller.text.trim().toUpperCase() == DeleteAccountPrompt.confirmWord;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: EvenColors.darkSurfaceElevated,
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This erases your plates on this phone and on your EvenPlate account. You cannot undo it.',
          ),
          const SizedBox(height: 16),
          Text(
            'Type ${DeleteAccountPrompt.confirmWord} to continue.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: DeleteAccountPrompt.confirmWord,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: EvenColors.crashWarning,
            disabledBackgroundColor: EvenColors.crashWarning.withValues(
              alpha: 0.35,
            ),
          ),
          child: const Text('Delete permanently'),
        ),
      ],
    );
  }
}
