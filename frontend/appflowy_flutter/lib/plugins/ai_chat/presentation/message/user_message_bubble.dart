import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_entity.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_member_bloc.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../chat_avatar.dart';
import '../layout_define.dart';

class ChatUserMessageBubble extends StatefulWidget {
  const ChatUserMessageBubble({
    super.key,
    required this.message,
    required this.child,
    this.files = const [],
    this.images = const [],
    this.imagePaths = const [],
  });

  final Message message;
  final Widget child;
  final List<ChatFile> files;
  final List<String> images;
  final List<String> imagePaths;

  @override
  State<ChatUserMessageBubble> createState() => _ChatUserMessageBubbleState();
}

class _ChatUserMessageBubbleState extends State<ChatUserMessageBubble> {
  @override
  void initState() {
    super.initState();
    context
        .read<ChatMemberBloc>()
        .add(ChatMemberEvent.getMemberInfo(widget.message.author.id));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AIChatUILayout.messageMargin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 显示图片缩略图
          if (widget.images.isNotEmpty || widget.imagePaths.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(right: 32),
              child: _MessageImageList(
                images: widget.images,
                imagePaths: widget.imagePaths,
              ),
            ),
            const VSpace(6),
          ],
          // 显示文件列表
          if (widget.files.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(right: 32),
              child: _MessageFileList(files: widget.files),
            ),
            const VSpace(6),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Spacer(),
              _buildBubble(context),
              const HSpace(DesktopAIChatSizes.avatarAndChatBubbleSpacing),
              _buildAvatar(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return BlocBuilder<ChatMemberBloc, ChatMemberState>(
      builder: (context, state) {
        final member = state.members[widget.message.author.id];
        return SelectionContainer.disabled(
          child: ChatUserAvatar(
            iconUrl: member?.info.avatarUrl ?? "",
            name: member?.info.name ?? "",
          ),
        );
      },
    );
  }

  Widget _buildBubble(BuildContext context) {
    return Flexible(
      flex: 5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16.0)),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 8.0,
        ),
        child: widget.child,
      ),
    );
  }
}

class _MessageFileList extends StatelessWidget {
  const _MessageFileList({required this.files});

  final List<ChatFile> files;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = files
        .map(
          (file) => _MessageFile(
            file: file,
          ),
        )
        .toList();

    return Wrap(
      direction: Axis.vertical,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 6,
      runSpacing: 6,
      children: children,
    );
  }
}

class _MessageFile extends StatelessWidget {
  const _MessageFile({required this.file});

  final ChatFile file;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowySvg(
              FlowySvgs.page_m,
              size: const Size.square(16),
              color: Theme.of(context).hintColor,
            ),
            const HSpace(6),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: FlowyText(
                  file.fileName,
                  fontSize: 12,
                  maxLines: 6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 图片缩略图列表组件
class _MessageImageList extends StatelessWidget {
  const _MessageImageList({required this.images, this.imagePaths = const []});

  final List<String> images; // base64 图片
  final List<String> imagePaths; // 文件路径图片

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = [];

    // 添加 base64 或 URL 图片
    for (final image in images) {
      children.add(_MessageImage(imageData: image));
    }

    // 添加文件路径图片
    for (final path in imagePaths) {
      children.add(_MessageImageFromPath(filePath: path));
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: children,
    );
  }
}

/// 单个图片缩略图组件（支持 base64 和 HTTP URL 两种来源）
class _MessageImage extends StatefulWidget {
  const _MessageImage({required this.imageData});

  final String imageData;

  @override
  State<_MessageImage> createState() => _MessageImageState();
}

class _MessageImageState extends State<_MessageImage> {
  MemoryImage? _memoryImage;

  bool get _isUrl =>
      widget.imageData.startsWith('http://') ||
      widget.imageData.startsWith('https://');

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  @override
  void didUpdateWidget(covariant _MessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageData != widget.imageData) {
      _decodeImage();
    }
  }

  void _decodeImage() {
    if (_isUrl) {
      _memoryImage = null;
      return;
    }

    try {
      _memoryImage = MemoryImage(base64Decode(widget.imageData));
    } catch (_) {
      _memoryImage = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary 隔离图片重绘，避免输入法动画影响
    return RepaintBoundary(
      child: _isUrl ? _buildNetworkImage(context) : _buildMemoryImage(context),
    );
  }

  Widget _buildNetworkImage(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFullNetworkImage(context),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 120, maxHeight: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: CachedNetworkImage(
          imageUrl: widget.imageData,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => _buildPlaceholder(context),
        ),
      ),
    );
  }

  Widget _buildMemoryImage(BuildContext context) {
    final memoryImage = _memoryImage;
    return GestureDetector(
      onTap: memoryImage == null
          ? null
          : () => _showFullMemoryImage(context, memoryImage),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 120, maxHeight: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: memoryImage != null
            ? Image(
                image: memoryImage,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _buildPlaceholder(context),
              )
            : _buildPlaceholder(context),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Theme.of(context).hintColor,
        size: 32,
      ),
    );
  }

  void _showFullNetworkImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: widget.imageData,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            _closeButton(context),
          ],
        ),
      ),
    );
  }

  void _showFullMemoryImage(BuildContext context, MemoryImage image) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image(
                  image: image,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
            ),
            _closeButton(context),
          ],
        ),
      ),
    );
  }

  Widget _closeButton(BuildContext context) {
    return Positioned(
      top: 8,
      right: 8,
      child: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.close, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// 从文件路径加载图片的组件
class _MessageImageFromPath extends StatefulWidget {
  const _MessageImageFromPath({required this.filePath});

  final String filePath;

  @override
  State<_MessageImageFromPath> createState() => _MessageImageFromPathState();
}

class _MessageImageFromPathState extends State<_MessageImageFromPath> {
  late FileImage _image;

  @override
  void initState() {
    super.initState();
    _image = FileImage(File(widget.filePath));
  }

  @override
  void didUpdateWidget(covariant _MessageImageFromPath oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _image = FileImage(File(widget.filePath));
    }
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary 隔离图片重绘
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _showFullImage(context),
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 120,
            maxHeight: 120,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image(
            image: _image,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _buildPlaceholder(context),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Theme.of(context).hintColor,
        size: 32,
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image(
                  image: _image,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
