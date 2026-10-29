import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/provider/chat/driver_chat_launcher_provider.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/views/pages/chat/driver_chat_navigation.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_chat_copy.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The app's single floating chat launcher.
///
/// Rendered once from `MaterialApp.builder`, above the Navigator, so it stays
/// put while routes are pushed and popped beneath it. No screen creates its
/// own: there is exactly one of these for the life of the app.
///
/// It owns no state of its own. Visibility comes from
/// [DriverChatLauncherProvider] and the badge from the shared
/// [DriverChatConversationsProvider]; this widget only draws them and drives
/// the poller's lifecycle.
class DriverChatBubble extends StatefulWidget {
  const DriverChatBubble({super.key});

  /// Vertical space this launcher occupies above the bottom safe-area inset:
  /// the bottom-navigation clearance plus the bubble itself.
  ///
  /// Screens that scroll their own content pad by at least this much so the
  /// last action never ends up underneath the launcher. Exposed rather than
  /// copied so a change to the geometry below cannot silently leave a screen
  /// short.
  static const double reservedBottomSpace =
      _DriverChatBubbleState._bottomNavigationClearance +
      _DriverChatBubbleState._diameter;

  @override
  State<DriverChatBubble> createState() => _DriverChatBubbleState();
}

class _DriverChatBubbleState extends State<DriverChatBubble>
    with WidgetsBindingObserver {
  static const double _diameter = 56;
  static const double _horizontalInset = 16;

  /// Clears the floating bottom-nav pill: brand strip, nav row and the card's
  /// own margins, measured from `CustomBottomNavBar`.
  static const double _bottomNavigationClearance = 118;

  bool _isOpening = false;
  bool _wasAuthenticated = false;

  /// Captured so lifecycle and disposal never reach for a BuildContext at a
  /// moment when it is not safe to read one.
  DriverChatConversationsProvider? _conversations;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _conversations = context.read<DriverChatConversationsProvider>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The launcher provider has not read storage yet on the very first frame;
      // this kicks off that read, and _syncPolling follows from its result.
      context.read<DriverChatLauncherProvider>().syncSession();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // This widget drives the poller, so the poller ends with it. In production
    // that is app teardown; the guarantee is that no timer outlives the tree.
    _conversations?.stopUnreadPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final conversations = _conversations;
    if (!mounted || conversations == null) return;

    if (state == AppLifecycleState.resumed) {
      // A no-op unless polling was started for a signed-in driver, so a
      // foreground event after logout cannot revive it.
      conversations.resumeUnreadPolling();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      conversations.pauseUnreadPolling();
    }
  }

  /// Starts the one unread poller when a driver signs in and stops it when the
  /// session ends. Called on every build of the authenticated-state selector,
  /// and idempotent, so repeated builds cannot stack timers.
  void _syncPolling(bool isAuthenticated) {
    if (isAuthenticated == _wasAuthenticated) {
      return;
    }
    _wasAuthenticated = isAuthenticated;

    final conversations = _conversations;
    if (conversations == null) {
      return;
    }
    if (isAuthenticated) {
      conversations.startUnreadPolling();
    } else {
      conversations.stopUnreadPolling();
    }
  }

  Future<void> _openConversations() async {
    final navigator = Nav.key.currentState;
    if (_isOpening || navigator == null) {
      return;
    }
    setState(() => _isOpening = true);
    try {
      // The observer hides the bubble as soon as this route is on top, so a
      // second push cannot be triggered from here while it is open.
      await DriverChatNavigation.openConversations(navigator);
      if (!mounted) return;
      // Coming back, take the server's figure rather than assuming what the
      // screen did to it.
      await context
          .read<DriverChatConversationsProvider>()
          .refreshUnreadCount();
    } finally {
      if (mounted) {
        setState(() => _isOpening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<DriverChatLauncherProvider, ({bool show, bool signedIn})>(
      selector:
          (_, launcher) => (
            show: launcher.shouldShow,
            signedIn: launcher.isAuthenticated,
          ),
      builder: (context, launcher, _) {
        _syncPolling(launcher.signedIn);
        if (!launcher.show) {
          return const SizedBox.shrink();
        }

        // The keyboard takes the space the bubble sits in, and covering an
        // input while someone types is worse than hiding the launcher.
        if (MediaQuery.viewInsetsOf(context).bottom > 0) {
          return const SizedBox.shrink();
        }

        return Selector<DriverChatConversationsProvider, int>(
          selector: (_, provider) => provider.globalUnreadCount,
          builder: (context, unreadCount, _) {
            return PositionedDirectional(
              // Directional, so the bubble sits on the natural trailing side in
              // both layouts instead of a mirrored LTR position.
              end: _horizontalInset,
              bottom:
                  _bottomNavigationClearance +
                  MediaQuery.paddingOf(context).bottom,
              child: _BubbleVisual(
                unreadCount: unreadCount < 0 ? 0 : unreadCount,
                isOpening: _isOpening,
                diameter: _diameter,
                onTap: _openConversations,
              ),
            );
          },
        );
      },
    );
  }
}

/// The launcher's appearance: one compact rounded-square brand control with
/// an optional unread badge.
///
/// Two one-shot animations, both quiet: the badge pops when the count rises,
/// and the whole control dips while pressed. Nothing animates on a loop —
/// a launcher that moves forever is noise, and it rebuilds every frame for
/// the life of the app.
class _BubbleVisual extends StatefulWidget {
  const _BubbleVisual({
    required this.unreadCount,
    required this.isOpening,
    required this.diameter,
    required this.onTap,
  });

  final int unreadCount;
  final bool isOpening;
  final double diameter;
  final VoidCallback onTap;

  @override
  State<_BubbleVisual> createState() => _BubbleVisualState();
}

class _BubbleVisualState extends State<_BubbleVisual>
    with SingleTickerProviderStateMixin {
  static const Duration _badgePopDuration = Duration(milliseconds: 260);
  static const Duration _pressDuration = Duration(milliseconds: 110);
  static const double _cornerRadius = 18;

  late final AnimationController _badgePop;
  late final Animation<double> _badgeScale;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _badgePop = AnimationController(vsync: this, duration: _badgePopDuration)
      // Rests at the end of the sequence, so a badge that is simply present
      // sits at its natural size instead of the 0.85 the sequence starts on.
      ..value = 1;
    _badgeScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.08), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 55),
    ]).animate(CurvedAnimation(parent: _badgePop, curve: Curves.easeOutCubic));
  }

  @override
  void didUpdateWidget(covariant _BubbleVisual oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only a rise is worth announcing. Reading messages lowers the count, and
    // animating that would draw the eye to something already handled.
    if (widget.unreadCount > oldWidget.unreadCount && widget.unreadCount > 0) {
      _badgePop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _badgePop.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = widget.unreadCount > 0;

    // The count is isolated in the Arabic label for the same reason the badge
    // forces its digits left-to-right: an unisolated number sitting between
    // Arabic words can be reordered against the surrounding text.
    final label =
        hasUnread
            ? chatCopy(
              context,
              'Open messages, ${widget.unreadCount} unread messages',
              'فتح الرسائل، ${isolateIdentifier('${widget.unreadCount}')} رسائل غير مقروءة',
            )
            : chatCopy(context, 'Open messages', 'فتح الرسائل');

    return Semantics(
      button: true,
      enabled: !widget.isOpening,
      label: label,
      tooltip: label,
      child: AnimatedScale(
        // Purely visual: it never sits between the pointer and the InkWell,
        // so the tap is delivered at once.
        scale: _isPressed ? 0.95 : 1,
        duration: _pressDuration,
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.isOpening ? null : widget.onTap,
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            borderRadius: BorderRadius.circular(_cornerRadius),
            child: Ink(
              key: const ValueKey<String>('driver-chat-launcher-surface'),
              width: widget.diameter,
              height: widget.diameter,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_cornerRadius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.gradient1, AppColors.primary],
                ),
                // One neutral shadow gives the control separation without a
                // coloured halo that can read as a second circular button.
                boxShadow: _elevation,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (widget.isOpening)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(
                      Icons.chat_bubble_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  if (!widget.isOpening && hasUnread)
                    PositionedDirectional(
                      top: -2,
                      end: -2,
                      child: ScaleTransition(
                        scale: _badgeScale,
                        child: _BubbleBadge(count: widget.unreadCount),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const List<BoxShadow> _elevation = [
    BoxShadow(color: Color(0x260F172A), blurRadius: 16, offset: Offset(0, 6)),
  ];
}

class _BubbleBadge extends StatelessWidget {
  const _BubbleBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';

    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xffE53935),
        borderRadius: BorderRadius.circular(10),
        // Separates the badge from the brand gradient underneath it.
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      // The count is already spoken in the button label; the bare digits
      // would merge into it and say it twice.
      child: ExcludeSemantics(
        child: Text(
          label,
          // Digits read left-to-right even in Arabic, so `99+` never becomes
          // `+99`.
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}
