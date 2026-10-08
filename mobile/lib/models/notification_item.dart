class NotificationItem {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final String entityType;
  final String entityId;
  final String? orderId;
  final String? tripId;
  final String? rideRequestId;
  final DateTime? readAt;
  final String idempotencyKey;
  final DateTime createdAt;

  NotificationItem({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.entityType,
    required this.entityId,
    this.orderId,
    this.tripId,
    this.rideRequestId,
    this.readAt,
    required this.idempotencyKey,
    required this.createdAt,
  });

  bool get isRead => readAt != null;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as String,
      orderId: json['order_id'] as String?,
      tripId: json['trip_id'] as String?,
      rideRequestId: json['ride_request_id'] as String?,
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at'] as String) : null,
      idempotencyKey: json['idempotency_key'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type,
      'title': title,
      'body': body,
      'entity_type': entityType,
      'entity_id': entityId,
      'order_id': orderId,
      'trip_id': tripId,
      'ride_request_id': rideRequestId,
      'read_at': readAt?.toIso8601String(),
      'idempotency_key': idempotencyKey,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get relativeTimeDescription {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }
}
