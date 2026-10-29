import 'dart:async';
import 'dart:collection';

import 'package:blockatie/models/chat/chat_exception.dart';
import 'package:blockatie/models/chat/driver_chat_message.dart';
import 'package:blockatie/models/chat/driver_chat_pagination.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

enum DriverChatConversationState {
  initial,
  loading,
  loaded,
  loadingOlder,
  loadingNewer,
  empty,
  error,
}

/// One Driver conversation thread.
///
/// Messages are always held oldest -> newest, matching the order the backend
/// returns them, so the UI can render the list without re-ordering it.
///
/// A message is either authoritative (it carries a server `messageId`) or
/// optimistic (it carries only a `clientMessageId` until the send returns).
/// Both live in [messages]; [_mergeMessages] reconciles the two by matching on
/// `clientMessageId` first, which is what stops a sent message appearing twice.
///
/// Polling lives here rather than in the screen so the timer is owned by the
/// same object that owns the state it updates: a disposed or session-switched
/// provider cannot leave a timer running. It never starts by itself — the
/// screen calls [startPolling].
class DriverChatConversationProvider extends UserScopedNotifier {
  DriverChatConversationProvider({
    required this.conversationId,
    required DriverChatRepository repository,
    this.pageSize = 30,
    this.newMessagesPageSize = 50,
    this.pollingInterval = const Duration(seconds: 15),
  }) : assert(conversationId > 0),
       _repository = repository;

  final int conversationId;
  final DriverChatRepository _repository;
  final int pageSize;
  final int newMessagesPageSize;
  final Duration pollingInterval;

  /// How many "fetch newer" pages one poll will drain before giving the UI a
  /// turn. Bounded so a long backlog cannot monopolise a tick.
  static const int maxPollPages = 3;

  final List<DriverChatMessage> _messages = <DriverChatMessage>[];
  DriverChatConversationState _state = DriverChatConversationState.initial;
  bool _hasOlder = true;
  bool _hasMoreNewer = false;
  int? _nextBeforeMessageId;
  int _latestMessageId = 0;
  int _unreadCount = 0;
  bool _isSending = false;
  bool _isMarkingRead = false;
  bool _newerInFlight = false;
  bool _isRefreshingReadReceipts = false;
  String? _errorMessage;

  CancelToken? _loadToken;
  CancelToken? _sendToken;
  CancelToken? _readToken;
  int _loadGeneration = 0;

  Timer? _pollingTimer;
  bool _pollingRequested = false;
  bool _pollingPaused = false;
  bool _pollInFlight = false;

  UnmodifiableListView<DriverChatMessage> get messages =>
      UnmodifiableListView(_messages);
  DriverChatConversationState get state => _state;
  bool get hasOlder => _hasOlder;
  bool get hasMoreNewer => _hasMoreNewer;
  bool get isSending => _isSending;
  bool get isMarkingRead => _isMarkingRead;
  String? get errorMessage => _errorMessage;
  int get latestMessageId => _latestMessageId;

  /// Remaining unread for this thread, as last reported by `mark_read`.
  int get unreadCount => _unreadCount;

  bool get isLoading => _state == DriverChatConversationState.loading;
  bool get isLoadingOlder => _state == DriverChatConversationState.loadingOlder;
  bool get isLoadingNewer => _state == DriverChatConversationState.loadingNewer;

  /// True while a timer is actually scheduled — not merely requested.
  bool get isPolling => _pollingTimer != null;
  bool get isPollingPaused => _pollingPaused;

  // ---------------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------------

  Future<void> loadInitial() async {
    final sessionGeneration = stateGeneration;
    try {
      if (isLoading || _messages.isNotEmpty) {
        return;
      }
      final generation = ++_loadGeneration;
      final token = CancelToken();
      _loadToken = token;
      _state = DriverChatConversationState.loading;
      _errorMessage = null;
      notifyListeners();

      try {
        final page = await guardSession(
          _repository.getMessages(
            conversationId: conversationId,
            limit: pageSize,
            cancelToken: token,
          ),
          sessionGeneration,
        );
        if (!_isCurrent(generation)) {
          return;
        }
        _messages
          ..clear()
          ..addAll(page.messages);
        _sortAndRecalculateLatest();
        _hasOlder = page.hasMore;
        _nextBeforeMessageId = page.nextBeforeMessageId;
        _state =
            _messages.isEmpty
                ? DriverChatConversationState.empty
                : DriverChatConversationState.loaded;
      } catch (error) {
        if (!acceptsState(sessionGeneration)) throw const SessionChanged();

        if (!_isCurrent(generation) || _isCancelled(error)) {
          return;
        }
        _errorMessage = _safeMessage(error);
        _state = DriverChatConversationState.error;
      } finally {
        if (acceptsState(sessionGeneration) && _isCurrent(generation)) {
          _loadToken = null;
          notifyListeners();
        }
      }
    } on SessionChanged {
      return;
    }
  }

