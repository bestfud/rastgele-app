import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_ui.dart';

enum AppGlyph {
  hook('assets/icons/hook.svg'),
  wave('assets/icons/wave.svg'),
  compass('assets/icons/compass.svg'),
  user('assets/icons/user.svg'),
  fish('assets/icons/fish.svg'),
  comment('assets/icons/comment.svg'),
  spot('assets/icons/spot.svg'),
  follow('assets/icons/follow.svg'),
  exact('assets/icons/exact.svg'),
  approx('assets/icons/approx.svg'),
  private('assets/icons/private.svg');

  const AppGlyph(this.assetPath);

  final String assetPath;
}

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.glyph, {
    super.key,
    this.size = 24,
    this.color,
  });

  final AppGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      glyph.assetPath,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? IconTheme.of(context).color ?? AppColors.textSecondary,
        BlendMode.srcIn,
      ),
    );
  }
}
