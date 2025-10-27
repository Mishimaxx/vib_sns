import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state/runtime_config.dart';

class DownloadQrScreen extends StatelessWidget {
  const DownloadQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final runtimeConfig = context.watch<StreetPassRuntimeConfig>();
    final downloadUrl = runtimeConfig.downloadUrl.trim();
    final hasUrl = downloadUrl.isNotEmpty;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u30c0\u30a6\u30f3\u30ed\u30fc\u30c9\u7528QR\u30b3\u30fc\u30c9'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (hasUrl)
              QrImageView(
                data: downloadUrl,
                size: 240,
                version: QrVersions.auto,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square),
              )
            else
              Container(
                width: 240,
                height: 240,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '\u4ed8\u5c5e\u306e\u30c0\u30a6\u30f3\u30ed\u30fc\u30c9URL\u304c\u8a2d\u5b9a\u3055\u308c\u3066\u3044\u307e\u305b\u3093\n--dart-define=DOWNLOAD_URL=... \u3067\u8a2d\u5b9a\u3057\u3066\u304f\u3060\u3055\u3044',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 24),
            SelectableText(
              hasUrl ? downloadUrl : '\u30c0\u30a6\u30f3\u30ed\u30fc\u30c9URL\u304c\u8a2d\u5b9a\u3055\u308c\u3066\u3044\u307e\u305b\u3093',
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '\u3053\u306eQR\u30b3\u30fc\u30c9\u3092\u64ae\u5f71\u3059\u308b\u3068\u3001\u6307\u5b9a\u3057\u305fURL\u304b\u3089\u30a2\u30d7\u30ea\u306e\u30c0\u30a6\u30f3\u30ed\u30fc\u30c9\u60c5\u5831\u306b\u79fb\u52d5\u3057\u307e\u3059\u3002',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
