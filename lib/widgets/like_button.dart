import 'package:flutter/material.dart';

enum LikeButtonVariant { hero, chip }

class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.isLiked,
    required this.likeCount,
    required this.onPressed,
    this.variant = LikeButtonVariant.hero,
    this.maxWidth,
    this.maxHeight,
  });

  final bool isLiked;
  final int likeCount;
  final VoidCallback onPressed;
  final LikeButtonVariant variant;
  final double? maxWidth;
  final double? maxHeight;

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final Animation<double> _pulse =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo);

  @override
  void initState() {
    super.initState();
    if (widget.isLiked) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant LikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isLiked && widget.isLiked) {
      _controller.forward(from: 0);
    } else if (oldWidget.isLiked && !widget.isLiked) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.variant) {
      case LikeButtonVariant.hero:
        return _HeroLikeButton(
          isLiked: widget.isLiked,
          likeCount: widget.likeCount,
          onPressed: _handlePressed,
          pulse: _pulse,
          maxWidth: widget.maxWidth,
          maxHeight: widget.maxHeight,
        );
      case LikeButtonVariant.chip:
        return _ChipLikeButton(
          isLiked: widget.isLiked,
          likeCount: widget.likeCount,
          onPressed: _handlePressed,
          pulse: _pulse,
        );
    }
  }

  void _handlePressed() {
    final willLike = !widget.isLiked;
    widget.onPressed();
    if (willLike) {
      _controller.forward(from: 0);
    } else {
      _controller.reverse();
    }
  }
}

class _HeroLikeButton extends StatelessWidget {
  const _HeroLikeButton({
    required this.isLiked,
    required this.likeCount,
    required this.onPressed,
    required this.pulse,
    this.maxWidth,
    this.maxHeight,
  });

