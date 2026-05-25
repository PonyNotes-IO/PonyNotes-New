import 'dart:io';
import 'package:flutter/material.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/media_entities.pbenum.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../application/file_library_models.dart';

/// 文件预览缩略图组件
class FilePreviewThumbnail extends StatefulWidget {
  final FileLibraryItem file;
  final double size;

  const FilePreviewThumbnail({
    super.key,
    required this.file,
    this.size = 48,
  });

  @override
  State<FilePreviewThumbnail> createState() => _FilePreviewThumbnailState();
}

class _FilePreviewThumbnailState extends State<FilePreviewThumbnail> {
  Player? _player;
  VideoController? _videoController;
  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (widget.file.fileType == MediaFileTypePB.Video) {
      _initVideoThumbnail();
    }
  }

  @override
  void didUpdateWidget(FilePreviewThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果文件改变了，重新加载缩略图
    if (oldWidget.file.url != widget.file.url) {
      // 清理旧的播放器
      _player?.dispose();
      _player = null;
      _videoController = null;
      _isLoading = false;
      _hasError = false;
      
      // 如果是视频，加载新的缩略图
      if (widget.file.fileType == MediaFileTypePB.Video) {
        _initVideoThumbnail();
      }
    }
  }

  Future<void> _initVideoThumbnail() async {
    if (_isLoading || !mounted) return;
    
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final player = Player();
      final videoController = VideoController(player);
      
      // 打开视频文件，但不自动播放
      await player.open(
        Media(widget.file.url),
        play: false, // 不自动播放
      );
      
      // 立即暂停
      await player.pause();
      
      // 定位到第一帧（0ms）
      await player.seek(Duration.zero);
      
      // 等待一小段时间让第一帧渲染
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (mounted) {
        setState(() {
          _player = player;
          _videoController = videoController;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading video thumbnail: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: _getFileTypeColor(widget.file.fileType).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _getFileTypeColor(widget.file.fileType).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: _buildThumbnailContent(context),
      ),
    );
  }

  Widget _buildThumbnailContent(BuildContext context) {
    switch (widget.file.fileType) {
      case MediaFileTypePB.Image:
        return _buildImageThumbnail();
      case MediaFileTypePB.Video:
        return _buildVideoThumbnail();
      default:
        return _buildIconThumbnail();
    }
  }

  /// 图片缩略图
  Widget _buildImageThumbnail() {
    final imageFile = File(widget.file.url);
    
    if (!imageFile.existsSync()) {
      return _buildIconThumbnail();
    }

    return Image.file(
      imageFile,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return _buildIconThumbnail();
      },
    );
  }

  /// 视频缩略图（显示视频第一帧）
  Widget _buildVideoThumbnail() {
    // 如果正在加载
    if (_isLoading) {
      return _buildLoadingThumbnail();
    }
    
    // 如果加载失败或有错误
    if (_hasError || _videoController == null) {
      return _buildPlaceholderVideoIcon();
    }
    
    // 显示视频第一帧
    return Stack(
      fit: StackFit.expand,
      children: [
        Video(
          controller: _videoController!,
          controls: NoVideoControls,
          fit: BoxFit.cover,
        ),
        // 添加播放图标覆盖层
        Center(
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: widget.size * 0.3,
            ),
          ),
        ),
      ],
    );
  }

  /// 加载中的缩略图
  Widget _buildLoadingThumbnail() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          color: _getFileTypeColor(widget.file.fileType).withOpacity(0.2),
        ),
        SizedBox(
          width: widget.size * 0.4,
          height: widget.size * 0.4,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              _getFileTypeColor(widget.file.fileType),
            ),
          ),
        ),
      ],
    );
  }

  /// 占位符视频图标（加载失败时显示）
  Widget _buildPlaceholderVideoIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          color: _getFileTypeColor(widget.file.fileType).withOpacity(0.2),
        ),
        Icon(
          Icons.play_circle_filled,
          color: _getFileTypeColor(widget.file.fileType),
          size: widget.size * 0.5,
        ),
      ],
    );
  }

  /// 图标缩略图（用于文档、音频等）
  Widget _buildIconThumbnail() {
    return Center(
      child: Icon(
        _getFileTypeIcon(widget.file.fileType),
        color: _getFileTypeColor(widget.file.fileType),
        size: widget.size * 0.5,
      ),
    );
  }

  IconData _getFileTypeIcon(MediaFileTypePB fileType) {
    switch (fileType) {
      case MediaFileTypePB.Document:
        return Icons.picture_as_pdf;
      case MediaFileTypePB.Image:
        return Icons.image;
      case MediaFileTypePB.Video:
        return Icons.play_arrow;
      case MediaFileTypePB.Audio:
        return Icons.audiotrack;
      case MediaFileTypePB.Archive:
        return Icons.archive;
      case MediaFileTypePB.Text:
        return Icons.description;
      case MediaFileTypePB.Other:
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileTypeColor(MediaFileTypePB fileType) {
    switch (fileType) {
      case MediaFileTypePB.Document:
        return Colors.red;
      case MediaFileTypePB.Image:
        return Colors.blue;
      case MediaFileTypePB.Video:
        return Colors.purple;
      case MediaFileTypePB.Audio:
        return Colors.orange;
      case MediaFileTypePB.Archive:
        return Colors.brown;
      case MediaFileTypePB.Text:
        return Colors.green;
      case MediaFileTypePB.Other:
      default:
        return Colors.grey;
    }
  }
}

