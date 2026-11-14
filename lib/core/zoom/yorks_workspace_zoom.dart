import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../shared/models/app_language.dart';
import 'yorks_inspection_gesture.dart';

/// The transform authority for one R35 workspace route.
///
/// This deliberately owns only a composited [TransformationController]. It
/// never changes MediaQuery, text scale, breakpoints or constraints, so a
/// 200% desktop workspace remains the same desktop layout—visually magnified.
class YorksWorkspaceZoomController extends ChangeNotifier {
  YorksWorkspaceZoomController({
    this.minimumScale = 1,
    this.maximumScale = 4,
    this.step = .125,
  }) : assert(minimumScale > 0),
       assert(maximumScale >= minimumScale),
       _transformationController = TransformationController() {
    _transformationController.addListener(notifyListeners);
  }

  final double minimumScale;
  final double maximumScale;
  final double step;
  final TransformationController _transformationController;

  /// Flutter surfaces physical mouse wheel movement in logical pixels. A
  /// conventional wheel notch is usually close to 72 pixels, while
  /// high-resolution wheels split that same physical notch over multiple
  /// smaller events. Scaling proportionally keeps both inputs predictable and
  /// caps an unusually large free-spin event at one controlled zoom step.
  static const double _wheelNotchDelta = 72;

  Size _viewportSize = Size.zero;

  TransformationController get transformationController =>
      _transformationController;

  double get currentScale => _transformationController.value
      .getMaxScaleOnAxis()
      .clamp(minimumScale, maximumScale)
      .toDouble();

  int get percentage => (currentScale * 100).round();
  bool get canZoomIn => currentScale < maximumScale - .001;
  bool get canZoomOut => currentScale > minimumScale + .001;

  /// The central scene is a stable keyboard/control focal point.
  Offset get defaultFocalPoint =>
      Offset(_viewportSize.width / 2, _viewportSize.height / 2);

  /// Updates the visual boundary without affecting the route's normal layout.
  void updateViewportSize(Size size) {
    if (size.isEmpty || size == _viewportSize) return;
    _viewportSize = size;
    setTransformation(
      _constrainedTransformation(_transformationController.value),
    );
  }

  void zoomIn({Offset? focalPoint}) =>
      setScaleAt(currentScale + step, focalPoint ?? defaultFocalPoint);

  void zoomOut({Offset? focalPoint}) =>
      setScaleAt(currentScale - step, focalPoint ?? defaultFocalPoint);

  void reset() => setTransformation(Matrix4.identity());

  void setScale(double scale, {Offset? focalPoint}) =>
      setScaleAt(scale, focalPoint ?? defaultFocalPoint);

  /// Returns a translation/scale matrix that keeps [focalPoint]'s scene
  /// coordinate under the same pixel after the scale changes.
  Matrix4 transformationForScaleAt(double scale, Offset focalPoint) {
    final targetScale = scale.clamp(minimumScale, maximumScale).toDouble();
    final scenePoint = _transformationController.toScene(focalPoint);
    final proposedTranslation = Offset(
      focalPoint.dx - scenePoint.dx * targetScale,
      focalPoint.dy - scenePoint.dy * targetScale,
    );
    return _matrixFor(
      targetScale,
      _clampTranslation(proposedTranslation, targetScale),
    );
  }

  void setScaleAt(double scale, Offset focalPoint) =>
      setTransformation(transformationForScaleAt(scale, focalPoint));

  /// Converts a physical wheel delta into one bounded scale adjustment.
  ///
  /// Negative [scrollDeltaY] is wheel-up and therefore zooms in. The result is
  /// intentionally proportional rather than one full [step] per event: a
  /// high-resolution wheel can emit several events for a single detent without
  /// producing an extreme jump.
  double scaleDeltaForWheelDelta(double scrollDeltaY) {
    if (scrollDeltaY.abs() < .001) return 0;
    final normalizedNotches = (scrollDeltaY.abs() / _wheelNotchDelta)
        .clamp(0, 1)
        .toDouble();
    return (scrollDeltaY.isNegative ? 1 : -1) * step * normalizedNotches;
  }

  /// Pans the transformed scene by a mouse drag delta. Panning is meaningful
  /// only once the scene is magnified; at 100% it remains pinned to the normal
  /// route layout.
  void panBy(Offset viewportDelta) {
    if (currentScale <= minimumScale + .001) return;
    final translation = _transformationController.value.getTranslation();
    setTransformation(
      _matrixFor(
        currentScale,
        Offset(
          translation.x + viewportDelta.dx,
          translation.y + viewportDelta.dy,
        ),
      ),
    );
  }

