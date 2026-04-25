import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onComplete,
  });

  final Future<void> Function() onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _slides = <_OnboardingSlide>[
    _OnboardingSlide(
      title: 'Mera bul',
      subtitle: 'Yakınındaki en verimli balık noktalarını keşfet',
      accent: Color(0xFF5B8DEF),
      accentSoft: Color(0xFFEAF2FF),
      glow: Color(0x225B8DEF),
      illustration: _SlideIllustrationType.map,
    ),
    _OnboardingSlide(
      title: 'Doğru zamanı yakala',
      subtitle: 'Hava koşullarına göre en iyi av saatlerini gör',
      accent: Color(0xFF2FA36B),
      accentSoft: Color(0xFFE8F8EF),
      glow: Color(0x222FA36B),
      illustration: _SlideIllustrationType.score,
    ),
    _OnboardingSlide(
      title: 'Deneyim paylaş',
      subtitle: 'Diğer balıkçılarla meralarını ve avlarını paylaş',
      accent: Color(0xFFE3A23B),
      accentSoft: Color(0xFFFFF5E5),
      glow: Color(0x22E3A23B),
      illustration: _SlideIllustrationType.social,
    ),
  ];

  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _isCompleting = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (_isCompleting) {
      return;
    }

    setState(() {
      _isCompleting = true;
    });

    await widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLastSlide = _currentIndex == _slides.length - 1;
    final currentSlide = _slides[_currentIndex];

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8FAFD),
              Color(0xFFF2F5FA),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  children: [
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _slides.length,
                        onPageChanged: (index) {
                          setState(() {
                            _currentIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          final slide = _slides[index];
                          return _OnboardingSlideCard(slide: slide);
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _slides.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: index == _currentIndex ? 30 : 10,
                          height: 10,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: index == _currentIndex
                                ? currentSlide.accent
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: isLastSlide
                          ? Container(
                              key: const ValueKey('start'),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: currentSlide.glow,
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: FilledButton(
                                onPressed: _isCompleting ? null : _complete,
                                style: FilledButton.styleFrom(
                                  backgroundColor: currentSlide.accent,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(56),
                                ),
                                child: Text(
                                  _isCompleting ? 'Hazırlanıyor...' : 'Hadi başlayalım',
                                ),
                              ),
                            )
                          : SizedBox(
                              key: const ValueKey('hint'),
                              width: double.infinity,
                              child: Text(
                                'Devam etmek için kaydır',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlideCard extends StatelessWidget {
  const _OnboardingSlideCard({
    required this.slide,
  });

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Card(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                slide.accentSoft.withValues(alpha: 0.85),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                Expanded(
                  flex: 6,
                  child: Center(
                    child: _IllustrationFrame(slide: slide),
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        slide.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        slide.subtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
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
  }
}

class _IllustrationFrame extends StatelessWidget {
  const _IllustrationFrame({
    required this.slide,
  });

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                slide.glow,
                slide.accentSoft.withValues(alpha: 0.18),
                Colors.transparent,
              ],
            ),
          ),
        ),
        Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          child: switch (slide.illustration) {
            _SlideIllustrationType.map => _MapIllustration(slide: slide),
            _SlideIllustrationType.score => _ScoreIllustration(slide: slide),
            _SlideIllustrationType.social => _SocialIllustration(slide: slide),
          },
        ),
      ],
    );
  }
}

