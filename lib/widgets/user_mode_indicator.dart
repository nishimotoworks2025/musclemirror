import 'dart:async';
import 'package:flutter/material.dart';
import '../services/user_mode_service.dart';
import '../screens/login_screen.dart';
import '../screens/subscription_page.dart';

/// A chip widget that displays the current user mode (Pro/Free/Guest)
/// Tapping on it navigates to the appropriate screen:
/// - Guest -> Login screen
/// - Free -> Subscription page
/// - Pro -> Settings sheet (handled by callback)
class UserModeIndicator extends StatefulWidget {
  final VoidCallback? onProTap;

  const UserModeIndicator({super.key, this.onProTap});

  @override
  State<UserModeIndicator> createState() => _UserModeIndicatorState();
}

class _UserModeIndicatorState extends State<UserModeIndicator> {
  final UserModeService _userModeService = UserModeService();
  StreamSubscription<UserMode>? _modeSubscription;

  @override
  void initState() {
    super.initState();
    _modeSubscription = _userModeService.modeStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _modeSubscription?.cancel();
    super.dispose();
  }

  void _handleTap() {
    final mode = _userModeService.currentMode;

    switch (mode) {
      case UserMode.guest:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
        break;
      case UserMode.free:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SubscriptionPage()));
        break;
      case UserMode.pro:
        widget.onProTap?.call();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayMode = _userModeService.currentMode;

    Color backgroundColor;
    Color textColor;
    IconData icon;
    String label;

    switch (displayMode) {
      case UserMode.guest:
        backgroundColor = theme.colorScheme.surfaceContainerHighest;
        textColor = theme.colorScheme.onSurfaceVariant;
        icon = Icons.person_outline;
        label = 'Guest';
        break;
      case UserMode.free:
        backgroundColor = Colors.blue.withAlpha(30);
        textColor = Colors.blue.shade700;
        icon = Icons.person;
        label = 'Free';
        break;
      case UserMode.pro:
        backgroundColor = Colors.amber.shade600;
        textColor = Colors.white;
        icon = Icons.workspace_premium;
        label = 'Pro';
        break;
    }

    return GestureDetector(
      onTap: _handleTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: textColor.withAlpha(180), width: 2),
          boxShadow: [
            BoxShadow(
              color: backgroundColor.withAlpha(100),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: textColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