  /// Lets the viewport animate a matrix without routing high-frequency gesture
  /// frames through Riverpod or rebuilding business widgets.
  void setTransformation(Matrix4 value) {
    final constrained = _constrainedTransformation(value);
    if (_sameMatrix(_transformationController.value, constrained)) return;
    _transformationController.value = constrained;
  }

  Matrix4 _constrainedTransformation(Matrix4 value) {
    final scale = value
        .getMaxScaleOnAxis()
        .clamp(minimumScale, maximumScale)
        .toDouble();
    final translation = value.getTranslation();
    return _matrixFor(
      scale,
      _clampTranslation(Offset(translation.x, translation.y), scale),
    );
  }

  Offset _clampTranslation(Offset value, double scale) {
    if (_viewportSize.isEmpty) return value;
    // The transformed scene always covers the viewport but cannot be panned
    // into blank space. At 100% both ranges collapse cleanly to zero.
    final minX = _viewportSize.width * (1 - scale);
    final minY = _viewportSize.height * (1 - scale);
    return Offset(
      value.dx.clamp(minX, 0).toDouble(),
      value.dy.clamp(minY, 0).toDouble(),
    );
  }

  Matrix4 _matrixFor(double scale, Offset translation) => Matrix4.identity()
    ..translateByDouble(translation.dx, translation.dy, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1);

