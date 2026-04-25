import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/vk_api_service.dart';

class VkAuthWebView extends StatefulWidget {
  const VkAuthWebView({super.key});

  @override
  State<VkAuthWebView> createState() => _VkAuthWebViewState();
}

class _VkAuthWebViewState extends State<VkAuthWebView> {
  late final WebViewController _controller;
  bool _loading = true;

  static const String _redirectUri = 'https://oauth.vk.com/blank.html';
  static const String _scope = 'audio,offline';

  String get _authUrl =>
      'https://oauth.vk.com/authorize?'
      'client_id=${VkApiService.appId}'
      '&display=mobile'
      '&redirect_uri=$_redirectUri'
      '&scope=$_scope'
      '&response_type=token'
      '&v=${VkApiService.apiVersion}';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(VkApiService.userAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            final url = request.url;
            if (url.startsWith(_redirectUri)) {
              _handleRedirect(url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_authUrl));
  }

  void _handleRedirect(String url) {
    // URL format: https://oauth.vk.com/blank.html#access_token=TOKEN&expires_in=0&user_id=USERID
    final fragment = Uri.parse(url.replaceFirst('#', '?')).queryParameters;
    final token = fragment['access_token'];
    final userId = fragment['user_id'];

    if (token != null && userId != null) {
      Navigator.of(context).pop({
        'access_token': token,
        'user_id': int.tryParse(userId),
      });
    } else {
      Navigator.of(context).pop(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Вход через VK'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
