import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

abstract final class UtilityStyle {
  static const blue = Color(0xFF1A4FD6);
  static const background = Color(0xFFF6F9FC);
  static const border = Color(0xFFE1E6EB);
  static const title = TextStyle(
    fontFamily: 'DM Sans',
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: Color(0xFF172536),
    height: 1.2,
    letterSpacing: -.4,
  );
  static const section = TextStyle(
    fontFamily: 'DM Sans',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Color(0xFF172536),
    height: 1.3,
  );
  static const body = TextStyle(
    fontFamily: 'DM Sans',
    fontSize: 15,
    fontFamilyFallback: ['Currency Symbols'],
    fontWeight: FontWeight.w400,
    color: Color(0xFF172536),
    height: 1.5,
  );
  static const metadata = TextStyle(
    fontFamily: 'DM Sans',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: Color(0xFF526077),
    height: 1.4,
  );
}

/// Content-sized header: title wrapping determines its height at any text scale.
class UtilityAppBar extends StatelessWidget implements PreferredSizeWidget {
  const UtilityAppBar({super.key, required this.title, this.actions});
  final Widget title;
  final List<Widget>? actions;
  @override
  Size get preferredSize => const Size.fromHeight(64);
  @override
  Widget build(BuildContext context) {
    final back = Navigator.of(context).canPop();
    final heading = Semantics(
      header: true,
      namesRoute: true,
      child: title is Text
          ? Text(
              (title as Text).data ?? '',
              style: UtilityStyle.title,
              softWrap: true,
            )
          : title,
    );
    final large = MediaQuery.textScalerOf(context).scale(26) > 39;
    return Material(
      color: UtilityStyle.background,
      child: SafeArea(
        bottom: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: large
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (back || actions?.isNotEmpty == true) ...[
                          Row(
                            children: [
                              if (back) const BackButton(),
                              const Spacer(),
                              ...?actions,
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        heading,
                      ],
                    )
                  : Row(
                      children: [
                        if (back) ...[
                          const BackButton(),
                          const SizedBox(width: 8),
                        ],
                        Expanded(child: heading),
                        if (actions != null) ...[
                          const SizedBox(width: 8),
                          ...actions!,
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Applied only to signed-in screens, leaving authentication and maps intact.
class UtilityScaffold extends StatelessWidget {
  const UtilityScaffold({
    super.key,
    this.appBar,
    this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.extendBody = false,
  });
  final PreferredSizeWidget? appBar;
  final Widget? body, bottomNavigationBar, floatingActionButton;
  final bool extendBody;

  static ThemeData themeFor(BuildContext context) {
    const blue = Color(0xFF1A4FD6);
    const text = Color(0xFF172536);
    const border = Color(0xFFE1E6EB);
    final base = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF6F9FC),
      colorScheme: base.colorScheme.copyWith(
        primary: blue,
        secondary: blue,
        onSurface: text,
        primaryContainer: const Color(0xFFEDF2FF),
        outline: border,
        outlineVariant: border,
      ),
      textTheme: base.textTheme.copyWith(
        bodyLarge: UtilityStyle.body,
        bodyMedium: UtilityStyle.body,
        bodySmall: UtilityStyle.metadata,
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 26,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 26,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: const Color(0xFFF6F9FC),
        foregroundColor: text,
        titleTextStyle: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: text,
          letterSpacing: -.4,
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        selectedColor: const Color(0xFFEDF2FF),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          shape: shape,
          textStyle: const TextStyle(
            fontFamily: 'DM Sans',
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(48, 48),
          shape: shape,
          side: const BorderSide(color: border),
          textStyle: const TextStyle(
            fontFamily: 'DM Sans',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: blue,
          minimumSize: const Size(48, 48),
          shape: shape,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: blue,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: const Color(0xFFF2F5F9),
        contentPadding: const EdgeInsets.all(16),
        helperStyle: UtilityStyle.metadata,
        helperMaxLines: 8,
        errorMaxLines: 8,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: base.colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: base.colorScheme.error, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: blue, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bar = appBar is UtilityAppBar ? appBar : null;
    final content = body == null
        ? const SizedBox.shrink()
        : Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: SizedBox(width: double.infinity, child: body),
            ),
          );
    return Theme(
      data: themeFor(context),
      child: Scaffold(
        appBar: bar == null ? appBar : null,
        body: bar == null
            ? content
            : Column(
                children: [
                  bar,
                  Expanded(child: content),
                ],
              ),
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
        extendBody: extendBody,
      ),
    );
  }
}

class UtilitySurface extends StatelessWidget {
  const UtilitySurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Theme(data: UtilityScaffold.themeFor(context), child: child);
}

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
    final neutral = ['Closed', 'Inactive', 'Draft'].contains(status);
    final alert = [
      'Overdue',
      'Service interruption',
      'Rejected',
    ].contains(status);
    final color = neutral
        ? const Color(0xFF526077)
        : done
        ? const Color(0xFF176442)
        : alert
        ? const Color(0xFFA02C24)
        : active
        ? const Color(0xFF1A4FD6)
        : const Color(0xFF78520A);
    return AnimatedSwitcher(
      duration: motionDuration(context, 180),
      child: Container(
        key: ValueKey(status),
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              done
                  ? CupertinoIcons.checkmark_circle
                  : alert
                  ? CupertinoIcons.info_circle
                  : active
                  ? CupertinoIcons.arrow_2_circlepath
                  : CupertinoIcons.clock,
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
    this.icon = CupertinoIcons.tray,
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
          Icon(
            icon,
            size: 30,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
                    color: const Color(0xFFE5E7EB),
                  ),
                  const SizedBox(height: 18),
                  Container(height: 14, color: const Color(0xFFE5E7EB)),
                  const SizedBox(height: 10),
                  Container(
                    height: 14,
                    width: 200,
                    color: const Color(0xFFE5E7EB),
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
                    ? CupertinoIcons.largecircle_fill_circle
                    : CupertinoIcons.circle,
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
                      ? FontWeight.w600
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
        child: const Icon(
          CupertinoIcons.checkmark_circle_fill,
          color: Colors.white,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(child: Text(message)),
    ],
  );
}

const interruptionPrefix = '[Service interruption] ';

/// Scales a complete currency amount together so decimals never wrap separately.
class AmountText extends StatelessWidget {
  const AmountText(
    this.amount, {
    super.key,
    this.fontSize = 32,
    this.color,
    this.letterSpacing = -.8,
  });
  final String amount;
  final double fontSize;
  final Color? color;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Text(
      amount,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        color: color ?? Theme.of(context).colorScheme.primary,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: letterSpacing,
      ),
    ),
  );
}

/// Keeps the essential record information visible and supporting details nearby.
class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.summary,
    required this.details,
    this.detailsLabel = 'Details',
    this.action,
  });

  final Widget summary;
  final List<Widget> details;
  final String detailsLabel;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          summary,
          const SizedBox(height: 16),
          const Divider(height: 1),
          ExpansionTile(
            initiallyExpanded: true,
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            title: Text(
              detailsLabel,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            children: details,
          ),
          if (action != null) ...[action!, const SizedBox(height: 12)],
        ],
      ),
    ),
  );
}

String recordDate(Object? value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return 'Date unavailable';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

Future<void> showPaymentGuidance(
  BuildContext context, {
  required String accountNumber,
  required String billNumber,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => UtilitySurface(
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Payment instructions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            const Text(
              'Maramag Water District',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Contact the district for accepted payment channels and requirements.',
            ),
            const Divider(height: 32),
            Text('Account $accountNumber'),
            const SizedBox(height: 8),
            Text('Bill $billNumber'),
            const SizedBox(height: 20),
            const Text(
              'Use these references when paying. Keep your official receipt. '
              'Payments appear in the app after district personnel verify and record them.',
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  ),
);

bool isInterruption(Object? title) =>
    title.toString().startsWith(interruptionPrefix);
String noticeTitle(Object? title) => isInterruption(title)
    ? title.toString().substring(interruptionPrefix.length)
    : title.toString();