  bool _sameMatrix(Matrix4 left, Matrix4 right) {
    for (var index = 0; index < 16; index++) {
      if ((left.storage[index] - right.storage[index]).abs() > .00001) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _transformationController
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}

/// Zooms only a workspace's central route content. Shell navigation, headers,
/// overlays, dialogs and toasts remain untransformed. Operating-system text
/// scaling is never changed.
class YorksWorkspaceZoomViewport extends StatefulWidget {
  const YorksWorkspaceZoomViewport({
    super.key,
    required this.child,
    required this.routeKey,
    required this.language,
    this.controller,
  });

  final Widget child;
  final String routeKey;
  final AppLanguage language;
  final YorksWorkspaceZoomController? controller;

  @override
  State<YorksWorkspaceZoomViewport> createState() =>
      _YorksWorkspaceZoomViewportState();
}

class _YorksWorkspaceZoomViewportState extends State<YorksWorkspaceZoomViewport>
    with TickerProviderStateMixin {
  late YorksWorkspaceZoomController _controller;
  late bool _ownsController;
  AnimationController? _animationController;
  int? _middlePanPointer;
  final _viewportKey = GlobalKey();
  bool _usesScope = false;

  @override
  void initState() {
    super.initState();
    _setController(widget.controller);
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scoped = YorksWorkspaceZoomScope.maybeOf(context);
    if (widget.controller == null && scoped != null && scoped != _controller) {
      _disposeAnimation();
      if (_ownsController) _controller.dispose();
      _controller = scoped;
      _ownsController = false;
      _usesScope = true;
    }
  }

  @override
  void didUpdateWidget(covariant YorksWorkspaceZoomViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _disposeAnimation();
      if (_ownsController) _controller.dispose();
      _setController(widget.controller);
    }
    // The shell host restores bounded session history. Standalone viewports
    // start new routes at 100%; neither path changes accessibility text size.
    if (oldWidget.routeKey != widget.routeKey) {
      _disposeAnimation();
      if (!_usesScope) _controller.reset();
    }
  }

  void _setController(YorksWorkspaceZoomController? supplied) {
    _ownsController = supplied == null;
    _controller = supplied ?? YorksWorkspaceZoomController();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    _disposeAnimation();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _disposeAnimation() {
    final animationController = _animationController;
    _animationController = null;
    animationController?.dispose();
  }

  void _animateToScale(double targetScale, {Offset? focalPoint}) {
    final end = _controller.transformationForScaleAt(
      targetScale,
      focalPoint ?? _keyboardFocalPoint,
    );
    _disposeAnimation();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.setTransformation(end);
      return;
    }
    final begin = Matrix4.copy(_controller.transformationController.value);
    final animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    final animation = Matrix4Tween(begin: begin, end: end).animate(
      CurvedAnimation(parent: animationController, curve: Curves.easeOutCubic),
    );
    animationController.addListener(
      () => _controller.setTransformation(animation.value),
    );
    _animationController = animationController;
    animationController.forward().whenCompleteOrCancel(() {
      if (identical(_animationController, animationController)) {
        _animationController = null;
        if (mounted) {
          _controller.setTransformation(end);
        }
        animationController.dispose();
      }
    });
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!_allowsInspection(event.position, event.viewId)) return;
    if (event is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
        if (!mounted || resolved is! PointerScaleEvent) return;
        _disposeAnimation();
        _controller.setScale(
          _controller.currentScale * resolved.scale,
          focalPoint: resolved.localPosition,
        );
      });
      return;
    }
    if (event is! PointerScrollEvent) return;
    final keyboard = HardwareKeyboard.instance;
    // Shift-wheel is a horizontal-scroll affordance in desktop browsers and
    // tables. It must never become a surprise zoom shortcut, even if a user
    // also happens to hold Ctrl or Command.
    if (keyboard.isShiftPressed ||
        (!keyboard.isControlPressed && !keyboard.isMetaPressed)) {
      return;
    }
    if (event.scrollDelta.dy.abs() < .01) return;

    // This Listener is the front-most hit-test target only for pointer
    // signals. Registering first consumes modified wheel input before an
    // underlying page/table Scrollable can also process it. Ordinary wheel
    // and two-finger scrolling do not register here and stay untouched.
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (!mounted || resolved is! PointerScrollEvent) return;
      final delta = _controller.scaleDeltaForWheelDelta(
        resolved.scrollDelta.dy,
      );
      if (delta == 0) return;
      // localPosition is the pointer's actual location in this viewport, so
      // the value under a physical mouse cursor remains anchored as it grows.
      _disposeAnimation();
      _controller.setScale(
        _controller.currentScale + delta,
        focalPoint: resolved.localPosition,
      );
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_allowsInspection(event.position, event.viewId)) return;
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons & kMiddleMouseButton == 0 ||
        _controller.currentScale <= _controller.minimumScale + .001) {
      return;
    }
    _disposeAnimation();
    setState(() => _middlePanPointer = event.pointer);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _middlePanPointer ||
        event.buttons & kMiddleMouseButton == 0) {
      return;
    }
    _controller.panBy(event.delta);
  }

  void _endMiddlePan(PointerEvent event) {
    if (event.pointer != _middlePanPointer) return;
    setState(() => _middlePanPointer = null);
  }

  bool _allowsInspection(Offset position, int viewId) {
    final result = HitTestResult();
    GestureBinding.instance.hitTestInView(result, position, viewId);
    return !result.path.any((entry) => entry.target is _YorksZoomExclusionBox);
  }

  Rect? get _focusedRect {
    final view = _viewportKey.currentContext?.findRenderObject();
    final focused = FocusManager.instance.primaryFocus?.context
        ?.findRenderObject();
    if (view is! RenderBox || focused is! RenderBox || !focused.attached) {
      return null;
    }
    RenderObject? ancestor = focused;
    while (ancestor != null && ancestor != view) {
      ancestor = ancestor.parent;
    }
    if (ancestor == null) {
      return null; // A dialog/menu owns focus, not this view.
    }
    return MatrixUtils.transformRect(
      focused.getTransformTo(view),
      Offset.zero & focused.size,
    );
  }

  Offset get _keyboardFocalPoint {
    final center = _focusedRect?.center ?? _controller.defaultFocalPoint;
    final view = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (view == null) return center;
    return Offset(
      center.dx.clamp(0, view.size.width),
      center.dy.clamp(0, view.size.height),
    );
  }

  void _focusChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.canZoomOut) return;
      final rect = _focusedRect;
      final view =
          _viewportKey.currentContext?.findRenderObject() as RenderBox?;
      if (rect == null || view == null) return;
      const margin = 12.0;
      double correction(double start, double end, double extent) =>
          end - start > extent - 2 * margin
          ? margin - start
          : start < margin
          ? margin - start
          : end > extent - margin
          ? extent - margin - end
          : 0;
      _controller.panBy(
        Offset(
          correction(rect.left, rect.right, view.size.width),
          correction(rect.top, rect.bottom, view.size.height),
        ),
      );
    });
  }

  bool _canSpacePan(PointerDownEvent event) {
    final focused = FocusManager.instance.primaryFocus?.context;
    final editing =
        focused?.widget is EditableText ||
        focused?.findAncestorWidgetOfExactType<EditableText>() != null;
    return !editing &&
        _controller.canZoomOut &&
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.space,
        ) &&
        _allowsInspection(event.position, event.viewId);
  }

  void _inspect(double ratio, Offset previous, Offset current) {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _disposeAnimation();
    final before = box.globalToLocal(previous);
    final after = box.globalToLocal(current);
    _controller.setScale(_controller.currentScale * ratio, focalPoint: before);
    _controller.panBy(after - before);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _controller.updateViewportSize(constraints.biggest);
        return YorksWorkspaceZoomShortcuts(
          controller: _controller,
          onZoomIn: () =>
              _animateToScale(_controller.currentScale + _controller.step),
          onZoomOut: () =>
              _animateToScale(_controller.currentScale - _controller.step),
          onReset: () => _animateToScale(_controller.minimumScale),
          child: RawGestureDetector(
            gestures: {
              YorksInspectionGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    YorksInspectionGestureRecognizer
                  >(
                    () => YorksInspectionGestureRecognizer(),
                    (recognizer) => recognizer
                      ..onInspect = _inspect
                      ..canPan = (() => _controller.canZoomOut)
                      ..allowsStart = _allowsInspection,
                  ),
              YorksInspectionMousePanRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    YorksInspectionMousePanRecognizer
                  >(
                    () => YorksInspectionMousePanRecognizer(),
                    (recognizer) => recognizer
                      ..allowsStart = _canSpacePan
                      ..onStart = ((_) => _disposeAnimation())
                      ..onUpdate = ((details) =>
                          _controller.panBy(details.delta)),
                  ),
            },
            child: MouseRegion(
              cursor: _middlePanPointer != null
                  ? SystemMouseCursors.grabbing
                  : MouseCursor.defer,
              child: Stack(
                key: _viewportKey,
                fit: StackFit.expand,
                children: [
                  ClipRect(
                    child: AnimatedBuilder(
                      animation: _controller,
                      child: widget.child,
                      builder: (context, child) => Transform(
                        transform: _controller.transformationController.value,
                        child: child,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: _YorksPointerPassthroughLayer(
                      onPointerSignal: _handlePointerSignal,
                      onPointerDown: _handlePointerDown,
                      onPointerMove: _handlePointerMove,
                      onPointerUp: _endMiddlePan,
                      onPointerCancel: _endMiddlePan,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Sits above the workspace in paint order without becoming its input target.
///
/// It deliberately adds itself to the hit-test path, then returns `false` so
/// the normal page/table child is still hit-tested. That makes this layer the
/// first [PointerSignalResolver] registrant for Ctrl/Command-wheel zoom while
/// preserving every unmodified pointer event for the existing route widgets.
class _YorksPointerPassthroughLayer extends LeafRenderObjectWidget {
  const _YorksPointerPassthroughLayer({
    required this.onPointerSignal,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
  });

  final PointerSignalEventListener onPointerSignal;
  final PointerDownEventListener onPointerDown;
  final PointerMoveEventListener onPointerMove;
  final PointerUpEventListener onPointerUp;
  final PointerCancelEventListener onPointerCancel;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _YorksPointerPassthroughRenderBox(
        onPointerSignal: onPointerSignal,
        onPointerDown: onPointerDown,
        onPointerMove: onPointerMove,
        onPointerUp: onPointerUp,
        onPointerCancel: onPointerCancel,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _YorksPointerPassthroughRenderBox renderObject,
  ) {
    renderObject
      ..onPointerSignal = onPointerSignal
      ..onPointerDown = onPointerDown
      ..onPointerMove = onPointerMove
      ..onPointerUp = onPointerUp
      ..onPointerCancel = onPointerCancel;
  }
}

class _YorksPointerPassthroughRenderBox extends RenderBox {
  _YorksPointerPassthroughRenderBox({
    required this.onPointerSignal,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
  });

  PointerSignalEventListener onPointerSignal;
  PointerDownEventListener onPointerDown;
  PointerMoveEventListener onPointerMove;
  PointerUpEventListener onPointerUp;
  PointerCancelEventListener onPointerCancel;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performResize() {
    size = constraints.biggest;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    // Let the Stack continue to the route content behind this visual layer.
    return false;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    assert(debugHandleEvent(event, entry));
    switch (event) {
      case PointerDownEvent():
        onPointerDown(event);
      case PointerMoveEvent():
        onPointerMove(event);
      case PointerUpEvent():
        onPointerUp(event);
      case PointerCancelEvent():
        onPointerCancel(event);
      case PointerSignalEvent():
        onPointerSignal(event);
      default:
        break;
    }
  }
}

class YorksWorkspaceZoomShortcuts extends StatelessWidget {
  const YorksWorkspaceZoomShortcuts({
    super.key,
    required this.controller,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.child,
  });

  final YorksWorkspaceZoomController controller;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.equal, control: true):
          _YorksZoomInIntent(),
      SingleActivator(LogicalKeyboardKey.equal, control: true, shift: true):
          _YorksZoomInIntent(),
      SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
          _YorksZoomInIntent(),
      SingleActivator(LogicalKeyboardKey.minus, control: true):
          _YorksZoomOutIntent(),
      SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true):
          _YorksZoomOutIntent(),
      SingleActivator(LogicalKeyboardKey.digit0, control: true):
          _YorksZoomResetIntent(),
      SingleActivator(LogicalKeyboardKey.equal, meta: true):
          _YorksZoomInIntent(),
      SingleActivator(LogicalKeyboardKey.equal, meta: true, shift: true):
          _YorksZoomInIntent(),
      SingleActivator(LogicalKeyboardKey.numpadAdd, meta: true):
          _YorksZoomInIntent(),
      SingleActivator(LogicalKeyboardKey.minus, meta: true):
          _YorksZoomOutIntent(),
      SingleActivator(LogicalKeyboardKey.numpadSubtract, meta: true):
          _YorksZoomOutIntent(),
      SingleActivator(LogicalKeyboardKey.digit0, meta: true):
          _YorksZoomResetIntent(),
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        _YorksZoomInIntent: CallbackAction<_YorksZoomInIntent>(
          onInvoke: (_) {
            if (controller.canZoomIn) onZoomIn();
            return null;
          },
        ),
        _YorksZoomOutIntent: CallbackAction<_YorksZoomOutIntent>(
          onInvoke: (_) {
            if (controller.canZoomOut) onZoomOut();
            return null;
          },
        ),
        _YorksZoomResetIntent: CallbackAction<_YorksZoomResetIntent>(
          onInvoke: (_) {
            if (controller.canZoomOut) onReset();
            return null;
          },
        ),
      },
      child: Focus(autofocus: true, child: child),
    ),
  );
}

class _YorksZoomInIntent extends Intent {
  const _YorksZoomInIntent();
}

class _YorksZoomOutIntent extends Intent {
  const _YorksZoomOutIntent();
}

class _YorksZoomResetIntent extends Intent {
  const _YorksZoomResetIntent();
}

class YorksWorkspaceZoomScope extends InheritedWidget {
  const YorksWorkspaceZoomScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final YorksWorkspaceZoomController controller;
  static YorksWorkspaceZoomController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<YorksWorkspaceZoomScope>()
      ?.controller;
  @override
  bool updateShouldNotify(YorksWorkspaceZoomScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Bounded, in-memory view history. Key this host by authenticated identity;
/// inspection transforms must never survive logout or cross between people.
class YorksWorkspaceZoomHost extends StatefulWidget {
  const YorksWorkspaceZoomHost({
    super.key,
    required this.routeKey,
    required this.child,
  });
  final String routeKey;
  final Widget child;
  @override
  State<YorksWorkspaceZoomHost> createState() => _YorksWorkspaceZoomHostState();
}

class _YorksWorkspaceZoomHostState extends State<YorksWorkspaceZoomHost> {
  final _controller = YorksWorkspaceZoomController();
  final _history = <String, Matrix4>{};
  @override
  void didUpdateWidget(covariant YorksWorkspaceZoomHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeKey == widget.routeKey) return;
    _history.remove(oldWidget.routeKey);
    _history[oldWidget.routeKey] = Matrix4.copy(
      _controller.transformationController.value,
    );
    final restored = _history.remove(widget.routeKey);
    while (_history.length > 20) {
      _history.remove(_history.keys.first);
    }
    _controller.setTransformation(restored ?? Matrix4.identity());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      YorksWorkspaceZoomScope(controller: _controller, child: widget.child);
}

/// Marks a dedicated document/image viewer as the sole owner of its gestures.
class YorksWorkspaceZoomExclusion extends SingleChildRenderObjectWidget {
  const YorksWorkspaceZoomExclusion({super.key, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _YorksZoomExclusionBox();
}

class _YorksZoomExclusionBox extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final hit = super.hitTest(result, position: position);
    if (hit) result.add(BoxHitTestEntry(this, position));
    return hit;
  }
}
