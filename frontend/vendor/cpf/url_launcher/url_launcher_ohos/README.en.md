# url_launcher_ohos

This project is developed based on [url_launcher](https://pub.dev/packages/url_launcher).

## Introduction

url_launcher_ohos is the OpenHarmony platform implementation of the url_launcher plugin, used to launch URLs in OpenHarmony applications. It supports opening web links in the system browser or in-app WebView, and also supports system functions such as making phone calls, sending SMS, and opening the app store.

## Installation

Navigate to your project directory and add the following dependency to `pubspec.yaml`:

```yaml
dependencies:
  url_launcher_ohos:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/url_launcher/url_launcher_ohos
      # ref: url_launcher_v6.1.11-ohos-1.0.1
      ref: TAG  #   Select a TAG according to the TAG version table below
```

Run the command:

```bash
flutter pub get
```

**TAG Version Table**

| Flutter Version | TAG1 | TAG2 | Branch |
| :--- | :--- | :--- | :--- |
| 3.41 | `url_launcher_v6.3.2-ohos-1.0.0` | `url_launcher_v6.3.2-ohos-1.0.1` | `br_url_launcher-v6.3.2_ohos` |
| 3.35 | `url_launcher_v6.3.2-ohos-1.0.0` | `url_launcher_v6.3.2-ohos-1.0.1` | `br_url_launcher-v6.3.2_ohos` |
| 3.27 | `url_launcher_v6.3.1-ohos-1.0.0` | `url_launcher_v6.3.1-ohos-1.0.1` | `br_url_launcher_v6.3.1_ohos` |
| 3.22 | `url_launcher_v6.3.0-ohos-1.0.0` | `url_launcher_v6.3.0-ohos-1.0.1` | `br_url_launcher-v6.3.0_ohos` |
| 3.7 | `url_launcher_v6.1.11-ohos-1.0.0` | `url_launcher_v6.1.11-ohos-1.0.1` | `master` |

## Constraints and Limitations

### Compatibility

Tested and passed on the following versions:

1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.0.830; ROM: 6.1.0.117 SP6;

### Permission Requirements

This plugin requires the following permissions:

**Add permissions in module.json5 under the entry directory**

Open `entry/src/main/module.json5` and add:

```json
"requestPermissions": [
  {
    "name": "ohos.permission.INTERNET",
    "reason": "$string:network_reason",
    "usedScene": {
      "abilities": [
        "EntryAbility"  // Replace with your app's actual entry Ability name
      ],
      "when": "inuse"
    }
  }
]
```

**Add the reason for requesting the above permissions under the entry directory**

Open `entry/src/main/resources/base/element/string.json` and add:

```json
{
  "string": [
    {
      "name": "network_reason",
      "value": "Use network to access web pages"
    }
  ]
}
```

## Usage Example

The following example shows how to use url_launcher to open a web link in the browser:

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'URL Launcher Demo',
      home: const UrlLaunchDemo(),
    );
  }
}

class UrlLaunchDemo extends StatefulWidget {
  const UrlLaunchDemo({super.key});

  @override
  State<UrlLaunchDemo> createState() => _UrlLaunchDemoState();
}

class _UrlLaunchDemoState extends State<UrlLaunchDemo> {
  final Uri _url = Uri.parse('https://www.openharmony.cn');

  /// Open URL in system browser
  Future<void> _launchInBrowser() async {
    if (!await launchUrl(_url, mode: LaunchMode.externalApplication)) {
      // Show a friendly message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot open link: $_url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('URL Launcher Example'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: _launchInBrowser,
          child: const Text('Open in Browser'),
        ),
      ),
    );
  }
}
```

## Usage Instructions

### 1. Open URL in System Browser

Use the `launchUrl` method with `mode: LaunchMode.externalApplication` to open the link in the system browser:

```dart
await launchUrl(
  Uri.parse('https://www.openharmony.cn'),
  mode: LaunchMode.externalApplication,
);
```

### 2. Open URL in In-App WebView

Set `mode: LaunchMode.inAppWebView` to open the link in an in-app WebView:

```dart
await launchUrl(
  Uri.parse('https://www.openharmony.cn'),
  mode: LaunchMode.inAppWebView,
  webViewConfiguration: InAppWebViewConfiguration(
    enableJavaScript: true,
    enableDomStorage: true,
    headers: {
      'harmony_browser_page': 'pages/LaunchInAppPage' // OHOS-specific configuration, specifying the in-app WebView page path
    },
  ),
);
```

> **Note:** On the OHOS platform, when using WebView mode, you must add the `harmony_browser_page` key in `headers` to specify the in-app WebView page path, and create the corresponding page in the OHOS project and configure the route.

### 3. Check whether a URL can be launched

Before launching a URL, you can use the `canLaunchUrl` method to check whether the device supports handling the URL:

```dart
if (await canLaunchUrl(Uri.parse('https://www.openharmony.cn'))) {
  await launchUrl(Uri.parse('https://www.openharmony.cn'));
}
```

### 4. Close WebView

After opening a URL in WebView mode, you can call `closeInAppWebView` to close the WebView:

```dart
await closeInAppWebView();
```

### 5. Make a phone call

Use the `tel:` scheme to launch the system dialer:

```dart
await launchUrl(Uri(scheme: 'tel', path: '1234567890'));
```

### 6. Send SMS

Use the `sms:` scheme to launch the SMS application:

```dart
await launchUrl(Uri(scheme: 'sms', path: '5555555555'));
```

### 7. Open the app store

Use the `store:` scheme to open the app store:

```dart
await launchUrl(
  Uri.parse('AppGallery Url'),
  mode: LaunchMode.externalApplication,
);
```

### 8. Send email

Use the `mailto:` scheme to launch the email application:

```dart
await launchUrl(Uri(scheme: 'mailto', path: 'example@example.com'));
```

### Supported URL Schemes

| Scheme | Description |
|--------|-------------|
| `http:` / `https:` | Open web page in system browser |
| `tel:` | Launch dialer |
| `sms:` | Launch SMS application |
| `mailto:` | Launch email application |
| `file:` | Open local file (sandbox path only) |
| `store:` | Open app store |
| `store://enterprise` | Enterprise installation |

