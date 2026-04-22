import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// MyWellWallet logo for the app bar (top left). Optional back button before it.
class AppBarLogo extends StatelessWidget {
  const AppBarLogo({
    super.key,
    this.showBackButton = false,
    this.onBack,
    this.logoHeight = 32,
  });

  final bool showBackButton;
  final VoidCallback? onBack;
  final double logoHeight;

  static const String _logoAsset = 'assets/icons/MyWellWallet.png';

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showBackButton)
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack ?? () => context.pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        Padding(
          padding: EdgeInsets.only(left: showBackButton ? 0 : 8),
          child: Image.asset(
            _logoAsset,
            height: logoHeight,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(Icons.medical_services, size: logoHeight, color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ],
    );
  }
}
