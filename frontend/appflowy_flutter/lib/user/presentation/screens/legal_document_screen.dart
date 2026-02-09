import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    this.url,
    this.content
  });

  final String title;
  final String? url;
  final String? content;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: url != null && url?.isNotEmpty == true ? InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url ?? "")),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          supportZoom: true,
        ),
      ) : LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: SingleChildScrollView(
              child: Container(
                width: constraints.maxWidth,
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                padding: const EdgeInsets.all(16.0),
                child: SelectableText(
                  content ?? '',
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

