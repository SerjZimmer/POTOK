// Domain entities for Mail module
// These are simplified versions of backend models for Flutter

class MailAccount {
  final String uid;
  final String provider;
  final String email;
  final String? displayName;
  final String? avatarUrl;
  final bool isDefault;
  final bool isVisible;
  final DateTime createdAt;
  final DateTime updatedAt;

  MailAccount({
    required this.uid,
    required this.provider,
    required this.email,
    this.displayName,
    this.avatarUrl,
    this.isDefault = false,
    this.isVisible = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MailAccount.fromJson(Map<String, dynamic> json) {
    return MailAccount(
      uid: json['uid'] as String,
      provider: json['provider'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      isDefault: json['isDefault'] as bool? ?? false,
      isVisible: json['isVisible'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'provider': provider,
      'email': email,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'isDefault': isDefault,
      'isVisible': isVisible,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class Mailbox {
  final String id;
  final String accountUid;
  final String name;
  final String role;
  final int total;
  final int unread;
  final bool visible;

  Mailbox({
    required this.id,
    required this.accountUid,
    required this.name,
    required this.role,
    required this.total,
    required this.unread,
    required this.visible,
  });

  factory Mailbox.fromJson(Map<String, dynamic> json) {
    return Mailbox(
      id: json['id'] as String,
      accountUid: json['accountUid'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
      total: json['total'] as int,
      unread: json['unread'] as int,
      visible: json['visible'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'accountUid': accountUid,
      'name': name,
      'role': role,
      'total': total,
      'unread': unread,
      'visible': visible,
    };
  }
}

class Thread {
  final String id;
  final String accountUid;
  final String? mailboxId;
  final String subject;
  final String lastFrom;
  final String? lastSnippet;
  final DateTime lastDate;
  final int unreadCount;
  final ThreadFlags flags;
  final String hash;

  Thread({
    required this.id,
    required this.accountUid,
    this.mailboxId,
    required this.subject,
    required this.lastFrom,
    this.lastSnippet,
    required this.lastDate,
    required this.unreadCount,
    required this.flags,
    required this.hash,
  });

  factory Thread.fromJson(Map<String, dynamic> json) {
    return Thread(
      id: json['id'] as String,
      accountUid: json['accountUid'] as String,
      mailboxId: json['mailboxId'] as String?,
      subject: json['subject'] as String,
      lastFrom: json['lastFrom'] as String,
      lastSnippet: json['lastSnippet'] as String?,
      lastDate: DateTime.parse(json['lastDate'] as String),
      unreadCount: json['unreadCount'] as int,
      flags: ThreadFlags.fromJson(json['flags'] as Map<String, dynamic>),
      hash: json['hash'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'accountUid': accountUid,
      'mailboxId': mailboxId,
      'subject': subject,
      'lastFrom': lastFrom,
      'lastSnippet': lastSnippet,
      'lastDate': lastDate.toIso8601String(),
      'unreadCount': unreadCount,
      'flags': flags.toJson(),
      'hash': hash,
    };
  }
}

class ThreadFlags {
  final bool pinned;
  final bool flagged;
  final bool answered;

  ThreadFlags({
    this.pinned = false,
    this.flagged = false,
    this.answered = false,
  });

  factory ThreadFlags.fromJson(Map<String, dynamic> json) {
    return ThreadFlags(
      pinned: json['pinned'] as bool? ?? false,
      flagged: json['flagged'] as bool? ?? false,
      answered: json['answered'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pinned': pinned,
      'flagged': flagged,
      'answered': answered,
    };
  }
}

class Message {
  final String id;
  final String threadId;
  final String accountUid;
  final String from;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final DateTime date;
  final String subject;
  final String? bodyText;
  final String? bodyHtml;
  final MessageFlags flags;
  final int size;
  final bool hasAttachments;

  Message({
    required this.id,
    required this.threadId,
    required this.accountUid,
    required this.from,
    required this.to,
    required this.cc,
    required this.bcc,
    required this.date,
    required this.subject,
    this.bodyText,
    this.bodyHtml,
    required this.flags,
    required this.size,
    required this.hasAttachments,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      threadId: json['threadId'] as String,
      accountUid: json['accountUid'] as String,
      from: json['from'] as String,
      to: List<String>.from(json['to'] as List),
      cc: List<String>.from(json['cc'] as List),
      bcc: List<String>.from(json['bcc'] as List),
      date: DateTime.parse(json['date'] as String),
      subject: json['subject'] as String,
      bodyText: json['bodyText'] as String?,
      bodyHtml: json['bodyHtml'] as String?,
      flags: MessageFlags.fromJson(json['flags'] as Map<String, dynamic>),
      size: json['size'] as int,
      hasAttachments: json['hasAttachments'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'threadId': threadId,
      'accountUid': accountUid,
      'from': from,
      'to': to,
      'cc': cc,
      'bcc': bcc,
      'date': date.toIso8601String(),
      'subject': subject,
      'bodyText': bodyText,
      'bodyHtml': bodyHtml,
      'flags': flags.toJson(),
      'size': size,
      'hasAttachments': hasAttachments,
    };
  }
}

class MessageFlags {
  final bool seen;
  final bool flagged;
  final bool answered;

  MessageFlags({
    this.seen = false,
    this.flagged = false,
    this.answered = false,
  });

  factory MessageFlags.fromJson(Map<String, dynamic> json) {
    return MessageFlags(
      seen: json['seen'] as bool? ?? false,
      flagged: json['flagged'] as bool? ?? false,
      answered: json['answered'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'seen': seen,
      'flagged': flagged,
      'answered': answered,
    };
  }
}

class Attachment {
  final String id;
  final String messageId;
  final String filename;
  final String mime;
  final int size;
  final String? localPath;

  Attachment({
    required this.id,
    required this.messageId,
    required this.filename,
    required this.mime,
    required this.size,
    this.localPath,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id'] as String,
      messageId: json['messageId'] as String,
      filename: json['filename'] as String,
      mime: json['mime'] as String,
      size: json['size'] as int,
      localPath: json['localPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'messageId': messageId,
      'filename': filename,
      'mime': mime,
      'size': size,
      'localPath': localPath,
    };
  }
}