  final bool isLiked;
  final int likeCount;
  final VoidCallback onPressed;
  final Animation<double> pulse;
  final double? maxWidth;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final gradient = isLiked
        ? const LinearGradient(
            colors: [Color(0xFFFF5F8F), Color(0xFFFF8F70)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.primary.withValues(alpha: 0.75),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    final shadowColor =
        isLiked ? const Color(0xFFFF5F8F) : theme.colorScheme.primary;

    final height = ((maxHeight ?? 74).clamp(0, 74)).toDouble();
    final double horizontalPadding = height * 0.32;
    final double verticalPadding = height * 0.2;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: height,
        maxWidth: maxWidth ?? double.infinity,
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: pulse,
            builder: (context, child) {
              final value = pulse.value;
              final size = (height * 1.3) + (height * 0.6) * value;
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFF7AAD).withValues(
                          alpha: (0.35 - value * 0.3).clamp(0.05, 0.35)),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onPressed,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: gradient,
                  boxShadow: [
                    BoxShadow(
                      color: shadowColor.withValues(alpha: 0.45),
                      blurRadius: 18 + height * 0.2,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutBack,
                      scale: isLiked ? 1.1 : 1,
                      child: Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: height * 0.375,
                      ),
                    ),
                    SizedBox(width: height * 0.22),
                    Text(
                      isLiked
                          ? '\u3044\u3044\u306d\u6e08\u307f'
                          : '\u3044\u3044\u306d\u3059\u308b',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        fontSize: height * 0.28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -10,
            right: -10,
            child: AnimatedBuilder(
              animation: pulse,
              builder: (context, child) {
                final opacity = (1 - pulse.value).clamp(0.0, 1.0);
                final scale = 1 + pulse.value * 0.4;
                return Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipLikeButton extends StatelessWidget {
  const _ChipLikeButton({
    required this.isLiked,
    required this.likeCount,
    required this.onPressed,
    required this.pulse,
  });

  final bool isLiked;
  final int likeCount;
  final VoidCallback onPressed;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color baseColor =
        isLiked ? const Color(0xFFFF5F8F) : theme.colorScheme.primary;
    final Color textColor =
        isLiked ? Colors.white : theme.colorScheme.onPrimaryContainer;

    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final value = pulse.value;
        final glowOpacity = (0.3 * (1 - value)).clamp(0.0, 0.3);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: baseColor.withValues(alpha: glowOpacity),
                        blurRadius: 18 + value * 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onPressed,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutQuad,
                  constraints: const BoxConstraints(minWidth: 132),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: isLiked
                        ? const LinearGradient(
                            colors: [Color(0xFFFF5F8F), Color(0xFFFF8F70)],
                          )
                        : LinearGradient(
                            colors: [
                              theme.colorScheme.surfaceContainerHighest,
                              theme.colorScheme.surface,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    border: Border.all(
                      color: isLiked
                          ? baseColor.withValues(alpha: 0.7)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        size: 18,
                        color: isLiked ? Colors.white : baseColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isLiked
                            ? '\u3044\u3044\u306d\u6e08\u307f'
                            : '\u3044\u3044\u306d',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isLiked ? textColor : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: isLiked ? 0.25 : 0.5,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          likeCount.toString(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isLiked ? textColor : baseColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class FollowButton extends StatefulWidget {
  const FollowButton({
    super.key,
    required this.isFollowing,
    required this.onPressed,
    this.variant = LikeButtonVariant.hero,
    this.maxWidth,
    this.maxHeight,
  });

  final bool isFollowing;
  final VoidCallback onPressed;
  final LikeButtonVariant variant;
  final double? maxWidth;
  final double? maxHeight;

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  late final Animation<double> _pulse =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo);

  @override
  void initState() {
    super.initState();
    if (widget.isFollowing) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isFollowing && widget.isFollowing) {
      _controller.forward(from: 0);
    } else if (oldWidget.isFollowing && !widget.isFollowing) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.variant) {
      case LikeButtonVariant.hero:
        return _HeroFollowButton(
          pulse: _pulse,
          isFollowing: widget.isFollowing,
          onPressed: _handlePressed,
          maxWidth: widget.maxWidth,
          maxHeight: widget.maxHeight,
        );
      case LikeButtonVariant.chip:
        return _ChipFollowButton(
          pulse: _pulse,
          isFollowing: widget.isFollowing,
          onPressed: _handlePressed,
        );
    }
  }

  void _handlePressed() {
    final willFollow = !widget.isFollowing;
    widget.onPressed();
    if (willFollow) {
      _controller.forward(from: 0);
    } else {
      _controller.reverse();
    }
  }
}

class _HeroFollowButton extends StatelessWidget {
  const _HeroFollowButton({
    required this.pulse,
    required this.isFollowing,
    required this.onPressed,
    this.maxWidth,
    this.maxHeight,
  });

  final Animation<double> pulse;
  final bool isFollowing;
  final VoidCallback onPressed;
  final double? maxWidth;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = isFollowing
        ? const LinearGradient(
            colors: [Color(0xFF4F7BFF), Color(0xFF5CEFFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              theme.colorScheme.secondary,
              theme.colorScheme.secondary.withValues(alpha: 0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    final Color highlight =
        isFollowing ? const Color(0xFF4F7BFF) : theme.colorScheme.secondary;

    final height = ((maxHeight ?? 74).clamp(0, 74)).toDouble();
    final double horizontalPadding = height * 0.3;
    final double verticalPadding = height * 0.2;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: height,
        maxWidth: maxWidth ?? double.infinity,
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: pulse,
            builder: (context, child) {
              final value = pulse.value;
              final size = (height * 1.2) + (height * 0.6) * value;
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      highlight.withValues(
                        alpha: (0.32 - value * 0.26).clamp(0.05, 0.32),
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onPressed,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: gradient,
                  boxShadow: [
                    BoxShadow(
                      color: highlight.withValues(alpha: 0.32),
                      blurRadius: 18 + height * 0.18,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      scale: isFollowing ? 1.08 : 1,
                      child: Icon(
                        isFollowing ? Icons.check : Icons.person_add_alt_1,
                        color: Colors.white,
                        size: height * 0.35,
                      ),
                    ),
                    SizedBox(width: height * 0.2),
                    Text(
                      isFollowing
                          ? '\u30d5\u30a9\u30ed\u30fc\u4e2d'
                          : '\u30d5\u30a9\u30ed\u30fc\u3059\u308b',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        fontSize: height * 0.28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipFollowButton extends StatelessWidget {
  const _ChipFollowButton({
    required this.pulse,
    required this.isFollowing,
    required this.onPressed,
  });

  final Animation<double> pulse;
  final bool isFollowing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const Color activeColor = Color(0xFF4F7BFF);
    final Color inactiveColor = theme.colorScheme.secondary;
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final value = pulse.value;
        final glow = (0.26 * (1 - value)).clamp(0.0, 0.26);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: (isFollowing ? activeColor : inactiveColor)
                            .withValues(alpha: glow),
                        blurRadius: 16 + value * 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onPressed,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutQuad,
                  constraints: const BoxConstraints(minWidth: 128),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: isFollowing
                        ? const LinearGradient(
                            colors: [Color(0xFF4F7BFF), Color(0xFF5CEFFF)],
                          )
                        : LinearGradient(
                            colors: [
                              theme.colorScheme.surfaceContainerHighest,
                              theme.colorScheme.surface,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    border: Border.all(
                      color: (isFollowing ? activeColor : inactiveColor)
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isFollowing ? Icons.check : Icons.person_add_alt_1,
                        size: 18,
                        color: isFollowing ? Colors.white : activeColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isFollowing
                            ? '\u30d5\u30a9\u30ed\u30fc\u4e2d'
                            : '\u30d5\u30a9\u30ed\u30fc',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isFollowing ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
