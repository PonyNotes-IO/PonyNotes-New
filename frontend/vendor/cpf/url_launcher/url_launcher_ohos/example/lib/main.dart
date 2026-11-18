// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'URL Launcher',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'URL Launcher'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final UrlLauncherPlatform launcher = UrlLauncherPlatform.instance;
  bool _hasCallSupport = false;
  Future<void>? _launched;
  String _phone = '';
  String? _launchAppGalleryLog = null;

  @override
  void initState() {
    super.initState();
    // Check for phone call support.
    launcher.canLaunch('tel:123').then((bool result) {
      setState(() {
        _hasCallSupport = result;
      });
    });
  }

  Future<void> _launchInBrowser(String url) async {
    if (!await launcher.launch(
      url,
      useSafariVC: false,
      useWebView: false,
      enableJavaScript: false,
      enableDomStorage: false,
      universalLinksOnly: false,
      headers: <String, String>{},
    )) {
      throw Exception('Could not launch $url');
    }
  }

  Future<void> _launchInWebView(String url) async {
    if (!await launcher.launch(
      url,
      useSafariVC: true,
      useWebView: true,
      enableJavaScript: false,
      enableDomStorage: false,
      universalLinksOnly: false,
      headers: <String, String>{
        'my_header_key': 'my_header_value',
        'harmony_browser_page': 'pages/LaunchInAppPage'
      },
    )) {
      throw Exception('Could not launch $url');
    }
  }

  Future<void> _launchInWebViewWithJavaScript(String url) async {
    if (!await launcher.launch(
      url,
      useSafariVC: true,
      useWebView: true,
      enableJavaScript: true,
      enableDomStorage: false,
      universalLinksOnly: false,
      headers: <String, String>{
        'harmony_browser_page': 'pages/LaunchInAppPage'
      },
    )) {
      throw Exception('Could not launch $url');
    }
  }

  Future<void> _launchInWebViewWithDomStorage(String url) async {
    if (!await launcher.launch(
      url,
      useSafariVC: true,
      useWebView: true,
      enableJavaScript: false,
      enableDomStorage: true,
      universalLinksOnly: false,
      headers: <String, String>{
        'harmony_browser_page': 'pages/LaunchInAppPage'
      },
    )) {
      throw Exception('Could not launch $url');
    }
  }

  Future<void> _launchEmail(String url) async {
    if (!await launcher.launch(
      url,
      useSafariVC: false,
      useWebView: false,
      enableJavaScript: false,
      enableDomStorage: false,
      universalLinksOnly: false,
      headers: <String, String>{
        'harmony_browser_page': 'pages/LaunchInAppPage'
      },
    )) {
      throw Exception('Could not launch $url');
    }
  }

  Widget _launchStatus(BuildContext context, AsyncSnapshot<void> snapshot) {
    if (snapshot.hasError) {
      return Text('Error: ${snapshot.error}');
    } else {
      return const Text('');
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    // Use `Uri` to ensure that `phoneNumber` is properly URL-encoded.
    // Just using 'tel:$phoneNumber' would create invalid URLs in some cases,
    // such as spaces in the input, which would cause `launch` to fail on some
    // platforms.
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    await launcher.launch(
      launchUri.toString(),
      useSafariVC: false,
      useWebView: false,
      enableJavaScript: false,
      enableDomStorage: false,
      universalLinksOnly: true,
      headers: <String, String>{},
    );
  }

  Future<void> _launchAppGalleryDetails(String url) async {
    //store://appgallery.huawei.com/app/detail?id=APPID'
    if (await launcher.canLaunch(url)) {
      var result = await launcher.launchUrl(
        url,
        const LaunchOptions(mode: PreferredLaunchMode.externalApplication),
      );
      if (result) {
        setState(() {
          _launchAppGalleryLog = "Launched $url";
        });
      } else {
        setState(() {
          _launchAppGalleryLog = "Could not launch $url";
        });
      }
    } else {
      setState(() {
        _launchAppGalleryLog = "canLaunch=false, $url";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // onPressed calls using this URL are not gated on a 'canLaunch' check
    // because the assumption is that every device can launch a web URL.
    const String toLaunch = 'https://www.cylog.org/headers/';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: ListView(
        children: <Widget>[
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                    onChanged: (String text) => _phone = text,
                    decoration: const InputDecoration(
                        hintText: 'Input the phone number to launch')),
              ),
              ElevatedButton(
                onPressed: _hasCallSupport
                    ? () => setState(() {
                  _launched = _makePhoneCall(_phone);
                })
                    : null,
                child: _hasCallSupport
                    ? const Text('Make phone call')
                    : const Text('Calling not supported'),
              ),
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(toLaunch),
              ),
              ElevatedButton(
                onPressed: () => setState(() {
                  _launched = _launchInBrowser(toLaunch);
                }),
                child: const Text('Launch in browser'),
              ),
              const Padding(padding: EdgeInsets.all(16.0)),
              ElevatedButton(
                onPressed: () => setState(() {
                  _launched = _launchInWebView(toLaunch);
                }),
                child: const Text('Launch in app'),
              ),
              ElevatedButton(
                onPressed: () => setState(() {
                  _launched = _launchInWebViewWithJavaScript(toLaunch);
                }),
                child: const Text('Launch in app (JavaScript ON)'),
              ),
              ElevatedButton(
                onPressed: () => setState(() {
                  _launched = _launchInWebViewWithDomStorage(toLaunch);
                }),
                child: const Text('Launch in app (DOM storage ON)'),
              ),
              const Padding(padding: EdgeInsets.all(16.0)),
              ElevatedButton(
                onPressed: () => setState(() {
                  _launched = _launchInWebView(toLaunch);
                  Timer(const Duration(seconds: 5), () {
                    launcher.closeWebView();
                  });
                }),
                child: const Text('Launch in app + close after 5 seconds'),
              ),
              const Padding(padding: EdgeInsets.all(16.0)),
              ElevatedButton(
                onPressed: () => setState(() {
                  //此处包名应该更换成 C+AppID
                  const String url =
                      'store://appgallery.huawei.com/app/detail?id=com.huawei.hmsapp.himovie';
                  _launched = _launchAppGalleryDetails(url);
                }),
                child: const Text('Launch AppGallery Details'),
              ),
              if (_launchAppGalleryLog?.isNotEmpty ?? false)
                Text(_launchAppGalleryLog!),
              const Padding(padding: EdgeInsets.all(16.0)),
              ElevatedButton(
                onPressed: () => setState(() {
                  _launched = _launchEmail('mailto:admin@exmaple.com');
                }),
                child: const Text('Launch in email'),
              ),
              const Padding(padding: EdgeInsets.all(16.0)),
              FutureBuilder<void>(future: _launched, builder: _launchStatus),
            ],
          ),
        ],
      ),
    );
  }
}
