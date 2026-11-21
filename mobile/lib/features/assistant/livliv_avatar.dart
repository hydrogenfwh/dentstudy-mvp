// Web-only adapter for the LivLiv companion.
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'dafeiyu_avatar.dart';

class LivLivAvatar extends StatefulWidget {
  final DafeiyuPose pose;
  final String? expression;
  final int interactionSerial;
  final ValueChanged<DafeiyuPose> onPoseReady;
  const LivLivAvatar(
      {super.key,
      required this.pose,
      this.expression,
      required this.interactionSerial,
      required this.onPoseReady});

  @override
  State<LivLivAvatar> createState() => _LivLivAvatarState();
}

class _LivLivAvatarState extends State<LivLivAvatar> {
  web.HTMLIFrameElement? _frame;
  bool _loaded = false;

  void _configureFrame(Object element) {
    if (!mounted) return;
    final frame = element as web.HTMLIFrameElement;
    _frame = frame;
    frame
      ..src = 'livliv/frame.html?follow=1'
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.pointerEvents = 'none'
      ..setAttribute('title', 'LivLiv 测试角色');
    frame.onload = ((web.Event _) {
      if (!mounted) return;
      _loaded = true;
      // The Flutter platform-view wrapper otherwise captures pointer events
      // before the enclosing draggable companion can receive them.
      _makePlatformViewTransparentToPointers();
      _sendPose();
    }).toJS;
    // A cached frame can load before Flutter attaches the platform-view host.
    // Reapply once layout has mounted it so touch reaches the drag handler.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _makePlatformViewTransparentToPointers();
    });
  }

  void _makePlatformViewTransparentToPointers() {
    (_frame?.parentElement as web.HTMLElement?)?.style.pointerEvents = 'none';
    (_frame?.closest('flt-platform-view') as web.HTMLElement?)
        ?.style
        .pointerEvents = 'none';
  }

  void _sendPose() {
    if (!_loaded) return;
    _frame?.contentWindow?.postMessage(
      jsonEncode({
        'type': 'dentstudy-livliv-pose',
        'pose': widget.pose.name,
        'expression': widget.expression
      }).toJS,
      web.window.location.origin.toJS,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onPoseReady(widget.pose);
    });
  }

  @override
  void didUpdateWidget(covariant LivLivAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _makePlatformViewTransparentToPointers();
    });
    if (oldWidget.pose != widget.pose ||
        oldWidget.expression != widget.expression ||
        oldWidget.interactionSerial != widget.interactionSerial) _sendPose();
  }

  @override
  void dispose() {
    _frame?.onload = null;
    _frame?.src = 'about:blank';
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: HtmlElementView.fromTagName(tagName: 'iframe', onElementCreated: _configureFrame),
      );
}
