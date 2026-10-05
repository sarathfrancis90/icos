import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_urls.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/external_links.dart';

/// "By continuing, you agree to our Terms of Service and Privacy Policy."
/// as one centred, naturally wrapping sentence, with each document a
/// separately tappable, separately announced link.
///
/// The links are plain inline text spans, so lines keep their natural height
/// and the closing full stop wraps together with "Privacy Policy" (it cannot
/// land on a line of its own). Each link's touch target is widened to
/// [AppSizes.minTouchTarget] by hit-test behaviour, not by padding the text:
/// a tap within 22dp above or below a link opens it.
class LegalConsentText extends StatefulWidget {
  const LegalConsentText({super.key, this.onOpen = openExternalUrl});

  /// Opens a url; returns false when it could not be opened. Injectable so
  /// tests do not reach for the platform.
  final Future<bool> Function(String url) onOpen;

  @override
  State<LegalConsentText> createState() => _LegalConsentTextState();
}

class _Link {
  _Link(this.label, this.url, this.start, this.recognizer);

  final String label;
  final String url;

  /// Offset of [label] in the sentence's plain text.
  final int start;
  final TapGestureRecognizer recognizer;

  int get end => start + label.length;
}

class _LegalConsentTextState extends State<LegalConsentText> {
  static const _sentenceEnd = '.';

  final _textKey = GlobalKey();
  late final List<_Link> _links;
  Offset? _pointerDown;

  @override
  void initState() {
    super.initState();
    var offset = AppStrings.consentPrefix.length;
    _Link make(String label, String url) {
      final link = _Link(label, url, offset, TapGestureRecognizer());
      link.recognizer.onTap = () => _open(url);
      offset += label.length;
      return link;
    }

    final terms = make(AppStrings.termsOfService, kTermsUrl);
    offset += AppStrings.consentAnd.length;
    final privacy = make(AppStrings.privacyPolicy, kPrivacyPolicyUrl);
    _links = [terms, privacy];
  }

  @override
  void dispose() {
    for (final link in _links) {
      link.recognizer.dispose();
    }
    super.dispose();
  }

  Future<void> _open(String url) async {
    final ok = await widget.onOpen(url);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.couldNotOpen(url))));
    }
  }

  RenderParagraph? _paragraph() {
    RenderParagraph? find(RenderObject object) {
      if (object is RenderParagraph) return object;
      RenderParagraph? found;
      object.visitChildren((child) => found ??= find(child));
      return found;
    }

    final root = _textKey.currentContext?.findRenderObject();
    return root == null ? null : find(root);
  }

  /// A tap that missed every link's own text but landed within the 44dp band
  /// centred on one opens that link (the nearest, when bands overlap).
  void _onPointerUp(PointerUpEvent event) {
    final down = _pointerDown;
    _pointerDown = null;
    if (down == null || (event.localPosition - down).distance > kTouchSlop) {
      return;
    }
    final paragraph = _paragraph();
    if (paragraph == null || !paragraph.hasSize) return;
    final local = paragraph.globalToLocal(event.position);
    const half = AppSizes.minTouchTarget / 2;

    // On a link's own text the span's recognizer handles the tap; on any
    // other text (the words of an adjacent line) nothing happens.
    for (final link in _links) {
      for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: link.start, extentOffset: link.end),
      )) {
        if (box.toRect().inflate(1).contains(local)) return;
      }
    }
    final textLength = paragraph.text.toPlainText().length;
    for (final box in paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: textLength),
    )) {
      if (box.toRect().contains(local)) return;
    }

    // Otherwise a tap just above or below a link, horizontally over it, opens
    // it (the nearest, when bands overlap).
    _Link? best;
    var bestDistance = double.infinity;
    for (final link in _links) {
      for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: link.start, extentOffset: link.end),
      )) {
        final rect = box.toRect();
        final band = Rect.fromLTRB(
          rect.left,
          rect.center.dy - half,
          rect.right,
          rect.center.dy + half,
        );
        if (!band.contains(local)) continue;
        final distance = (local.dy - rect.center.dy).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          best = link;
        }
      }
    }
    if (best != null) _open(best.url);
  }

  @override
  Widget build(BuildContext context) {
    final base = AppTheme.darkTheme.textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondaryDark,
    );
    final linkStyle = base?.copyWith(
      color: AppColors.purpleLight,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.purpleLight,
    );
    final terms = _links[0];
    final privacy = _links[1];
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _pointerDown = event.localPosition,
      onPointerUp: _onPointerUp,
      onPointerCancel: (_) => _pointerDown = null,
      child: Padding(
        // Room above and below for the links' 44dp bands (the text's own line
        // height is unchanged); the band never overlaps a neighbouring widget.
        padding: const EdgeInsetsDirectional.symmetric(
          vertical: (AppSizes.minTouchTarget - 16) / 2,
        ),
        child: Text.rich(
          key: _textKey,
          TextSpan(
            style: base,
            children: [
              const TextSpan(text: AppStrings.consentPrefix),
              TextSpan(
                text: terms.label,
                style: linkStyle,
                recognizer: terms.recognizer,
              ),
              const TextSpan(text: AppStrings.consentAnd),
              TextSpan(
                text: privacy.label,
                style: linkStyle,
                recognizer: privacy.recognizer,
              ),
              const TextSpan(text: _sentenceEnd),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
