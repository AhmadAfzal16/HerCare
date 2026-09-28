class CommunityPost {
  CommunityPost(Map<String, dynamic> data)
      : id = data['id'] as String,
        authorId = data['author']['id'] as String,
        alias = data['author']['alias'] as String,
        title = data['title'] as String? ?? '',
        body = data['body'] as String? ?? '',
        topic = data['topic'] as String,
        status = data['status'] as String,
        mine = data['is_mine'] == true,
        expert = data['expert_answer'] == true,
        parentId = data['parent_id'] as String?,
        sessionId = data['session_id'] as String?,
        createdAt = DateTime.parse(data['created_at'] as String),
        version = (data['version'] as num).toInt(),
        comments = (data['comment_count'] as num? ?? 0).toInt(),
        reactions = Map<String, dynamic>.from(data['reactions'] as Map? ?? {}),
        myReactions = Set<String>.from(data['my_reactions'] as List? ?? []),
        moderation =
            Map<String, dynamic>.from(data['moderation'] as Map? ?? {}),
        reports = List<String>.from(data['reports'] as List? ?? []);
  final String id, authorId, alias, title, body, topic, status;
  final String? parentId, sessionId;
  final bool mine, expert;
  final DateTime createdAt;
  final int version, comments;
  final Map<String, dynamic> reactions, moderation;
  final Set<String> myReactions;
  final List<String> reports;
}

class CommunityPage {
  CommunityPage(Map<String, dynamic> data)
      : items = (data['items'] as List)
            .map((v) => CommunityPost(Map<String, dynamic>.from(v as Map)))
            .toList(),
        cursor = data['next_cursor'] as String?;
  final List<CommunityPost> items;
  final String? cursor;
}
