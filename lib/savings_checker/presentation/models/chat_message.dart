enum ChatMessageSender { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.sender,
    required this.text,
    this.createdAt,
    this.analysisNumber,
    this.turnId,
    this.analysisId,
    this.revision,
    this.contextRevision,
    this.failed = false,
  });

  final ChatMessageSender sender;
  final String text;
  final DateTime? createdAt;
  // Session grouping exists even before the first accepted planner response.
  final int? analysisNumber;
  final int? turnId;
  final String? analysisId;
  final int? revision;
  final int? contextRevision;
  final bool failed;
}
