/*
 	  * Copyright (C) 2026 Huawei Device Co., Ltd.
 	  * Licensed under the Apache License, Version 2.0 (the "License");

 	  * you may not use this file except in compliance with the License.
 	  * You may obtain a copy of the License at
 	  *
 	  *     http://www.apache.org/licenses/LICENSE-2.0
 	  *
 	  * Unless required by applicable law or agreed to in writing, software
 	  * distributed under the License is distributed on an "AS IS" BASIS,
 	  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 	  * See the License for the specific language governing permissions and
 	  * limitations under the License.
 	  */

/// 单独测试 5 个旧版/基础接口的 Demo 页面
///
/// 覆盖接口：
///   - pickImage()       选择单张图片（返回 PickedFile）
///   - pickMultiImage()  选择多张图片（返回 PickedFile 列表）
///   - pickVideo()       选择单个视频（返回 PickedFile）
///   - getImage()        获取单张图片（返回 XFile）
///   - getMultiImage()   获取多张图片（返回 XFile 列表）

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker_ohos/image_picker_ohos.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

void main() {
  runApp(const LegacyApiApp());
}

class LegacyApiApp extends StatelessWidget {
  const LegacyApiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Legacy API Demo',
      home: LegacyApiHomePage(title: 'Legacy API Test'),
    );
  }
}

class LegacyApiHomePage extends StatefulWidget {
  const LegacyApiHomePage({super.key, this.title});

  final String? title;

  @override
  State<LegacyApiHomePage> createState() => _LegacyApiHomePageState();
}

class _LegacyApiHomePageState extends State<LegacyApiHomePage> {
  final ImagePickerPlatform _picker = ImagePickerPlatform.instance;

  // 预览文件列表（统一用 XFile 存储）
  List<XFile>? _mediaFileList;
  bool _isVideo = false;

  // 各接口结果文本
  String _resultText = '';

  bool _loading = false;
  VideoPlayerController? _controller;

