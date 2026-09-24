import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Categories of alert events emitted by the trading engine and app.
enum NotificationType {
  tradeFill,
  stopLoss,
  takeProfit,
  trailingStop,
  dailyLossHalt,
  pdtWarning,
  system,
}

/// Visual and urgency priority for notifications.
enum NotificationSeverity {
  info,
  success,
  warning,
  critical,
}

/// A structured notification record.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.severity,
    required this.timestamp,
    this.symbol,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final NotificationSeverity severity;
  final DateTime timestamp;
  final String? symbol;
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        title: title,
        body: body,
        type: type,
        severity: severity,
        timestamp: timestamp,
        symbol: symbol,
        read: read ?? this.read,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'type': type.name,
        'severity': severity.name,
        'timestamp': timestamp.toIso8601String(),
        'symbol': symbol,
        'read': read,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        type: NotificationType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => NotificationType.system,
        ),
        severity: NotificationSeverity.values.firstWhere(
          (s) => s.name == json['severity'],
          orElse: () => NotificationSeverity.info,
        ),
        timestamp: DateTime.parse(json['timestamp'] as String),
        symbol: json['symbol'] as String?,
        read: json['read'] as bool? ?? false,
      );
}

/// User configuration for alerts and remote push webhooks.
class NotificationConfig {
  const NotificationConfig({
    this.enabled = true,
    this.notifyOnFills = true,
    this.notifyOnStops = true,
    this.notifyOnHalts = true,
    this.notifyOnPdt = true,
    this.webhookUrl = '',
    this.telegramBotToken = '',
    this.telegramChatId = '',
  });

  final bool enabled;
  final bool notifyOnFills;
  final bool notifyOnStops;
  final bool notifyOnHalts;
  final bool notifyOnPdt;

  /// Optional Discord, Slack, or generic HTTP webhook endpoint for phone push.
  final String webhookUrl;

  /// Optional Telegram bot integration for phone push notifications.
  final String telegramBotToken;
  final String telegramChatId;

  bool get hasWebhook => webhookUrl.trim().isNotEmpty;
  bool get hasTelegram =>
      telegramBotToken.trim().isNotEmpty && telegramChatId.trim().isNotEmpty;

  NotificationConfig copyWith({
    bool? enabled,
    bool? notifyOnFills,
    bool? notifyOnStops,
    bool? notifyOnHalts,
    bool? notifyOnPdt,
    String? webhookUrl,
    String? telegramBotToken,
    String? telegramChatId,
  }) =>
      NotificationConfig(
        enabled: enabled ?? this.enabled,
        notifyOnFills: notifyOnFills ?? this.notifyOnFills,
        notifyOnStops: notifyOnStops ?? this.notifyOnStops,
        notifyOnHalts: notifyOnHalts ?? this.notifyOnHalts,
        notifyOnPdt: notifyOnPdt ?? this.notifyOnPdt,
        webhookUrl: webhookUrl ?? this.webhookUrl,
        telegramBotToken: telegramBotToken ?? this.telegramBotToken,
        telegramChatId: telegramChatId ?? this.telegramChatId,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'notifyOnFills': notifyOnFills,
        'notifyOnStops': notifyOnStops,
        'notifyOnHalts': notifyOnHalts,
        'notifyOnPdt': notifyOnPdt,
        'webhookUrl': webhookUrl,
        'telegramBotToken': telegramBotToken,
        'telegramChatId': telegramChatId,
      };

  factory NotificationConfig.fromJson(Map<String, dynamic> json) =>
      NotificationConfig(
        enabled: json['enabled'] as bool? ?? true,
        notifyOnFills: json['notifyOnFills'] as bool? ?? true,
        notifyOnStops: json['notifyOnStops'] as bool? ?? true,
        notifyOnHalts: json['notifyOnHalts'] as bool? ?? true,
        notifyOnPdt: json['notifyOnPdt'] as bool? ?? true,
        webhookUrl: json['webhookUrl'] as String? ?? '',
        telegramBotToken: json['telegramBotToken'] as String? ?? '',
        telegramChatId: json['telegramChatId'] as String? ?? '',
      );
}

/// Dispatches notifications to in-app stream, local history, and remote webhooks.
class NotificationService {
  NotificationService({
    NotificationConfig? config,
    http.Client? client,
  })  : config = config ?? const NotificationConfig(),
        _client = client ?? http.Client();

  NotificationConfig config;
  final http.Client _client;

  final StreamController<AppNotification> _controller =
      StreamController<AppNotification>.broadcast();
  Stream<AppNotification> get stream => _controller.stream;

  final List<AppNotification> _history = <AppNotification>[];
  List<AppNotification> get history => List<AppNotification>.unmodifiable(_history);

  int get unreadCount => _history.where((n) => !n.read).length;

  int _seq = 0;

