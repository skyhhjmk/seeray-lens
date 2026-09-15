import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:webview_cef/webview_cef.dart' as cef;
import 'package:webview_flutter/webview_flutter.dart';

class CaptureView extends StatefulWidget {
  const CaptureView({
    required this.apiBase,
    required this.siteId,
    required this.resourceId,
    required this.accessToken,
    required this.mode,
    super.key,
  });

  final String apiBase, siteId, resourceId, accessToken, mode;

  @override
  State<CaptureView> createState() => _CaptureViewState();
}

class _CaptureViewState extends State<CaptureView> {
  static Future<void>? _cefReady;
  WebViewController? _controller;
  cef.WebViewController? _desktopController;
  HttpServer? _desktopServer;
  String? _desktopUrl;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CaptureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiBase != widget.apiBase ||
        oldWidget.siteId != widget.siteId ||
        oldWidget.resourceId != widget.resourceId ||
        oldWidget.accessToken != widget.accessToken ||
        oldWidget.mode != widget.mode) {
      _load();
    }
  }

  @override
  void dispose() {
    final controller = _desktopController;
    if (controller != null) unawaited(controller.dispose());
    _desktopServer?.close(force: true);
    super.dispose();
  }

  Future<void> _load() async {
    final previousController = _desktopController;
    _desktopController = null;
    if (previousController != null) await previousController.dispose();
    final previousServer = _desktopServer;
    _desktopServer = null;
    await previousServer?.close(force: true);
    if (mounted) {
      setState(() {
        _error = null;
        _controller = null;
        _desktopUrl = null;
      });
    }
    try {
      final path = widget.mode == 'recording'
          ? '/api/v1/sites/${widget.siteId}/heatmaps/recordings/${widget.resourceId}'
          : '/api/v1/sites/${widget.siteId}/heatmaps/dom-snapshots/${widget.resourceId}';
      final response = await http.get(
        Uri.parse('${widget.apiBase.replaceFirst(RegExp(r'/$'), '')}$path'),
        headers: {
          if (widget.accessToken.isNotEmpty)
            'Authorization': 'Bearer ${widget.accessToken}',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final events = widget.mode == 'recording'
          ? <Object?>[
              for (final chunk in decoded as List<Object?>)
                ...(chunk as Map<String, Object?>)['events'] as List<Object?>,
            ]
          : decoded;
      final bundle = (await rootBundle.loadString(
        'assets/replayer.js',
      )).replaceAll('</script', r'<\/script');
      final mode = jsonEncode(widget.mode);
      final payload = jsonEncode(events).replaceAll('</script', r'<\/script');
      final html = '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body,seeray-replayer{display:block;width:100%;height:100%;margin:0;overflow:hidden;background:#fff}</style>
</head><body><div id="status" style="padding:16px;font:14px sans-serif;color:#555">Loading capture…</div><seeray-replayer></seeray-replayer></body></html>''';
      final renderScript =
          '''(() => {
  const status = document.getElementById('status');
  try {
    const element = document.querySelector('seeray-replayer');
    if (!element || typeof element.renderCapture !== 'function') {
      throw new Error('SeeRay replayer did not initialize');
    }
    element.renderCapture($payload, $mode);
    status?.remove();
  } catch (error) {
    if (status) {
      status.textContent = 'Unable to render capture: ' + String(error);
      status.style.color = '#b3261e';
    }
    console.error('SeeRay capture render failed', error);
  }
})();''';

      if (Platform.isLinux || Platform.isWindows) {
        final desktopHtml = html.replaceFirst(
          '</body>',
          '<script>$bundle</script><script>$renderScript</script></body>',
        );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final random = Random.secure();
        final secret = base64UrlEncode(
          List<int>.generate(24, (_) => random.nextInt(256)),
        ).replaceAll('=', '');
        server.listen((request) async {
          request.response.headers.set(
            HttpHeaders.cacheControlHeader,
            'no-store',
          );
          request.response.headers.contentType = ContentType.html;
          if (request.uri.path == '/$secret') {
            request.response.write(desktopHtml);
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        });
        if (!mounted) {
          await server.close(force: true);
          return;
        }
        _desktopServer = server;
        final desktopUrl =
            'http://${server.address.address}:${server.port}/$secret';
        _cefReady ??= cef.WebviewManager().initialize(
          userAgent: 'SeeRay-Lens-Admin/1.0',
        );
        await _cefReady;
        final controller = cef.WebviewManager().createWebView(
          loading: const Center(child: CircularProgressIndicator()),
        );
        controller.setWebviewListener(
          cef.WebviewEventsListener(
            onConsoleMessage: (level, message, source, line) {
              debugPrint('[SeeRay CEF][$level] $message ($source:$line)');
            },
          ),
        );
        await controller.initialize(desktopUrl);
        if (!mounted) {
          await controller.dispose();
          await server.close(force: true);
          return;
        }
        _desktopController = controller;
        setState(() => _desktopUrl = desktopUrl);
        return;
      }

      final mobileHtml = html.replaceFirst(
        '</body>',
        '<script>$bundle</script><script>$renderScript</script></body>',
      );

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..enableZoom(false)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) =>
                request.url == 'about:blank' || request.url.startsWith('data:')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent,
          ),
        );
      await controller.loadHtmlString(mobileHtml);
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _controller = null;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('Unable to render capture: $_error'));
    }
    final desktopUrl = _desktopUrl;
    final desktopController = _desktopController;
    if (desktopUrl != null && desktopController != null) {
      return ValueListenableBuilder<bool>(
        valueListenable: desktopController,
        builder: (context, ready, child) => ready
            ? desktopController.webviewWidget
            : desktopController.loadingWidget,
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return WebViewWidget(controller: controller);
  }
}
