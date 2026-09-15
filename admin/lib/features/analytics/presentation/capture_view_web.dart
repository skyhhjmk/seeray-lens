import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

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
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType =
        'seeray-${widget.mode}-${widget.resourceId}-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final element =
          web.document.createElement('seeray-replayer') as web.HTMLElement;
      element.setAttribute('api-base', widget.apiBase);
      element.setAttribute('site-id', widget.siteId);
      element.setAttribute('resource-id', widget.resourceId);
      element.setAttribute('access-token', widget.accessToken);
      element.setAttribute('mode', widget.mode);
      element.style.width = '100%';
      element.style.height = '100%';
      return element;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
