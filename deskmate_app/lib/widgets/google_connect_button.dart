import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import '../theme/app_theme.dart';

/// One-click Google sign-in for Gmail, Calendar, Drive and Tasks, or a
/// "connected" badge once done.
class GoogleConnectButton extends StatelessWidget {
  final void Function(String message, {bool isError}) onResult;

  const GoogleConnectButton({super.key, required this.onResult});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final theme = Theme.of(context);

    if (provider.isGoogleAccountConnected) {
      return Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: theme.statusOk),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Google account connected (Gmail, Calendar, Drive, Tasks)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.successText,
              ),
            ),
          ),
        ],
      );
    }

    final busy = provider.isConnectingGoogle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final error = await provider.connectGoogleAccount();
                    if (!context.mounted) return;
                    if (error != null) {
                      onResult(error, isError: true);
                    } else {
                      onResult(
                        'Google account connected for Gmail, Calendar, Drive and Tasks.',
                      );
                    }
                  },
            icon: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.account_circle_outlined, size: 16),
            label: Text(
              busy ? 'Waiting for Google sign-in…' : 'Connect Google Account',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accentFg,
              foregroundColor: Colors.white,
              disabledBackgroundColor: theme.accentFg.withValues(alpha: 0.6),
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          busy
              ? 'Finish signing in in the browser window that opened. Google shows one screen for all permissions.'
              : 'Opens one Google screen to allow Gmail, Calendar, Drive and Tasks. You only do this once.',
          style: TextStyle(fontSize: 10.5, color: theme.fgMuted, height: 1.35),
        ),
      ],
    );
  }
}
