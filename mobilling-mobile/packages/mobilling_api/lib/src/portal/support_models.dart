/// Support-area models: tickets, announcements, knowledgebase.
/// Shapes match `PortalTicketController::format`,
/// `PortalAnnouncementController` and `PortalKnowledgebaseController`.
library;

import '../json.dart';

class PortalTicket {
  const PortalTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.priority,
    required this.department,
    required this.replies,
    this.ticketNumber,
    this.relatedService,
    this.repliesCount,
    this.lastReplyAt,
    this.createdAt,
  });

  final String id;
  final String subject;

  /// open | answered | customer_reply | closed (staff side may add more; the
  /// status chip falls back gracefully on unknowns).
  final String status;
  final String priority;
  final String department;
  final List<TicketReply> replies;
  final String? ticketNumber;
  final String? relatedService;
  final int? repliesCount;
  final DateTime? lastReplyAt;
  final DateTime? createdAt;

  bool get isClosed => status == 'closed';

  factory PortalTicket.fromJson(Map<String, dynamic> json) => PortalTicket(
        id: json.id(),
        subject: json.strOr('subject', '—'),
        status: json.strOr('status', 'open'),
        priority: json.strOr('priority', 'medium'),
        department: json.strOr('department', 'support'),
        replies: json.list('replies', TicketReply.fromJson),
        ticketNumber: json.str('ticket_number'),
        relatedService: json.str('related_service'),
        repliesCount: json['replies_count'] == null
            ? null
            : json.count('replies_count'),
        lastReplyAt: json.date('last_reply_at'),
        createdAt: json.date('created_at'),
      );
}

class TicketReply {
  const TicketReply({
    required this.id,
    required this.message,
    required this.isClient,
    required this.attachments,
    this.authorName,
    this.createdAt,
  });

  final String id;
  final String message;

  /// author_type is 'client' or 'staff' — drives chat-bubble alignment.
  final bool isClient;
  final List<TicketAttachment> attachments;
  final String? authorName;
  final DateTime? createdAt;

  factory TicketReply.fromJson(Map<String, dynamic> json) => TicketReply(
        id: json.id(),
        message: json.strOr('message', ''),
        isClient: json.strOr('author_type', 'client') == 'client',
        attachments: json.list('attachments', TicketAttachment.fromJson),
        authorName: json.str('author_name'),
        createdAt: json.date('created_at'),
      );
}

class TicketAttachment {
  const TicketAttachment({
    required this.id,
    required this.originalName,
    this.mime,
    this.size,
  });

  final String id;
  final String originalName;
  final String? mime;
  final int? size;

  factory TicketAttachment.fromJson(Map<String, dynamic> json) =>
      TicketAttachment(
        id: json.id(),
        originalName: json.strOr('original_name', 'attachment'),
        mime: json.str('mime'),
        size: json['size'] == null ? null : json.count('size'),
      );
}

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.publishedAt,
  });

  final String id;
  final String title;

  /// HTML from the tenant's editor — render through a tag-stripper.
  final String body;
  final DateTime? publishedAt;

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
        id: json.id(),
        title: json.strOr('title', '—'),
        body: json.strOr('body', ''),
        publishedAt: json.date('published_at'),
      );
}

class KbCategory {
  const KbCategory({
    required this.name,
    required this.articles,
    this.id,
    this.slug,
    this.description,
  });

  final String name;
  final List<KbArticleSummary> articles;

  /// Null for the synthetic "General" bucket of uncategorised articles.
  final String? id;
  final String? slug;
  final String? description;

  factory KbCategory.fromJson(Map<String, dynamic> json) => KbCategory(
        name: json.strOr('name', 'General'),
        articles: json.list('articles', KbArticleSummary.fromJson),
        id: json.str('id'),
        slug: json.str('slug'),
        description: json.str('description'),
      );
}

class KbArticleSummary {
  const KbArticleSummary({
    required this.id,
    required this.title,
    required this.slug,
    this.excerpt,
    this.views,
  });

  final String id;
  final String title;
  final String slug;
  final String? excerpt;
  final int? views;

  factory KbArticleSummary.fromJson(Map<String, dynamic> json) =>
      KbArticleSummary(
        id: json.id(),
        title: json.strOr('title', '—'),
        slug: json.strOr('slug', ''),
        excerpt: json.str('excerpt'),
        views: json['views'] == null ? null : json.count('views'),
      );
}

class KbArticle {
  const KbArticle({
    required this.id,
    required this.title,
    required this.body,
    this.categoryName,
    this.views,
    this.updatedAt,
  });

  final String id;
  final String title;

  /// HTML body.
  final String body;
  final String? categoryName;
  final int? views;
  final DateTime? updatedAt;

  factory KbArticle.fromJson(Map<String, dynamic> json) => KbArticle(
        id: json.id(),
        title: json.strOr('title', '—'),
        body: json.strOr('body', ''),
        categoryName: json.str('category_name'),
        views: json['views'] == null ? null : json.count('views'),
        updatedAt: json.date('updated_at'),
      );
}
