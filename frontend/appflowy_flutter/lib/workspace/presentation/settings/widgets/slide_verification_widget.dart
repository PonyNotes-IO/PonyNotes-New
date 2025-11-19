import 'package:flutter/material.dart';

/// 滑块验证组件（自实现简化版）
/// 用户需要将滑块拖到右侧以完成验证
class SlideVerificationWidget extends StatefulWidget {
  const SlideVerificationWidget({
    super.key,
    required this.onVerificationSuccess,
    this.height = 50,
  });

  /// 验证成功的回调
  final VoidCallback onVerificationSuccess;
  
  /// 组件高度
  final double height;

  @override
  State<SlideVerificationWidget> createState() => _SlideVerificationWidgetState();
}

class _SlideVerificationWidgetState extends State<SlideVerificationWidget> {
  double _sliderPosition = 0.0;
  bool _isVerified = false;
  bool _isDragging = false;
  double _maxWidth = 300.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxWidth = constraints.maxWidth - 50;
        
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: _isVerified 
                ? const Color(0xFF00C853).withOpacity(0.1)
                : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isVerified 
                  ? const Color(0xFF00C853)
                  : Colors.grey.withOpacity(0.3),
            ),
          ),
          child: Stack(
            children: [
              // 背景进度条
              if (_sliderPosition > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _sliderPosition + 45,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isVerified
                            ? [
                                const Color(0xFF00C853).withOpacity(0.3),
                                const Color(0xFF00C853).withOpacity(0.1),
                              ]
                            : [
                                Colors.blue.withOpacity(0.3),
                                Colors.blue.withOpacity(0.1),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              
              // 提示文字
              Center(
                child: Text(
                  _isVerified ? '验证成功' : '按住滑块，拖动到右边',
                  style: TextStyle(
                    fontSize: 14,
                    color: _isVerified 
                        ? const Color(0xFF00C853)
                        : Colors.grey[600],
                    fontWeight: _isVerified ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              
              // 滑块
              Positioned(
                left: _sliderPosition,
                top: 2,
                bottom: 2,
                child: GestureDetector(
                  onHorizontalDragStart: (details) {
                    if (!_isVerified) {
                      setState(() {
                        _isDragging = true;
                      });
                    }
                  },
                  onHorizontalDragUpdate: (details) {
                    if (!_isVerified) {
                      setState(() {
                        _sliderPosition += details.delta.dx;
                        _sliderPosition = _sliderPosition.clamp(0.0, _maxWidth);
                      });
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    setState(() {
                      _isDragging = false;
                    });
                    
                    // 检查是否拖到了右侧（超过80%即可）
                    if (_sliderPosition > _maxWidth * 0.8 && !_isVerified) {
                      setState(() {
                        _isVerified = true;
                        _sliderPosition = _maxWidth;
                      });
                      widget.onVerificationSuccess();
                    } else if (!_isVerified) {
                      // 未完成验证，滑块回弹
                      setState(() {
                        _sliderPosition = 0.0;
                      });
                    }
                  },
                  child: Container(
                    width: 45,
                    decoration: BoxDecoration(
                      color: _isVerified 
                          ? const Color(0xFF00C853)
                          : (_isDragging ? Colors.blue : Colors.white),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _isVerified 
                            ? const Color(0xFF00C853)
                            : Colors.grey.withOpacity(0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isVerified ? Icons.check : Icons.arrow_forward_ios,
                      color: _isVerified ? Colors.white : Colors.grey[600],
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
