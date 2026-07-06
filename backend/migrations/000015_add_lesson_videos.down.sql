UPDATE lessons SET video_url = NULL
WHERE video_url LIKE '/static/videos/%';
