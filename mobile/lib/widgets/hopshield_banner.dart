import 'package:flutter/material.dart';

MaterialBanner hopShieldBanner(BuildContext context, {required String message, bool blocked = false}) {
  return MaterialBanner(
    leading: Icon(blocked ? Icons.gpp_bad_outlined : Icons.gpp_maybe_outlined),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
        child: const Text('Dismiss'),
      ),
    ],
  );
}