  void _setMediaFileList(XFile? file) {
    _mediaFileList = file == null ? null : <XFile>[file];
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // ─────────────────────── 1. pickImage ───────────────────────

  Future<void> _testPickImage() async {
    setState(() => _loading = true);
    try {
      final PickedFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 80,
      );
      setState(() {
        _isVideo = false;
        if (file != null) {
          _mediaFileList = <XFile>[XFile(file.path)];
          _resultText = '✅ pickImage 成功\n路径: ${file.path}';
        } else {
          _resultText = '⚠️ pickImage: 用户取消';
          _mediaFileList = null;
        }
      });
    } catch (e) {
      setState(() {
        _resultText = '❌ pickImage 错误: $e';
        _mediaFileList = null;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  // ─────────────────────── 2. pickMultiImage ───────────────────────

  Future<void> _testPickMultiImage() async {
    setState(() => _loading = true);
    try {
      final List<PickedFile>? files = await _picker.pickMultiImage(
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 80,
      );
      setState(() {
        _isVideo = false;
        if (files == null || files.isEmpty) {
          _resultText = '⚠️ pickMultiImage: 用户取消或空结果';
          _mediaFileList = null;
        } else {
          _mediaFileList = files.map((f) => XFile(f.path)).toList();
          _resultText =
              '✅ pickMultiImage 共 ${files.length} 张\n${files.map((f) => f.path).join('\n')}';
        }
      });
    } catch (e) {
      setState(() {
        _resultText = '❌ pickMultiImage 错误: $e';
        _mediaFileList = null;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  // ─────────────────────── 3. pickVideo ───────────────────────

  Future<void> _testPickVideo() async {
    setState(() => _loading = true);
    try {
      final PickedFile? file = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 15),
      );
      _controller?.dispose();
      _controller = null;
      setState(() {
        _isVideo = true;
        if (file != null) {
          _mediaFileList = <XFile>[XFile(file.path)];
          _resultText = '✅ pickVideo 成功\n路径: ${file.path}';
        } else {
          _resultText = '⚠️ pickVideo: 用户取消';
          _mediaFileList = null;
        }
      });
      if (file != null) {
        _initVideoPlayer();
      }
    } catch (e) {
      setState(() {
        _resultText = '❌ pickVideo 错误: $e';
        _mediaFileList = null;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  // ─────────────────────── 4. getImage ───────────────────────

  Future<void> _testGetImage() async {
    setState(() => _loading = true);
    try {
      final XFile? file = await _picker.getImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 80,
      );
      setState(() {
        _isVideo = false;
        if (file != null) {
          _mediaFileList = <XFile>[file];
          _resultText = '✅ getImage 成功\n路径: ${file.path}';
        } else {
          _resultText = '⚠️ getImage: 用户取消';
          _mediaFileList = null;
        }
      });
    } catch (e) {
      setState(() {
        _resultText = '❌ getImage 错误: $e';
        _mediaFileList = null;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  // ─────────────────────── 5. getMultiImage ───────────────────────

  Future<void> _testGetMultiImage() async {
    setState(() => _loading = true);
    try {
      final List<XFile>? files = await _picker.getMultiImage(
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 80,
      );
      setState(() {
        _isVideo = false;
        if (files == null || files.isEmpty) {
          _resultText = '⚠️ getMultiImage: 用户取消或空结果';
          _mediaFileList = null;
        } else {
          _mediaFileList = files;
          _resultText =
              '✅ getMultiImage 共 ${files.length} 张\n${files.map((f) => f.path).join('\n')}';
        }
      });
    } catch (e) {
      setState(() {
        _resultText = '❌ getMultiImage 错误: $e';
        _mediaFileList = null;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  // ─────────────────────── 预览组件 ───────────────────────

  Widget _previewImages() {
    if (_mediaFileList == null || _mediaFileList!.isEmpty) {
      return const Center(
        child: Text(
          '尚未选择文件，点击下方按钮开始测试',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      itemCount: _mediaFileList!.length,
      itemBuilder: (context, index) {
        final XFile image = _mediaFileList![index];
        return Padding(
          padding: const EdgeInsets.all(4.0),
          child: Image.file(
            File(image.path),
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Center(child: Text('图片无法加载')),
          ),
        );
      },
    );
  }

  void _initVideoPlayer() {
    if (_mediaFileList == null || _mediaFileList!.isEmpty) return;
    _controller = VideoPlayerController.file(File(_mediaFileList!.first.path))
      ..initialize()
          .then((_) {
            setState(() {});
            _controller!.play();
          })
          .catchError((error) {
            _controller?.dispose();
            _controller = null;
          });
  }

  Widget _previewVideo() {
    if (_mediaFileList == null || _mediaFileList!.isEmpty) {
      return const Center(
        child: Text(
          '尚未选择视频，点击下方按钮开始测试',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: Colors.grey),
        ),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: VideoPlayer(_controller!),
      ),
    );
  }

  Widget _handlePreview() {
    if (_isVideo) {
      return _previewVideo();
    }
    return _previewImages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Legacy API Test'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回主页面',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 上半部分：预览区域
                Expanded(flex: 3, child: _handlePreview()),
                // 分割线
                const Divider(height: 1),
                // 下半部分：结果信息
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _resultText.isEmpty ? '点击下方按钮开始测试' : _resultText,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          FloatingActionButton(
            heroTag: 'pickImage',
            tooltip: 'pickImage',
            onPressed: _loading ? null : _testPickImage,
            child: const Icon(Icons.photo),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: FloatingActionButton(
              heroTag: 'pickMultiImage',
              tooltip: 'pickMultiImage',
              onPressed: _loading ? null : _testPickMultiImage,
              child: const Icon(Icons.photo_library),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: FloatingActionButton(
              backgroundColor: Colors.red,
              heroTag: 'pickVideo',
              tooltip: 'pickVideo',
              onPressed: _loading ? null : _testPickVideo,
              child: const Icon(Icons.video_library),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: FloatingActionButton(
              heroTag: 'getImage',
              tooltip: 'getImage',
              onPressed: _loading ? null : _testGetImage,
              child: const Icon(Icons.image),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: FloatingActionButton(
              backgroundColor: Colors.red,
              heroTag: 'getMultiImage',
              tooltip: 'getMultiImage',
              onPressed: _loading ? null : _testGetMultiImage,
              child: const Icon(Icons.collections),
            ),
          ),
        ],
      ),
    );
  }
}