  /// Walks backwards through the thread using the `before_message_id` cursor.
  Future<void> loadOlder() async {
    final sessionGeneration = stateGeneration;
    try {
      if (!_hasOlder ||
          isLoading ||
          isLoadingOlder ||
          _nextBeforeMessageId == null) {
        return;
      }
      final generation = ++_loadGeneration;
      final token = CancelToken();
      _loadToken = token;
      _state = DriverChatConversationState.loadingOlder;
      _errorMessage = null;
      notifyListeners();

      try {
        final page = await guardSession(
          _repository.getMessages(
            conversationId: conversationId,
            beforeMessageId: _nextBeforeMessageId,
            limit: pageSize,
            cancelToken: token,
          ),
          sessionGeneration,
        );
        if (!_isCurrent(generation)) {
          return;
        }
        _mergeMessages(page.messages);
        _hasOlder = page.hasMore;
        _nextBeforeMessageId = page.nextBeforeMessageId;
        _state =
            _messages.isEmpty
                ? DriverChatConversationState.empty
                : DriverChatConversationState.loaded;
      } catch (error) {
        if (!acceptsState(sessionGeneration)) throw const SessionChanged();

        if (!_isCurrent(generation) || _isCancelled(error)) {
          return;
        }
        _errorMessage = _safeMessage(error);
        // Keep whatever is already on screen; only a first load may fail to a
        // full-screen error.
        _state =
            _messages.isEmpty
                ? DriverChatConversationState.error
                : DriverChatConversationState.loaded;
      } finally {
        if (acceptsState(sessionGeneration) && _isCurrent(generation)) {
          _loadToken = null;
          notifyListeners();
        }
      }
    } on SessionChanged {
      return;
    }
  }

  /// Everything after [latestMessageId].
  ///
  /// [silent] suppresses the loading state so a background poll does not put a
  /// spinner on screen every interval; the data path is identical.
  Future<void> fetchNewMessages({bool silent = false}) async {
    final sessionGeneration = stateGeneration;
    try {
      if (isLoading || isLoadingOlder || _newerInFlight) {
        return;
      }
      final generation = ++_loadGeneration;
      final token = CancelToken();
      _loadToken = token;
      _newerInFlight = true;
      if (!silent) {
        _state = DriverChatConversationState.loadingNewer;
        _errorMessage = null;
        notifyListeners();
      }

      try {
        final page = await guardSession(
          _repository.getNewMessages(
            conversationId: conversationId,
            afterMessageId: _latestMessageId,
            limit: newMessagesPageSize,
            cancelToken: token,
          ),
          sessionGeneration,
        );
        if (!_isCurrent(generation)) {
          return;
        }
        _mergeMessages(page.messages);
        // The cursor only ever moves forward: an empty page still reports the
        // server's newest id, and a stale reply must not rewind it.
        _latestMessageId =
            page.latestMessageId > _latestMessageId
                ? page.latestMessageId
                : _latestMessageId;
        _hasMoreNewer = page.hasMore;
        _state =
            _messages.isEmpty
                ? DriverChatConversationState.empty
                : DriverChatConversationState.loaded;
      } catch (error) {
        if (!acceptsState(sessionGeneration)) throw const SessionChanged();

        if (!_isCurrent(generation) || _isCancelled(error)) {
          return;
        }
        // A failed background poll must not replace the thread with an error
        // screen; the next tick will try again.
        if (!silent) {
          _errorMessage = _safeMessage(error);
        }
        _state =
            _messages.isEmpty
                ? DriverChatConversationState.error
                : DriverChatConversationState.loaded;
      } finally {
        if (acceptsState(sessionGeneration) && _isCurrent(generation)) {
          _newerInFlight = false;
          _loadToken = null;
          notifyListeners();
        }
      }
    } on SessionChanged {
      return;
    }
  }

