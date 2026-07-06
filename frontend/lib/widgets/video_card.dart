import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/youtube_video.dart';

/// Pastel-styled video card matching the AI Tutor app's visual language.
class VideoCard extends StatelessWidget {
  final YoutubeVideo video;
  final VoidCallback onWatch;
  final int index;

  const VideoCard({
    super.key,
    required this.video,
    required this.onWatch,
    this.index = 0,
  });

  static const _cardColor = Color(0xFFFDF6F0); // pastel cream
  static const _accentColor = Color(0xFFB8A6E8); // pastel lavender
  static const _textDark = Color(0xFF3A3153);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: _cardColor,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _accentColor.withOpacity(0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onWatch,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      video.thumbnail,
                      width: 120,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 120,
                        height: 80,
                        color: _accentColor.withOpacity(0.15),
                        child: const Icon(Icons.play_circle_outline, color: _textDark),
                      ),
                    ),
                  ),
                  if (video.duration.isNotEmpty)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          video.duration,
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      video.channel,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: _textDark.withOpacity(0.65),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton.icon(
                        onPressed: onWatch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: Text('Watch', style: GoogleFonts.poppins(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: (index * 80).ms, duration: 300.ms).slideY(begin: 0.08, end: 0);
  }
}