> For custom URL schemes (e.g., `amapuri://`), you need to add the corresponding scheme to `querySchemes` in `module.json5` for `canLaunchUrl` to work correctly.

## API Reference

> [!TIP] An **ohos Support** value of **yes** means the ohos platform supports this property; **no** means not supported; **partially** means partially supported. The usage method is consistent across platforms, and the behavior is aligned with iOS or Android.

#### UrlLauncherPlatform

| Name | Type | Parameter Type | Return Value | OHOS Support | Description |
|------|------|----------------|--------------|--------------|-------------|
| canLaunch() | Method | String url | Future\<bool\> | yes | Checks whether the device can launch a specific URL scheme |
| launch | Method | String url,<br/>required bool useSafariVC,<br/>required bool useWebView,<br/>required bool enableJavaScript,<br/>required bool enableDomStorage,<br/>required bool universalLinksOnly,<br/>required Map\<String, String\> headers,<br/>String? webOnlyWindowName | Future\<bool\> | yes | Specifies jump parameters and URL path |
| launchUrl() | Method | String url,<br/>[LaunchOptions](#LaunchOptions) options | Future\<bool\> | yes | Specifies the browser to jump to and opens the URL |
| closeWebView() | Method | / | Future\<void\> | yes | Closes the WebView page |

#### LaunchOptions

| Name | Type | Parameter Type | Return Value | OHOS Support | Description |
|------|------|----------------|--------------|--------------|-------------|
| mode | Property | / | [PreferredLaunchMode](#PreferredLaunchMode) | yes | The mode required to launch the URL |
| webViewConfiguration | Property | / | [InAppWebViewConfiguration](#InAppWebViewConfiguration) | yes | Configures the WebView in [PreferredLaunchMode.inAppWebView] mode |
| webOnlyWindowName | Property | / | String? | yes | The default behavior when unset should be to open the URL in a new tab |

#### PreferredLaunchMode

| Name | Type | Parameter Type | Return Value | OHOS Support | Description |
|------|------|----------------|--------------|--------------|-------------|
| platformDefault | Enum value | / | enum | yes | The launch mode is determined by the platform |
| inAppWebView | Enum value | / | enum | yes | Loads in an in-app WebView |
| externalApplication | Enum value | / | enum | yes | Passes the URL to an external application for handling |
| externalNonBrowserApplication | Enum value | / | enum | yes | Passes the URL to an external non-browser application for handling |

#### InAppWebViewConfiguration

| Name | Type | Parameter Type | Return Value | OHOS Support | Description |
|------|------|----------------|--------------|--------------|-------------|
| enableJavaScript | Property | / | bool | yes | When set to true, enables JavaScript in the WebView |
| enableDomStorage | Property | / | bool | yes | When set to true, enables DOM storage in the WebView |
| headers | Property | / | Map\<String, String\> | yes | Request headers used when opening the URL in a web page. On OHOS, use this parameter to pass `harmony_browser_page` to specify the WebView page path |

#### launch method parameters

| Name | Type | Parameter Type | Return Value | OHOS Support | Description |
|------|------|----------------|--------------|--------------|-------------|
| url | Parameter | String | / | yes | Jump address |
| useSafariVC | Parameter | bool | / | yes | Whether to open the URL in the Safari view controller |
| useWebView | Parameter | bool | / | yes | If set to false, opens the URL in the device's default browser; otherwise, opens the URL in a WebView |
| enableJavaScript | Parameter | bool | / | yes | When set to true, enables JavaScript in the WebView |
| enableDomStorage | Parameter | bool | / | yes | When set to true, enables DOM storage in the WebView |
| universalLinksOnly | Parameter | bool | / | yes | Controls whether to open web pages only through Universal Links |
| headers | Parameter | Map\<String, String\> | / | yes | Request headers used when opening the URL in a web page |
| webOnlyWindowName | Parameter | String? | / | yes | The default behavior when unset should be to open the URL in a new tab |

## Known Issues

None

## Directory Structure

```
flutter_packages/
└── packages/
    └── url_launcher/
        └── url_launcher_ohos/
            ├── lib/                          # Dart code directory
            │   ├── src/
            │   │   └── messages.g.dart       # Platform channel message definitions
            │   └── url_launcher_ohos.dart    # Plugin main entry
            ├── ohos/                         # OpenHarmony native code directory
            │   ├── index.ets                 # Native plugin export entry
            │   └── src/main/ets/components/plugin/
            │       ├── InAppBrowser.ets      # In-app browser implementation
            │       ├── Messages.ets          # Message handling
            │       ├── UrlLauncher.ets       # URL launcher implementation
            │       └── UrlLauncherPlugin.ets # Plugin entry
            ├── example/                      # Example app
            │   ├── lib/main.dart             # Example code
            │   └── ohos/                     # Example app native code
            ├── test/                         # Unit tests
            ├── test_driver/                  # Integration test driver
            ├── integration_test/             # Integration tests
            ├── pubspec.yaml                  # Package configuration file
            ├── README.md                     # Chinese documentation
            └── README.en.md                  # English documentation
```

## Contributing

If you find any issues during use, please submit an [Issue](https://gitcode.com/CPF-Flutter/flutter_packages/issues). PRs are also welcome.


## License

This project is licensed under [BSD-3-Clause](LICENSE), feel free to use and contribute.
