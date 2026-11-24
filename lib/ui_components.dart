import 'package:flutter/material.dart';

Duration motionDuration(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

class PressFeedback extends StatefulWidget {
  const PressFeedback({super.key, required this.child});
  final Widget child;
  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => pressed = true),
    onPointerUp: (_) => setState(() => pressed = false),
    onPointerCancel: (_) => setState(() => pressed = false),
    child: AnimatedScale(
      scale: pressed ? .985 : 1,
      duration: motionDuration(context, 100),
      child: widget.child,
    ),
  );
}

/// A one-time entrance; data refreshes do not replay it.
class ContentEntrance extends StatelessWidget {
  const ContentEntrance({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: motionDuration(context, 300),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (_, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 10 * (1 - value)),
        child: child,
      ),
    ),
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final done = [
      'Paid',
      'Resolved',
      'Completed',
      'Published',
      'Active',
      'Verified',
    ].contains(status);
    final active = ['Assigned', 'In progress', 'Under review'].contains(status);
    final alert = [
      'Overdue',
      'Service interruption',
      'Rejected',
    ].contains(status);
    final color = done
        ? const Color(0xFF176442)
        : alert
        ? const Color(0xFFA02C24)
        : active
        ? const Color(0xFF165D99)
        : const Color(0xFF78520A);
    return AnimatedSwitcher(
      duration: motionDuration(context, 180),
      child: Container(
        key: ValueKey(status),
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              done
                  ? Icons.check_circle_outline
                  : alert
                  ? Icons.info_outline
                  : active
                  ? Icons.autorenew
                  : Icons.schedule,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                status,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });
  final String title, message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

class LoadingCards extends StatefulWidget {
  const LoadingCards({super.key, this.count = 3});
  final int count;
  @override
  State<LoadingCards> createState() => _LoadingCardsState();
}

class _LoadingCardsState extends State<LoadingCards>
    with SingleTickerProviderStateMixin {
  late final AnimationController pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      pulse.stop();
      pulse.value = 1;
    } else {
      pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading records',
    liveRegion: true,
    child: ExcludeSemantics(
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, child) =>
            Opacity(opacity: .45 + .4 * pulse.value, child: child),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            widget.count,
            (_) => Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 22,
                    width: 150,
                    color: const Color(0xFFDCEBEC),
                  ),
                  const SizedBox(height: 18),
                  Container(height: 14, color: const Color(0xFFDCEBEC)),
                  const SizedBox(height: 10),
                  Container(
                    height: 14,
                    width: 200,
                    color: const Color(0xFFDCEBEC),
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

class RepairProgress extends StatelessWidget {
  const RepairProgress({super.key, required this.status});
  final String status;
  static const stages = ['Open', 'Assigned', 'In progress', 'Resolved'];
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Recorded repair progress',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      // Only mark the current recorded state: earlier stages may have been skipped.
      for (final stage in stages)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Icon(
                stage == status
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: stage == status
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              const SizedBox(width: 10),
              Text(
                stage,
                style: TextStyle(
                  fontWeight: stage == status
                      ? FontWeight.w700
                      : FontWeight.normal,
                ),
              ),
              if (stage == status) const Text(' · Current'),
            ],
          ),
        ),
    ],
  );
}

class SuccessNotice extends StatelessWidget {
  const SuccessNotice(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      TweenAnimationBuilder<double>(
        tween: Tween(begin: .5, end: 1),
        duration: motionDuration(context, 280),
        curve: Curves.easeOutBack,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: const Icon(Icons.check_circle, color: Colors.white),
      ),
      const SizedBox(width: 12),
      Expanded(child: Text(message)),
    ],
  );
}

const interruptionPrefix = '[Service interruption] ';
bool isInterruption(Object? title) =>
    title.toString().startsWith(interruptionPrefix);
String noticeTitle(Object? title) => isInterruption(title)
    ? title.toString().substring(interruptionPrefix.length)
    : title.toString();