  /// Check whether this notification type is permitted by user settings.
  bool shouldNotify(NotificationType type) {
    if (!config.enabled) return false;
    switch (type) {
      case NotificationType.tradeFill:
        return config.notifyOnFills;
      case NotificationType.stopLoss:
      case NotificationType.takeProfit:
      case NotificationType.trailingStop:
        return config.notifyOnStops;
      case NotificationType.dailyLossHalt:
        return config.notifyOnHalts;
      case NotificationType.pdtWarning:
        return config.notifyOnPdt;
      case NotificationType.system:
        return true;
    }
  }

  /// Dispatch an alert. Adds to history, emits to stream, and sends webhooks.
  Future<bool> dispatch({
    required String title,
    required String body,
    required NotificationType type,
    required NotificationSeverity severity,
    String? symbol,
  }) async {
    if (!shouldNotify(type)) return false;

    final n = AppNotification(
      id: 'notif-${DateTime.now().microsecondsSinceEpoch}-${++_seq}',
      title: title,
      body: body,
      type: type,
      severity: severity,
      timestamp: DateTime.now(),
      symbol: symbol,
      read: false,
    );

    _history.insert(0, n);
    if (_history.length > 200) {
      _history.removeRange(200, _history.length);
    }

    if (!_controller.isClosed) {
      _controller.add(n);
    }

    // Deliver to remote push webhooks asynchronously.
    unawaited(_sendRemote(n));
    return true;
  }

  void markAllRead() {
    for (var i = 0; i < _history.length; i++) {
      if (!_history[i].read) {
        _history[i] = _history[i].copyWith(read: true);
      }
    }
  }

  void markRead(String id) {
    final idx = _history.indexWhere((n) => n.id == id);
    if (idx >= 0) {
      _history[idx] = _history[idx].copyWith(read: true);
    }
  }

  void clearHistory() {
    _history.clear();
  }

  /// Test webhook connectivity by posting a sample ping.
  Future<bool> sendTestNotification() async {
    return dispatch(
      title: '🔔 Tr-Daily Test Alert',
      body: 'Notifications are configured properly and active.',
      type: NotificationType.system,
      severity: NotificationSeverity.info,
    );
  }

  Future<void> _sendRemote(AppNotification n) async {
    if (config.hasWebhook) {
      await _postWebhook(n);
    }
    if (config.hasTelegram) {
      await _postTelegram(n);
    }
  }

  Future<void> _postWebhook(AppNotification n) async {
    final urlStr = config.webhookUrl.trim();
    if (urlStr.isEmpty) return;

    try {
      final uri = Uri.parse(urlStr);
      final isDiscord = urlStr.contains('discord.com/api/webhooks');
      final isSlack = urlStr.contains('slack.com/services');

      Map<String, dynamic> payload;
      if (isDiscord) {
        final color = switch (n.severity) {
          NotificationSeverity.critical => 0xFF3B30, // Red
          NotificationSeverity.warning => 0xFFA726,  // Orange
          NotificationSeverity.success => 0x26A69A,  // Teal green
          NotificationSeverity.info => 0x42A5F5,     // Blue
        };
        payload = <String, dynamic>{
          'username': 'Tr-Daily Agent',
          'embeds': <Map<String, dynamic>>[
            <String, dynamic>{
              'title': n.title,
              'description': n.body,
              'color': color,
              'timestamp': n.timestamp.toUtc().toIso8601String(),
              'footer': <String, dynamic>{'text': 'Tr-Daily Day-Trading'},
            }
          ]
        };
      } else if (isSlack) {
        payload = <String, dynamic>{
          'text': '*${n.title}*\n${n.body}',
        };
      } else {
        // Generic JSON webhook
        payload = n.toJson();
      }

      await _client.post(
        uri,
        headers: const <String, String>{
          'Content-Type': 'application/json',
          'User-Agent': 'Tr-Daily/0.1',
        },
        body: jsonEncode(payload),
      );
    } catch (_) {
      // Remote alerts are best-effort; don't break engine loop.
    }
  }

  Future<void> _postTelegram(AppNotification n) async {
    final token = config.telegramBotToken.trim();
    final chatId = config.telegramChatId.trim();
    if (token.isEmpty || chatId.isEmpty) return;

    try {
      final uri = Uri.parse('https://api.telegram.org/bot$token/sendMessage');
      final icon = switch (n.severity) {
        NotificationSeverity.critical => '🚨',
        NotificationSeverity.warning => '⚠️',
        NotificationSeverity.success => '✅',
        NotificationSeverity.info => 'ℹ️',
      };
      final text = '$icon *${n.title}*\n\n${n.body}';

      await _client.post(
        uri,
        headers: const <String, String>{
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'chat_id': chatId,
          'text': text,
          'parse_mode': 'Markdown',
        }),
      );
    } catch (_) {
      // Telegram best-effort.
    }
  }

  void dispose() {
    unawaited(_controller.close());
    _client.close();
  }
}
