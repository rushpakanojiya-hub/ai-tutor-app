class YoutubeVideo {
  final String videoId;
  final String title;
  final String? description;
  final String thumbnail;
  final String channel;
  final String? publishedAt;
  final String duration;

  YoutubeVideo({
    required this.videoId,
    required this.title,
    this.description,
    required this.thumbnail,
    required this.channel,
    this.publishedAt,
    required this.duration,
  });

  factory YoutubeVideo.fromJson(Map<String, dynamic> json) {
    return YoutubeVideo(
      videoId: json['video_id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      thumbnail: json['thumbnail'] ?? '',
      channel: json['channel'] ?? '',
      publishedAt: json['published_at'],
      duration: json['duration'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'video_id': videoId,
      'title': title,
      'description': description,
      'thumbnail': thumbnail,
      'channel': channel,
      'published_at': publishedAt,
      'duration': duration,
    };
  }
}
