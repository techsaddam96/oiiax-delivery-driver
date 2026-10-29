import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/views/pages/chat/driver_chat_navigation.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_chat_copy.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_chat_header.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_conversation_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Driver's conversation list.
///
/// Reads [DriverChatConversationsProvider], which is registered once in
/// `main.dart` — this screen does not own it, so the same list and the same
/// global unread figure are shared with whatever else needs them later.
class DriverConversationsPage extends StatefulWidget {
  const DriverConversationsPage({super.key, this.repository});

  /// Handed to the thread this screen opens. Production leaves it null, so the
  /// thread builds its own service.
  @visibleForTesting
  final DriverChatRepository? repository;

  @override
  State<DriverConversationsPage> createState() =>
      _DriverConversationsPageState();
}

class _DriverConversationsPageState extends State<DriverConversationsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<DriverChatConversationsProvider>();
      // The provider survives this screen, so a rebuild must not refetch a list
      // that is already loaded.
      if (provider.state == DriverChatConversationsState.initial) {
        unawaited(provider.loadInitial());
      }
      unawaited(provider.refreshUnreadCount());
    });
  }

  Future<void> _openConversation(int index) async {
    final provider = context.read<DriverChatConversationsProvider>();
    if (index >= provider.conversations.length) return;

    await DriverChatNavigation.openConversation(
      context,
      conversation: provider.conversations[index],
      repository: widget.repository,
    );
    if (!mounted) return;
    // The thread marks messages read while it is open; re-reading the global
    // figure on the way back keeps the badge authoritative rather than derived.
    unawaited(provider.refreshUnreadCount());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF6F8FC),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Consumer<DriverChatConversationsProvider>(
              builder: (context, provider, _) => DriverChatHeader(
                title: chatCopy(context, 'Conversations', 'المحادثات'),
                subtitle: chatCopy(
                  context,
                  'Messages with operations and support',
                  'الرسائل مع فريق العمليات والدعم',
                ),
                badgeCount: provider.unreadCount,
              ),
            ),
            Expanded(
              child: Consumer<DriverChatConversationsProvider>(
                builder: (context, provider, _) => _buildBody(provider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(DriverChatConversationsProvider provider) {
    if (provider.state == DriverChatConversationsState.initial ||
        provider.isLoading) {
      return const _ConversationListSkeleton();
    }

    if (provider.state == DriverChatConversationsState.error &&
        provider.conversations.isEmpty) {
      return _ConversationsErrorState(
        isSessionError: provider.errorMessage == 'chat_authentication_required',
        onRetry: provider.refresh,
      );
    }

    if (provider.conversations.isEmpty) {
      return _ConversationsEmptyState(onRefresh: provider.refresh);
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: provider.refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              itemCount: provider.conversations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) => DriverConversationTile(
                conversation: provider.conversations[index],
                onTap: () => _openConversation(index),
              ),
            ),
          ),
        ),
        // The Driver list is paged (page/limit), not an endless scroll, so it
        // gets an explicit pager rather than scroll-triggered loading.
        if (provider.totalPages > 1) _ConversationsPager(provider: provider),
      ],
    );
  }
}

class _ConversationsPager extends StatelessWidget {
  const _ConversationsPager({required this.provider});

  final DriverChatConversationsProvider provider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xffE7EDF5))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _PagerButton(
              icon: Icons.chevron_left_rounded,
              onTap: provider.hasPreviousPage && !provider.isBusy
                  ? provider.previousPage
                  : null,
            ),
            Expanded(
              child: Text(
                '${chatCopy(context, 'Page', 'صفحة')} '
                '${provider.page} / ${provider.totalPages}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xff334155),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _PagerButton(
              icon: Icons.chevron_right_rounded,
              onTap: provider.hasNextPage && !provider.isBusy
                  ? provider.nextPage
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _PagerButton extends StatelessWidget {
  const _PagerButton({required this.icon, required this.onTap});

  final IconData icon;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    // The chevrons are mirrored by the ambient direction so "next" always
    // points forward in the reading order.
    return Material(
      color: enabled ? const Color(0xffEEF5FF) : const Color(0xffF1F5F9),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? () => onTap!() : null,
        child: SizedBox(
          width: 44,
          height: 40,
          child: Icon(
            icon,
            color: enabled ? AppColors.primary : const Color(0xffB6C2D2),
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _ConversationListSkeleton extends StatelessWidget {
  const _ConversationListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 84,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xffE7EDF5)),
        ),
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              _SkeletonBox(width: 46, height: 46, radius: 15),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(width: 130, height: 12, radius: 6),
                    SizedBox(height: 10),
                    _SkeletonBox(width: 190, height: 10, radius: 5),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xffEAF0F7),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _ConversationsEmptyState extends StatelessWidget {
  const _ConversationsEmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          const SizedBox(height: 110),
          Icon(Icons.forum_outlined, size: 54, color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            chatCopy(context, 'No conversations yet', 'لا توجد محادثات بعد'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            chatCopy(
              context,
              'Messages from operations and shipment threads will appear here.',
              'ستظهر هنا رسائل فريق العمليات ومحادثات الشحنات.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationsErrorState extends StatelessWidget {
  const _ConversationsErrorState({
    required this.isSessionError,
    required this.onRetry,
  });

  final bool isSessionError;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final title = isSessionError
        ? chatCopy(context, 'Session expired', 'انتهت الجلسة')
        : chatCopy(
            context,
            'Could not load conversations',
            'تعذر تحميل المحادثات',
          );
    final description = isSessionError
        ? chatCopy(
            context,
            'Please sign in again to continue.',
            'يرجى تسجيل الدخول مرة أخرى للمتابعة.',
          )
        : chatCopy(
            context,
            'Check your connection and try again.',
            'تحقق من الاتصال وحاول مرة أخرى.',
          );

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRetry,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
        children: [
          const SizedBox(height: 70),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xffE1EAF4)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F153B6A),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Color(0xffEAF2FF),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSessionError
                        ? Icons.lock_outline_rounded
                        : Icons.forum_outlined,
                    color: AppColors.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => onRetry(),
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                    label: Text(
                      chatCopy(context, 'Try again', 'إعادة المحاولة'),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
