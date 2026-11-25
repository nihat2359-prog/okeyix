import 'dart:math' as math;
import 'package:flutter/material.dart';

const _gold = Color(0xFFE5C585);
const _ivory = Color(0xFFF5E8CC);

class CampaignDialog extends StatelessWidget {
  const CampaignDialog({super.key, required this.imageUrl, this.title});
  final String imageUrl;
  final String? title;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final height = math.min(440.0, math.max(0.0, bounds.maxHeight - 24));
      final width = math.min(840.0, math.max(0.0, bounds.maxWidth - 32));
      final compact = height < 300 || width < 540;
      final gap = compact ? 12.0 : 24.0;
      final heading = title?.trim();
      void close() => Navigator.of(context).pop();
      return Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: const BoxConstraints(minWidth: 0),
        child: SizedBox(
          key: const ValueKey('campaign-panel'),
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xAAA68B58)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 28,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/lobby/lobby.png',
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xD9101C1D),
                          Color(0xC70A1918),
                          Color(0xF0081117),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(compact ? 12 : 20),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 6,
                          child: Container(
                            key: const ValueKey('campaign-art'),
                            decoration: const BoxDecoration(
                              gradient: RadialGradient(
                                colors: [Color(0x337D693E), Color(0x000B1719)],
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: imageUrl.startsWith('http')
                                  ? Image.network(
                                      imageUrl,
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const _ImageMessage(
                                                'Kampanya görseli yüklenemedi.',
                                              ),
                                    )
                                  : const _ImageMessage(
                                      'Kampanya görseli yok.',
                                    ),
                            ),
                          ),
                        ),
                        SizedBox(width: gap),
                        Container(
                          width: 1,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x00B99B62),
                                Color(0x66B99B62),
                                Color(0x00B99B62),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 48,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Image.asset(
                                          'assets/images/logo/okeyix_logo.png',
                                          width: compact ? 84 : 120,
                                          fit: BoxFit.contain,
                                          semanticLabel: 'Okeyix',
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Kapat',
                                      onPressed: close,
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        color: _gold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'DUYURU',
                                            style: TextStyle(
                                              color: _gold,
                                              fontSize: 11,
                                              letterSpacing: 2,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            heading != null &&
                                                    heading.isNotEmpty
                                                ? heading
                                                : 'Masadan haberler',
                                            style: TextStyle(
                                              color: _ivory,
                                              fontSize: compact ? 19 : 28,
                                              height: 1.15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFD0AF69),
                                    ),
                                    gradient: const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFFF0D69C),
                                        Color(0xFFC49B51),
                                      ],
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x44000000),
                                        offset: Offset(0, 3),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: TextButton(
                                    onPressed: close,
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF302419),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'TAMAM',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ImageMessage extends StatelessWidget {
  const _ImageMessage(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: _ivory),
    ),
  );
}
