import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/fa_theme.dart';

/// Logo files by model family (assets/folder_agent/ai-logos/).
const _logos = {
  'smollm': 'smollm.webp',
  'deepseek': 'deepseek.png',
  'granite': 'granite.svg',
  'mistral': 'mistral.webp',
  'gemma': 'gemma.webp',
  'llama': 'llama.webp',
  'qwen': 'qwen.png',
  'phi': 'phi.webp',
  'lfm': 'lfm.png',
};

/// Model family of an Ollama id or catalog family ("qwen3:4b" → "qwen"; unknown → "custom").
String modelFamily(String idOrFamily) {
  final id = idOrFamily.toLowerCase();
  for (final family in _logos.keys) {
    if (id.contains(family)) return family;
  }
  return 'custom';
}

/// The logo of a chat model: its family's mark, a cloud for Gemini.
class ModelLogo extends StatelessWidget {
  final String modelId;
  final bool cloud;
  final double size;
  const ModelLogo(this.modelId, {super.key, this.cloud = false, this.size = 18});

  @override
  Widget build(BuildContext context) {
    if (cloud) return Icon(Icons.cloud_outlined, size: size, color: context.fa.mutedForeground);
    final path = 'assets/folder_agent/ai-logos/${_logos[modelFamily(modelId)] ?? 'custom.webp'}';
    final img = path.endsWith('.svg')
        ? SvgPicture.asset(path, width: size, height: size, fit: BoxFit.contain)
        : Image.asset(path, width: size, height: size, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
    return ClipRRect(borderRadius: BorderRadius.circular(size * 0.22), child: img);
  }
}