class _MapIllustration extends StatelessWidget {
  const _MapIllustration({
    required this.slide,
  });

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: slide.accentSoft,
                borderRadius: BorderRadius.circular(30),
              ),
              child: CustomPaint(
                painter: _MapPatternPainter(
                  lineColor: slide.accent.withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 52,
          top: 84,
          child: _MiniPin(
            color: slide.accent.withValues(alpha: 0.75),
            size: 24,
          ),
        ),
        Positioned(
          right: 58,
          top: 66,
          child: _MiniPin(
            color: slide.accent.withValues(alpha: 0.45),
            size: 18,
          ),
        ),
        Positioned(
          right: 74,
          bottom: 68,
          child: _MiniPin(
            color: slide.accent.withValues(alpha: 0.62),
            size: 20,
          ),
        ),
        Center(
          child: Container(
            width: 94,
            height: 94,
            decoration: BoxDecoration(
              color: slide.accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: slide.glow,
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.place_rounded,
              color: Colors.white,
              size: 48,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScoreIllustration extends StatelessWidget {
  const _ScoreIllustration({
    required this.slide,
  });

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          left: 34,
          top: 44,
          child: _MetricChip(
            label: 'Basınç uygun',
            background: Colors.white.withValues(alpha: 0.92),
            foreground: slide.accent,
          ),
        ),
        Positioned(
          right: 28,
          bottom: 50,
          child: _MetricChip(
            label: 'Rüzgar hafif',
            background: Colors.white.withValues(alpha: 0.92),
            foreground: slide.accent,
          ),
        ),
        SizedBox(
          width: 170,
          height: 170,
          child: CustomPaint(
            painter: _GaugePainter(
              accent: slide.accent,
              track: slide.accent.withValues(alpha: 0.12),
              progress: 0.85,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '85',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: slide.accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Çok iyi',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SocialIllustration extends StatelessWidget {
  const _SocialIllustration({
    required this.slide,
  });

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Transform.rotate(
        angle: -0.05,
        child: Container(
          width: 176,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: slide.glow,
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: slide.accentSoft,
                    child: Icon(
                      Icons.person_rounded,
                      size: 20,
                      color: slide.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kıyı avı',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Bugün hareket var',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                height: 90,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      slide.accentSoft,
                      Colors.white,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(
                  child: Icon(
                    Icons.waves_rounded,
                    size: 42,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.favorite_rounded, color: slide.accent, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '24',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Icon(
                    Icons.mode_comment_outlined,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '8',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPin extends StatelessWidget {
  const _MiniPin({
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.place_rounded,
      color: color,
      size: size,
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.accent,
    required this.track,
    required this.progress,
  });

  final Color accent;
  final Color track;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 16.0;
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) / 2) - strokeWidth;
    const startAngle = math.pi * 0.78;
    const sweepAngle = math.pi * 1.44;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.track != track ||
        oldDelegate.progress != progress;
  }
}

class _MapPatternPainter extends CustomPainter {
  const _MapPatternPainter({
    required this.lineColor,
  });

  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final first = Path()
      ..moveTo(size.width * 0.08, size.height * 0.28)
      ..quadraticBezierTo(
        size.width * 0.34,
        size.height * 0.18,
        size.width * 0.52,
        size.height * 0.38,
      )
      ..quadraticBezierTo(
        size.width * 0.70,
        size.height * 0.55,
        size.width * 0.90,
        size.height * 0.42,
      );

    final second = Path()
      ..moveTo(size.width * 0.18, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.34,
        size.height * 0.64,
        size.width * 0.48,
        size.height * 0.70,
      )
      ..quadraticBezierTo(
        size.width * 0.66,
        size.height * 0.76,
        size.width * 0.82,
        size.height * 0.60,
      );

    final vertical = Path()
      ..moveTo(size.width * 0.34, size.height * 0.10)
      ..quadraticBezierTo(
        size.width * 0.42,
        size.height * 0.34,
        size.width * 0.30,
        size.height * 0.86,
      );

    canvas.drawPath(first, paint);
    canvas.drawPath(second, paint);
    canvas.drawPath(vertical, paint);
  }

  @override
  bool shouldRepaint(covariant _MapPatternPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor;
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.accentSoft,
    required this.glow,
    required this.illustration,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final Color accentSoft;
  final Color glow;
  final _SlideIllustrationType illustration;
}

enum _SlideIllustrationType {
  map,
  score,
  social,
}
