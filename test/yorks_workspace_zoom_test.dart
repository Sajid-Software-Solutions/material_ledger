import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/zoom/yorks_workspace_zoom.dart';
import 'package:material_ledger/shared/models/app_language.dart';

void main() {
  if (kIsWeb) {
    testWidgets('browser uses a fixed-layout workspace transform', (
      tester,
    ) async {
      final controller = YorksWorkspaceZoomController();
      addTearDown(controller.dispose);
      controller.updateViewportSize(const Size(800, 600));
      controller.setScale(2);
      await tester.pumpWidget(
        _ZoomTestApp(
          controller: controller,
          routeKey: '/web',
          child: const Center(
            child: SizedBox(
              key: ValueKey('unscaled-content'),
              width: 100,
              height: 50,
            ),
          ),
        ),
      );
      final box = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('unscaled-content')),
      );
      final origin = box.localToGlobal(Offset.zero);
      expect(
        box.localToGlobal(const Offset(100, 50)) - origin,
        const Offset(200, 100),
      );
      expect(find.byType(YorksWorkspaceZoomShortcuts), findsOneWidget);
      await tester.sendEventToBinding(
        const PointerScaleEvent(
          kind: PointerDeviceKind.trackpad,
          position: Offset(400, 300),
          scale: 1.5,
        ),
      );
      await tester.pump();
      expect(controller.currentScale, 3);
      final transformedBox = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('unscaled-content')),
      );
      final transformedOrigin = transformedBox.localToGlobal(Offset.zero);
      expect(
        transformedBox.localToGlobal(const Offset(100, 50)) - transformedOrigin,
        const Offset(300, 150),
      );
      expect(tester.takeException(), isNull);
    });
    return;
  }

  test('focal-point zoom preserves the inspected scene coordinate', () {
    final controller = YorksWorkspaceZoomController();
    addTearDown(controller.dispose);
    controller.updateViewportSize(const Size(1200, 800));

    const focalPoint = Offset(860, 530);
    final before = controller.transformationController.toScene(focalPoint);
    controller.setScaleAt(2, focalPoint);
    final after = controller.transformationController.toScene(focalPoint);

    expect(controller.currentScale, 2);
    expect(after.dx, closeTo(before.dx, .0001));
    expect(after.dy, closeTo(before.dy, .0001));
  });

  test('zoom controller clamps, resets and re-clamps after a resize', () {
    final controller = YorksWorkspaceZoomController();
    addTearDown(controller.dispose);
    controller.updateViewportSize(const Size(1000, 700));

    controller.setScaleAt(99, const Offset(1000, 700));
    expect(controller.currentScale, 4);
    expect(
      controller.transformationController.value.getTranslation().x,
      inInclusiveRange(-3000, 0),
    );
    expect(
      controller.transformationController.value.getTranslation().y,
      inInclusiveRange(-2100, 0),
    );

    controller.updateViewportSize(const Size(600, 400));
    expect(
      controller.transformationController.value.getTranslation().x,
      inInclusiveRange(-1800, 0),
    );
    expect(
      controller.transformationController.value.getTranslation().y,
      inInclusiveRange(-1200, 0),
    );

    controller.reset();
    expect(controller.currentScale, 1);
    expect(controller.transformationController.value, Matrix4.identity());
  });

  test('wheel deltas are normalized and middle-drag panning stays bounded', () {
    final controller = YorksWorkspaceZoomController();
    addTearDown(controller.dispose);
    controller.updateViewportSize(const Size(1200, 800));

    // A regular wheel notch, a high-resolution stream totalling one notch and
    // an unusually large free-spin event all stay controlled.
    expect(controller.scaleDeltaForWheelDelta(-72), closeTo(.125, .0001));
    expect(
      List<double>.filled(12, -6)
          .map(controller.scaleDeltaForWheelDelta)
          .reduce((left, right) => left + right),
      closeTo(.125, .0001),
    );
    expect(controller.scaleDeltaForWheelDelta(-720), closeTo(.125, .0001));
    expect(controller.scaleDeltaForWheelDelta(720), closeTo(-.125, .0001));

    controller.setScaleAt(2, const Offset(600, 400));
    final beforePan = controller.transformationController.value
        .getTranslation();
    controller.panBy(const Offset(-180, -120));
    final afterPan = controller.transformationController.value.getTranslation();
    expect(afterPan.x, closeTo(beforePan.x - 180, .0001));
    expect(afterPan.y, closeTo(beforePan.y - 120, .0001));

    controller.panBy(const Offset(-10000, -10000));
    final bounded = controller.transformationController.value.getTranslation();
    expect(bounded.x, -1200);
    expect(bounded.y, -800);

    controller.reset();
    controller.panBy(const Offset(-200, -200));
    expect(controller.transformationController.value, Matrix4.identity());
  });

  testWidgets('desktop has no floating controls; the controller zooms', (
    tester,
  ) async {
    _setViewport(tester, const Size(1200, 800));
    final controller = YorksWorkspaceZoomController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: YorksWorkspaceZoomScope(
          controller: controller,
          child: Scaffold(
            appBar: AppBar(),
            body: YorksWorkspaceZoomViewport(
              controller: controller,
              routeKey: '/test',
              language: AppLanguage.english,
              child: const _ScrollableRouteContent(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('yorks-workspace-zoom-controls')),
      findsNothing,
    );
    controller.zoomIn();
    await tester.pumpAndSettle();
    expect(controller.currentScale, greaterThan(1));
    controller.reset();
    await tester.pumpAndSettle();
    expect(controller.currentScale, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route changes reset the workspace to 100 percent', (
    tester,
  ) async {
    _setViewport(tester, const Size(1200, 800));
    final controller = YorksWorkspaceZoomController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _ZoomTestApp(
        controller: controller,
        routeKey: '/yorks/overview',
        child: const _ScrollableRouteContent(),
      ),
    );
    await tester.pumpAndSettle();
    controller.setScale(2);
    await tester.pump();
    expect(controller.currentScale, 2);

    await tester.pumpWidget(
      _ZoomTestApp(
        controller: controller,
        routeKey: '/yorks/material-requests',
        child: const _ScrollableRouteContent(),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.currentScale, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet workspace has no floating controls', (tester) async {
    _setViewport(tester, const Size(820, 900));
    final controller = YorksWorkspaceZoomController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _ZoomTestApp(
        controller: controller,
        routeKey: '/yorks/overview',
        child: const _ScrollableRouteContent(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('yorks-workspace-zoom-controls')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal form fields and dropdown menus remain interactive', (
    tester,
  ) async {
    _setViewport(tester, const Size(1200, 800));
    final controller = YorksWorkspaceZoomController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _ZoomTestApp(
        controller: controller,
        routeKey: '/yorks/inventory/import',
        child: const _FormRouteContent(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('zoom-test-text-field')));
    await tester.enterText(
      find.byKey(const ValueKey('zoom-test-text-field')),
      'AHU-100',
    );
    expect(find.text('AHU-100'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('zoom-test-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project BOQ').last);
    await tester.pumpAndSettle();
    expect(find.text('Project BOQ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keyboard shortcuts and native pinch signals use the route viewport',
    (tester) async {
      _setViewport(tester, const Size(1200, 800));
      final controller = YorksWorkspaceZoomController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _ZoomTestApp(
          controller: controller,
          routeKey: '/yorks/overview',
          child: const _ScrollableRouteContent(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(controller.currentScale, greaterThan(1));

      controller.reset();
      await tester.pump();
      const wheelFocalPoint = Offset(520, 380);
      final beforeWheelZoom = controller.transformationController.toScene(
        wheelFocalPoint,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: wheelFocalPoint,
          scrollDelta: Offset(0, -72),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(controller.currentScale, greaterThan(1));
      final afterWheelZoom = controller.transformationController.toScene(
        wheelFocalPoint,
      );
      expect(afterWheelZoom.dx, closeTo(beforeWheelZoom.dx, .0001));
      expect(afterWheelZoom.dy, closeTo(beforeWheelZoom.dy, .0001));

      controller.reset();
      await tester.pump();
      await tester.sendEventToBinding(
        const PointerScaleEvent(
          kind: PointerDeviceKind.trackpad,
          position: Offset(260, 420),
          scale: 1.5,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(controller.currentScale, greaterThan(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary and Shift wheel scrolling do not zoom while Ctrl-wheel does',
    (tester) async {
      _setViewport(tester, const Size(1200, 800));
      final controller = YorksWorkspaceZoomController();
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        _ZoomTestApp(
          controller: controller,
          routeKey: '/yorks/inventory',
          child: _ScrollableRouteContent(scrollController: scrollController),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(500, 400),
          scrollDelta: Offset(0, 72),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.currentScale, 1);
      expect(scrollController.offset, greaterThan(0));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(500, 400),
          scrollDelta: Offset(0, -720),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(controller.currentScale, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(500, 400),
          scrollDelta: Offset(0, -720),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(controller.currentScale, greaterThan(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('middle-button drag pans a zoomed workspace only', (
    tester,
  ) async {
    _setViewport(tester, const Size(1200, 800));
    final controller = YorksWorkspaceZoomController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _ZoomTestApp(
        controller: controller,
        routeKey: '/yorks/material-requests',
        child: const _ScrollableRouteContent(),
      ),
    );
    await tester.pumpAndSettle();

    controller.setScaleAt(2, const Offset(600, 400));
    await tester.pump();
    final beforePan = controller.transformationController.value
        .getTranslation();
    final middleDrag = await tester.startGesture(
      const Offset(600, 400),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await middleDrag.moveBy(const Offset(-160, -110));
    await tester.pump();
    await middleDrag.up();
    await tester.pumpAndSettle();

    final afterPan = controller.transformationController.value.getTranslation();
    expect(afterPan.x, closeTo(beforePan.x - 160, .0001));
    expect(afterPan.y, closeTo(beforePan.y - 110, .0001));

    controller.reset();
    await tester.pump();
    final unzoomedDrag = await tester.startGesture(
      const Offset(600, 400),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await unzoomedDrag.moveBy(const Offset(-160, -110));
    await unzoomedDrag.up();
    await tester.pumpAndSettle();
    expect(controller.transformationController.value, Matrix4.identity());
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact routes retain their normal touch layout and scroll', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    final controller = YorksWorkspaceZoomController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _ZoomTestApp(
        controller: controller,
        routeKey: '/yorks/overview',
        child: const _ScrollableRouteContent(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('yorks-workspace-zoom-controls')),
      findsNothing,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Last controlled action'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('two-finger pinch is immediate, pans and returns to normal', (
    tester,
  ) async {
    _setViewport(tester, const Size(360, 800));
    final controller = YorksWorkspaceZoomController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _ZoomTestApp(
        controller: controller,
        routeKey: '/test',
        child: const _ScrollableRouteContent(),
      ),
    );
    final first = await tester.startGesture(const Offset(130, 350), pointer: 1);
    final second = await tester.startGesture(
      const Offset(230, 350),
      pointer: 2,
    );
    await first.moveTo(const Offset(80, 350));
    await second.moveTo(const Offset(280, 350));
    expect(controller.currentScale, closeTo(2, .001));
    final before = controller.transformationController.value.getTranslation().y;
    await first.moveBy(const Offset(0, -40));
    await second.moveBy(const Offset(0, -40));
    expect(
      controller.transformationController.value.getTranslation().y,
      closeTo(before - 40, .001),
    );
    await first.moveTo(const Offset(130, 310));
    await second.moveTo(const Offset(230, 310));
    expect(controller.currentScale, closeTo(1, .001));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native trackpad pinch and magnified pan do not animate behind input',
    (tester) async {
      _setViewport(tester, const Size(1200, 800));
      final controller = YorksWorkspaceZoomController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _ZoomTestApp(
          controller: controller,
          routeKey: '/test',
          child: const _ScrollableRouteContent(),
        ),
      );
      await tester.sendEventToBinding(
        const PointerPanZoomStartEvent(pointer: 42, position: Offset(500, 400)),
      );
      await tester.sendEventToBinding(
        const PointerPanZoomUpdateEvent(
          pointer: 42,
          position: Offset(500, 400),
          scale: 2,
        ),
      );
      expect(controller.currentScale, 2);
      final before = controller.transformationController.value.getTranslation();
      await tester.sendEventToBinding(
        const PointerPanZoomUpdateEvent(
          pointer: 42,
          position: Offset(500, 400),
          scale: 2,
          pan: Offset(-50, -30),
          panDelta: Offset(-50, -30),
        ),
      );
      expect(
        controller.transformationController.value.getTranslation().x,
        closeTo(before.x - 50, .001),
      );
      await tester.sendEventToBinding(
        const PointerPanZoomEndEvent(pointer: 42),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('view history restores only within the same authenticated host', (
    tester,
  ) async {
    _setViewport(tester, const Size(1200, 800));
    YorksWorkspaceZoomController? controller;
    Widget host(String route, String user) => MaterialApp(
      home: YorksWorkspaceZoomHost(
        key: ValueKey(user),
        routeKey: route,
        child: Builder(
          builder: (context) {
            controller = YorksWorkspaceZoomScope.maybeOf(context);
            return Scaffold(
              body: YorksWorkspaceZoomViewport(
                routeKey: route,
                language: AppLanguage.english,
                child: const _ScrollableRouteContent(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpWidget(host('/a', 'user-a'));
    await tester.pumpAndSettle();
    controller!.setScale(2);
    await tester.pumpWidget(host('/b', 'user-a'));
    await tester.pumpAndSettle();
    expect(controller!.currentScale, 1);
    await tester.pumpWidget(host('/a', 'user-a'));
    await tester.pumpAndSettle();
    expect(controller!.currentScale, 2);
    await tester.pumpWidget(host('/a', 'user-b'));
    await tester.pumpAndSettle();
    expect(controller!.currentScale, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single finger still scrolls when magnified', (tester) async {
    _setViewport(tester, const Size(360, 800));
    final controller = YorksWorkspaceZoomController();
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _ZoomTestApp(
        controller: controller,
        routeKey: '/test',
        child: _ScrollableRouteContent(scrollController: scroll),
      ),
    );
    controller.setScale(2);
    await tester.pump();
    await tester.dragFrom(const Offset(180, 500), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(controller.currentScale, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('reduced motion applies keyboard zoom without an animation', (
    tester,
  ) async {
    final controller = YorksWorkspaceZoomController();
    addTearDown(controller.dispose);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      _ZoomTestApp(
        controller: controller,
        routeKey: '/test',
        child: const _ScrollableRouteContent(),
      ),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(controller.currentScale, 1.125);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dedicated viewer does not also magnify the workspace', (
    tester,
  ) async {
    _setViewport(tester, const Size(360, 800));
    final controller = YorksWorkspaceZoomController();
    final viewer = TransformationController();
    addTearDown(controller.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(
      _ZoomTestApp(
        controller: controller,
        routeKey: '/test',
        child: YorksWorkspaceZoomExclusion(
          child: InteractiveViewer(
            transformationController: viewer,
            child: const SizedBox.expand(child: ColoredBox(color: Colors.blue)),
          ),
        ),
      ),
    );
    final first = await tester.startGesture(const Offset(100, 350), pointer: 1);
    final second = await tester.startGesture(
      const Offset(250, 350),
      pointer: 2,
    );
    await first.moveTo(const Offset(50, 350));
    await second.moveTo(const Offset(300, 350));
    await tester.pump();
    expect(controller.currentScale, 1);
    expect(viewer.value.getMaxScaleOnAxis(), greaterThan(1));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('space and primary mouse drag pan without a middle button', (
    tester,
  ) async {
    _setViewport(tester, const Size(1200, 800));
    final controller = YorksWorkspaceZoomController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _ZoomTestApp(
        controller: controller,
        routeKey: '/test',
        child: const _ScrollableRouteContent(),
      ),
    );
    controller.setScale(2);
    await tester.pump();
    final before = controller.transformationController.value.getTranslation().x;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final drag = await tester.startGesture(
      const Offset(600, 400),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(-50, 0));
    await drag.moveBy(const Offset(-80, 0));
    await drag.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(
      controller.transformationController.value.getTranslation().x,
      lessThan(before),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('magnified form preserves editing and dropdown selection', (
    tester,
  ) async {
    _setViewport(tester, const Size(1200, 800));
    final controller = YorksWorkspaceZoomController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _ZoomTestApp(
        controller: controller,
        routeKey: '/test',
        child: const _FormRouteContent(),
      ),
    );
    controller.setScale(2, focalPoint: Offset.zero);
    await tester.pump();
    await tester.tapAt(const Offset(200, 100));
    await tester.enterText(
      find.byKey(const ValueKey('zoom-test-text-field')),
      'Copper pipe 25 mm',
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const ValueKey('zoom-test-dropdown'))) +
          const Offset(100, 30),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project BOQ').last);
    await tester.pumpAndSettle();
    controller.reset();
    await tester.pumpAndSettle();
    expect(find.text('Copper pipe 25 mm'), findsOneWidget);
    expect(find.text('Project BOQ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ZoomTestApp extends StatelessWidget {
  const _ZoomTestApp({
    required this.controller,
    required this.routeKey,
    required this.child,
  });

  final YorksWorkspaceZoomController controller;
  final String routeKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: YorksWorkspaceZoomViewport(
        controller: controller,
        routeKey: routeKey,
        language: AppLanguage.english,
        child: child,
      ),
    ),
  );
}

class _ScrollableRouteContent extends StatelessWidget {
  const _ScrollableRouteContent({this.scrollController});

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('zoom-test-scrollable'),
    controller: scrollController,
    padding: const EdgeInsets.all(24),
    children: const [
      Text('Route content'),
      SizedBox(height: 1000),
      Text('Last controlled action'),
    ],
  );
}

class _FormRouteContent extends StatelessWidget {
  const _FormRouteContent();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      TextFormField(
        key: const ValueKey('zoom-test-text-field'),
        decoration: const InputDecoration(labelText: 'Item description'),
      ),
      const SizedBox(height: 24),
      DropdownButtonFormField<String>(
        key: const ValueKey('zoom-test-dropdown'),
        initialValue: 'Building BOQ',
        items: const [
          DropdownMenuItem(value: 'Building BOQ', child: Text('Building BOQ')),
          DropdownMenuItem(value: 'Project BOQ', child: Text('Project BOQ')),
        ],
        onChanged: (_) {},
      ),
    ],
  );
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
