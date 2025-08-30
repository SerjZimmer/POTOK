class Note {
  final String id;
  final String title;
  final String content;
  final String folderId;

  Note({required this.id, required this.title, required this.content, required this.folderId});

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      folderId: json['folder_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'folder_id': folderId,
    };
  }
}