  /// Opportunistically re-reads the newest page so "read by admin" ticks catch
  /// up on messages this driver sent. Never surfaces an error: it is a nicety,
  /// and failing it must not interrupt chatting.
  Future<void> refreshReadReceipts() async {
    final sessionGeneration = stateGeneration;
    try {
      final hasUnackowledgedOwnMessage = _messages.any(
        (message) =>
            message.isMine &&
            !message.isRead &&
            message.messageId != null &&
            message.messageId! > 0,
      );
      if (_isRefreshingReadReceipts || !hasUnackowledgedOwnMessage) {
        return;
      }

      _isRefreshingReadReceipts = true;
      try {
        final page = await guardSession(
          _repository.getMessages(
            conversationId: conversationId,
            limit: pageSize,
          ),
          sessionGeneration,
        );
        _mergeMessages(page.messages);
        notifyListeners();
      } catch (error) {
        if (!acceptsState(sessionGeneration)) throw const SessionChanged();
        // Deliberately swallowed.
      } finally {
        if (acceptsState(sessionGeneration)) {
          _isRefreshingReadReceipts = false;
        }
      }
    } on SessionChanged {
      return;
    }
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  /// Adds the message optimistically, then submits it.
  ///
  /// The `client_message_id` minted here is the idempotency key for this
  /// message for the rest of its life. [retryFailed] reuses it; it is never
  /// regenerated, because a new key would let the backend store the same text
  /// twice.
  Future<bool> sendMessage(String value) async {
    final sessionGeneration = stateGeneration;
    try {
      final normalized = value.trim();
      if (_isSending) {
        return false;
      }
      if (normalized.isEmpty) {
        _errorMessage = 'chat_message_required';
        notifyListeners();
        return false;
      }

      final clientMessageId = DriverChatService.generateClientMessageId();
      _messages.add(
        DriverChatMessage(
          conversationId: conversationId,
          senderRole: 'driver',
          senderName: '',
          messageType: 'text',
          message: normalized,
          isMine: true,
          isRead: false,
          createdAt: DateTime.now(),
          clientMessageId: clientMessageId,
          status: DriverChatMessageStatus.sending,
        ),
      );
      _isSending = true;
      _errorMessage = null;
      _sortAndRecalculateLatest();
      notifyListeners();

      return await guardSession(
        _submitMessage(message: normalized, clientMessageId: clientMessageId),
        sessionGeneration,
      );
    } on SessionChanged {
      return false;
    }
  }

  /// Re-submits a failed message under its original key.
  ///
  /// If the first attempt actually reached the server, the backend recognises
  /// the key and returns the stored message with `is_duplicate`, so the retry
  /// reconciles instead of duplicating.
  Future<bool> retryFailed(String clientMessageId) async {
    final sessionGeneration = stateGeneration;
    try {
      if (_isSending) {
        return false;
      }
      final index = _messages.indexWhere(
        (message) =>
            message.clientMessageId == clientMessageId &&
            message.status == DriverChatMessageStatus.failed,
      );
      if (index < 0) {
        return false;
      }

      final failed = _messages[index];
      _messages[index] = failed.copyWith(
        status: DriverChatMessageStatus.sending,
      );
      _isSending = true;
      _errorMessage = null;
      notifyListeners();

      return await guardSession(
        _submitMessage(
          // The text comes from the stored message, not from the caller, so a
          // retry can never alter what was queued.
          message: failed.message,
          clientMessageId: clientMessageId,
        ),
        sessionGeneration,
      );
    } on SessionChanged {
      return false;
    }
  }

  Future<bool> _submitMessage({
    required String message,
    required String clientMessageId,
  }) async {
    final sessionGeneration = stateGeneration;
    try {
      final token = CancelToken();
      _sendToken = token;
      try {
        final result = await guardSession(
          _repository.sendMessage(
            conversationId: conversationId,
            message: message,
            clientMessageId: clientMessageId,
            cancelToken: token,
          ),
          sessionGeneration,
        );
        if (token.isCancelled) {
          return false;
        }
        // Matching on client_message_id replaces the optimistic row in place.
        _mergeMessages(<DriverChatMessage>[result.message]);
        return true;
      } catch (error) {
        if (!acceptsState(sessionGeneration)) throw const SessionChanged();

        if (!_isCancelled(error)) {
          _setLocalMessageStatus(
            clientMessageId,
            DriverChatMessageStatus.failed,
          );
          _errorMessage = _safeMessage(error);
        }
        return false;
      } finally {
        if (acceptsState(sessionGeneration) && identical(_sendToken, token)) {
          _isSending = false;
          _sendToken = null;
          notifyListeners();
        }
      }
    } on SessionChanged {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Read receipts
  // ---------------------------------------------------------------------------

  /// Marks everything up to the newest incoming message as read.
  ///
  /// Returns the server's authoritative result, or null when there was nothing
  /// to mark or the call failed. The cursor is explicit — only messages this
  /// provider has actually loaded are acknowledged, never the whole thread.
  Future<DriverChatReadResult?> markRead() async {
    final sessionGeneration = stateGeneration;
    try {
      if (_isMarkingRead) {
        return null;
      }
      final lastReadableMessageId = _messages
          .where(
            (message) =>
                !message.isMine &&
                message.messageId != null &&
                message.messageId! > 0,
          )
          .fold<int>(
            0,
            (latest, message) =>
                message.messageId! > latest ? message.messageId! : latest,
          );
      if (lastReadableMessageId == 0) {
        return null;
      }

      _isMarkingRead = true;
      final token = CancelToken();
      _readToken = token;
      notifyListeners();

      try {
        final result = await guardSession(
          _repository.markRead(
            conversationId: conversationId,
            lastMessageId: lastReadableMessageId,
            cancelToken: token,
          ),
          sessionGeneration,
        );
        if (token.isCancelled) {
          return null;
        }
        for (var index = 0; index < _messages.length; index++) {
          final current = _messages[index];
          final messageId = current.messageId;
          if (!current.isMine &&
              messageId != null &&
              messageId <= result.lastReadMessageId) {
            _messages[index] = current.copyWith(isRead: true);
          }
        }
        _unreadCount = result.unreadCount;
        return result;
      } catch (error) {
        if (!acceptsState(sessionGeneration)) throw const SessionChanged();

        if (!_isCancelled(error)) {
          _errorMessage = _safeMessage(error);
        }
        return null;
      } finally {
        if (acceptsState(sessionGeneration) && identical(_readToken, token)) {
          _isMarkingRead = false;
          _readToken = null;
          notifyListeners();
        }
      }
    } on SessionChanged {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Polling
  // ---------------------------------------------------------------------------

  /// Starts the poll loop. Calling it twice is safe: [_ensureTimer] refuses to
  /// create a second timer, so there is never more than one in flight.
  void startPolling({bool immediate = false}) {
    _pollingRequested = true;
    _pollingPaused = false;
    _ensureTimer();
    if (immediate) {
      unawaited(pollOnce());
    }
  }

  /// Stops the loop and forgets that it was wanted. [resumePolling] will not
  /// restart it; [startPolling] is needed.
  void stopPolling() {
    _pollingRequested = false;
    _pollingPaused = false;
    _cancelTimer();
  }

  /// Suspends the loop without forgetting it — for backgrounding the app, or
  /// for a screen that is covered but not disposed.
  void pausePolling() {
    _pollingPaused = true;
    _cancelTimer();
  }

  /// Resumes a paused loop. A no-op unless [startPolling] was called first.
  void resumePolling({bool immediate = false}) {
    if (!_pollingRequested) {
      return;
    }
    _pollingPaused = false;
    _ensureTimer();
    if (immediate) {
      unawaited(pollOnce());
    }
  }

  /// One poll, drained up to [maxPollPages]. Exposed so a screen can poll on
  /// demand — pull-to-refresh, or returning from the background.
  Future<void> pollOnce() async {
    final sessionGeneration = stateGeneration;
    if (_pollInFlight || isLoading || isLoadingOlder || _newerInFlight) {
      return;
    }
    _pollInFlight = true;
    try {
      var pages = 0;
      do {
        await fetchNewMessages(silent: true);
        if (!acceptsState(sessionGeneration)) {
          return;
        }
        pages++;
      } while (_hasMoreNewer && pages < maxPollPages);

      await refreshReadReceipts();
    } finally {
      if (acceptsState(sessionGeneration)) {
        _pollInFlight = false;
      }
    }
  }

  void _ensureTimer() {
    if (!_pollingRequested || _pollingPaused || _pollingTimer != null) {
      return;
    }
    _pollingTimer = Timer.periodic(
      pollingInterval,
      (_) => unawaited(pollOnce()),
    );
  }

  void _cancelTimer() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Merging
  // ---------------------------------------------------------------------------

  /// Folds server rows into the local list.
  ///
  /// `clientMessageId` is checked before `messageId` on purpose: that is how an
  /// optimistic row finds its authoritative replacement, since the optimistic
  /// row has no server id yet. Falling back to `messageId` covers incoming
  /// messages and re-reads of the same page.
  void _mergeMessages(Iterable<DriverChatMessage> incoming) {
    final serverIndexes = <int, int>{};
    final clientIndexes = <String, int>{};
    for (var index = 0; index < _messages.length; index++) {
      final message = _messages[index];
      final serverId = message.messageId;
      if (serverId != null) {
        serverIndexes[serverId] = index;
      }
      final clientId = message.clientMessageId;
      if (clientId != null && clientId.isNotEmpty) {
        clientIndexes[clientId] = index;
      }
    }

    var didChange = false;
    for (final message in incoming) {
      final clientId = message.clientMessageId;
      int? index;
      if (clientId != null && clientId.isNotEmpty) {
        index = clientIndexes[clientId];
      }
      final serverId = message.messageId;
      index ??= serverId == null ? null : serverIndexes[serverId];

      if (index == null) {
        _messages.add(message);
        didChange = true;
        final newIndex = _messages.length - 1;
        if (serverId != null) {
          serverIndexes[serverId] = newIndex;
        }
        if (clientId != null && clientId.isNotEmpty) {
          clientIndexes[clientId] = newIndex;
        }
        continue;
      }

      final existing = _messages[index];
      // The read contract does not echo client_message_id, and list_messages
      // may omit created_at on an optimistic row we already timed locally, so
      // both are carried across rather than dropped.
      final replacement = message.copyWith(
        clientMessageId: message.clientMessageId ?? existing.clientMessageId,
        createdAt: message.createdAt ?? existing.createdAt,
      );
      if (replacement != existing) {
        _messages[index] = replacement;
        didChange = true;
      }
      if (serverId != null) {
        serverIndexes[serverId] = index;
      }
    }

    if (didChange) {
      _sortAndRecalculateLatest();
    }
  }

  void _setLocalMessageStatus(
    String clientMessageId,
    DriverChatMessageStatus status,
  ) {
    final index = _messages.indexWhere(
      (message) => message.clientMessageId == clientMessageId,
    );
    if (index >= 0) {
      _messages[index] = _messages[index].copyWith(status: status);
    }
  }

  /// Orders oldest -> newest and recomputes the polling cursor.
  ///
  /// Server ids order authoritatively. A pending message has no id yet, so it
  /// sorts after every stored message — it is, by definition, the newest thing
  /// in the thread.
  void _sortAndRecalculateLatest() {
    _messages.sort((first, second) {
      final firstId = first.messageId;
      final secondId = second.messageId;
      if (firstId != null && secondId != null) {
        return firstId.compareTo(secondId);
      }
      final firstTime = first.createdAt;
      final secondTime = second.createdAt;
      if (firstTime != null && secondTime != null) {
        final byTime = firstTime.compareTo(secondTime);
        if (byTime != 0) {
          return byTime;
        }
      }
      if (firstId == null && secondId != null) {
        return 1;
      }
      if (firstId != null && secondId == null) {
        return -1;
      }
      return 0;
    });
    _latestMessageId = _messages.fold<int>(0, (latest, message) {
      final messageId = message.messageId;
      return messageId != null && messageId > latest ? messageId : latest;
    });
  }

  /// True only while [generation] is still the newest load. Disposal is already
  /// covered: [acceptsState] is false once the notifier is disposed.
  bool _isCurrent(int generation) => generation == _loadGeneration;

  static bool _isCancelled(Object error) =>
      error is ChatException && error.code == 'REQUEST_CANCELLED';

  static String _safeMessage(Object error) =>
      error is ChatException ? error.safeMessage : 'chat_unknown_error';

  /// Wipes the thread and stops polling. Called by [UserSessionState] on logout
  /// and on account switch, so the next driver can never see these messages and
  /// no timer survives the boundary.
  @override
  @protected
  void clearUserState() {
    _loadGeneration++;
    _pollingRequested = false;
    _pollingPaused = false;
    _pollInFlight = false;
    _cancelTimer();
    _loadToken?.cancel('driver chat session cleared');
    _sendToken?.cancel('driver chat session cleared');
    _readToken?.cancel('driver chat session cleared');
    _loadToken = null;
    _sendToken = null;
    _readToken = null;
    _messages.clear();
    _state = DriverChatConversationState.initial;
    _hasOlder = true;
    _hasMoreNewer = false;
    _nextBeforeMessageId = null;
    _latestMessageId = 0;
    _unreadCount = 0;
    _isSending = false;
    _isMarkingRead = false;
    _newerInFlight = false;
    _isRefreshingReadReceipts = false;
    _errorMessage = null;
  }

  @override
  void dispose() {
    _loadGeneration++;
    _pollingRequested = false;
    _cancelTimer();
    _loadToken?.cancel('driver chat conversation disposed');
    _sendToken?.cancel('driver chat conversation disposed');
    _readToken?.cancel('driver chat conversation disposed');
    _loadToken = null;
    _sendToken = null;
    _readToken = null;
    super.dispose();
  }
}
