enum ChatMessageSender { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.sender,
    required this.text,
    this.createdAt,
  });

  final ChatMessageSender sender;
  final String text;
  final DateTime? createdAt;
}
