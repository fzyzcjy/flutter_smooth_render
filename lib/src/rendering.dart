import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_smooth_render/src/custom_layout_builder.dart';
import 'package:flutter_smooth_render/src/facade.dart';
import 'package:flutter_smooth_render/src/misc.dart';

/// Put this as high as possible in the tree
class SmootherParent extends StatelessWidget {
  final Widget child;

  const SmootherParent({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        // NOTE use *tight* constraints, so it is a Relayout Boundary, thus
        //      SmootherParentLastChildRaw.markNeedsLayout will not cause Stack to need to layout
        //      Otherwise it errors: https://github.com/fzyzcjy/yplusplus/issues/3397#issuecomment-1086873609
        const SizedBox(
          width: 0,
          height: 0,
          child: SmootherParentLastChildRaw(),
        ),
      ],
    );
  }
}

class SmootherParentLastChildRaw extends SingleChildRenderObjectWidget {
  const SmootherParentLastChildRaw({
    Key? key,
    Widget? child,
  }) : super(key: key, child: child);

  @override
  RenderSmootherParentLastChildRaw createRenderObject(BuildContext context) {
    return RenderSmootherParentLastChildRaw();
  }

  @override
  void updateRenderObject(BuildContext context, RenderSmootherParentLastChildRaw renderObject) {
    // nothing
  }
}

class RenderSmootherParentLastChildRaw extends RenderProxyBox with DisposeStatusRenderBoxMixin {
  RenderSmootherParentLastChildRaw({
    RenderBox? child,
  }) : super(child);

  @override
  void attach(covariant PipelineOwner owner) {
    super.attach(owner);

    assert(SmootherFacade.instance.smootherParentLastChild == null);
    SmootherFacade.instance.smootherParentLastChild = this;
  }

  @override
  void detach() {
    assert(SmootherFacade.instance.smootherParentLastChild == this);
    SmootherFacade.instance.smootherParentLastChild = null;

    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();

    // If this callback is called, then the whole subtree should have been [layout]ed successfully
    // Thus, we can deal with some old work
    // SmootherFacade.instance.workQueue.executeMany();
    SmootherFacade.instance.workQueue.maybeExecuteOne(debugReason: 'RenderSmootherParentLastChildRaw.performLayout');
  }
}

class Smoother extends StatefulWidget {
  final String debugName;
  final SmootherPlaceholder placeholder;

  /// If it changes, the new [child] will be delayed to be put into tree when it is not busy
  /// Otherwise, the [child] is *immediately* put into the tree, so this widget behaves as if a normal Container
  final SmootherLabel<dynamic> delayRenderTrigger;

  final Widget child;

  const Smoother({
    Key? key,
    this.debugName = '',
    this.delayRenderTrigger = const SmootherLabel<String>('Default'),
    this.placeholder = const SmootherPlaceholder(),
    required this.child,
  }) : super(key: key);

  @override
  State<Smoother> createState() => _SmootherState();
}

class _SmootherState extends State<Smoother> {
  late SmootherLabel<dynamic> activeDelayRenderTrigger;
  late Widget activeChild;

  // TODO maybe improve
  final _smootherRawKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    // hack
    final size = widget.placeholder.size.resolve(const BoxConstraints());
    activeDelayRenderTrigger = const SmootherLabel<String>('Placeholder');
    activeChild = Container(
      width: size.width,
      height: size.height,
      color: widget.placeholder.color,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (SmootherFacade.instance.debugDisableFunctionality) {
      return widget.child;
    }

    // return SmootherRaw(
    //   debugName: debugName,
    //   placeholder: placeholder,
    //   // NOTE use [LayoutBuilder], such that the [initState]/[didUpdateWidget] of the subtree is called inside
    //   // [_RenderSmootherRaw]'s [performLayout]
    //   child: LayoutBuilder(
    //     builder: (context, _) => child,
    //   ),
    // );

    // NOTE use [LayoutBuilder], such that the [initState]/[didUpdateWidget] of the subtree is called inside
    // [_RenderSmootherRaw]'s [performLayout]
    return SmootherRaw(
      key: _smootherRawKey,
      debugName: widget.debugName,
      child: CustomLayoutBuilder(builder: (context, _) {
        logger('Smoother.LayoutBuilder builder called');

        // only if [activeChild != widget.child], we need to consider carefully whether really change this child
        final effectiveShouldExecute = activeDelayRenderTrigger == widget.delayRenderTrigger ||
            !SmootherFacade.instance.hasSwapChildInCurrentFrame ||
            SmootherFacade.instance.scheduler.shouldExecute();
        if (effectiveShouldExecute) {
          activeChild = widget.child;
          activeDelayRenderTrigger = widget.delayRenderTrigger;
          SmootherFacade.instance.hasSwapChildInCurrentFrame = true;
        } else {
          logger('Smoother workQueue.add ${shortHash(this)} since skip execute');
          SmootherFacade.instance.workQueue.add(_onWorkQueueExecute);
        }

        return activeChild;
      }),
    );
  }

  void _onWorkQueueExecute() {
    final renderSmootherRaw = _smootherRawKey.currentContext?.findRenderObject() as RenderSmootherRaw?;
    if (renderSmootherRaw == null || renderSmootherRaw.disposed) {
      logger('Smoother onWorkQueueExecute skip since renderSmootherRaw($renderSmootherRaw)');
      return;
    }

    final customRenderLayoutBuilder = renderSmootherRaw.child as CustomRenderLayoutBuilder?;
    if (customRenderLayoutBuilder == null || customRenderLayoutBuilder.disposed) {
      logger('Smoother onWorkQueueExecute skip since customRenderLayoutBuilder($customRenderLayoutBuilder)');
      return;
    }

    logger('Smoother onWorkQueueExecute markNeedsLayout');
    // reason: otherwise even if [RenderSmoothRaw] re-layout, the [LayoutBuilder] will not call [LayoutBuilder.builder]
    customRenderLayoutBuilder.markNeedsLayout();
    // reason: wants to set `executeWorkQueueNextWorkAfterSelfLayout`
    renderSmootherRaw.markNeedsLayout(executeWorkQueueNextWorkAfterSelfLayout: true);
  }

  @override
  // ignore: unnecessary_overrides
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    // TODO some info
  }
}

abstract class SmootherSizeResolver {
  const SmootherSizeResolver();

  const factory SmootherSizeResolver.constant(Size size) = _SmootherSizeResolverConstant;

  Size resolve(BoxConstraints constraints);
}

class _SmootherSizeResolverConstant extends SmootherSizeResolver {
  final Size size;

  const _SmootherSizeResolverConstant(this.size);

  @override
  Size resolve(BoxConstraints constraints) => constraints.constrain(size);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SmootherSizeResolverConstant && runtimeType == other.runtimeType && size == other.size;

  @override
  int get hashCode => size.hashCode;
}

@immutable
class SmootherPlaceholder {
  final SmootherSizeResolver size;
  final Color color;

  const SmootherPlaceholder({
    this.size = const SmootherSizeResolver.constant(Size(20, 20)),
    this.color = Colors.transparent,
  });

  @override
  String toString() => 'SmootherPlaceholder{size: $size, color: $color}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmootherPlaceholder && runtimeType == other.runtimeType && size == other.size && color == other.color;

  @override
  int get hashCode => size.hashCode ^ color.hashCode;
}

class SmootherRaw extends SingleChildRenderObjectWidget {
  final String debugName;

  // final SmootherPlaceholder placeholder;

  const SmootherRaw({
    Key? key,
    required this.debugName,
    // required this.placeholder,
    Widget? child,
  }) : super(key: key, child: child);

  @override
  RenderSmootherRaw createRenderObject(BuildContext context) {
    return RenderSmootherRaw(
      debugName: debugName,
      // placeholder: placeholder,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSmootherRaw renderObject) {
    // ignore: avoid_single_cascade_in_expression_statements
    renderObject //
      ..debugName = debugName;
    // ..placeholder = placeholder
  }

// @override
// // ignore: unnecessary_overrides
// void debugFillProperties(DiagnosticPropertiesBuilder properties) {
//   super.debugFillProperties(properties);
//   properties.add(DiagnosticsProperty('placeholder', placeholder));
// }
}

class RenderSmootherRaw extends RenderProxyBox with DisposeStatusRenderBoxMixin {
  RenderSmootherRaw({
    // required SmootherPlaceholder placeholder,
    required this.debugName,
    RenderBox? child,
  }) :
        // _placeholder = placeholder,
        super(child);

  String debugName;

  // SmootherPlaceholder get placeholder => _placeholder;
  // SmootherPlaceholder _placeholder;
  //
  // set placeholder(SmootherPlaceholder value) {
  //   if (_placeholder == value) {
  //     return;
  //   }
  //
  //   if (_placeholder.size != value.size) {
  //     markNeedsLayout();
  //   }
  //
  //   _placeholder = value;
  // }

  var _executeWorkQueueNextWorkAfterSelfLayout = false;

  @override
  void markNeedsLayout({bool executeWorkQueueNextWorkAfterSelfLayout = false}) {
    super.markNeedsLayout();
    _executeWorkQueueNextWorkAfterSelfLayout = executeWorkQueueNextWorkAfterSelfLayout;
  }

  // var _hasSkippedChildLayout = false;
  // var _hasSucceededLayout = false;

  @override
  void performLayout() {
    logger('RenderSmootherRaw performLayout start child=$child child.sizedByParent=${child?.sizedByParent}');

    super.performLayout();

    if (_executeWorkQueueNextWorkAfterSelfLayout) {
      _executeWorkQueueNextWorkAfterSelfLayout = false;
      // https://github.com/fzyzcjy/yplusplus/issues/3397#issuecomment-1086863179
      // SmootherFacade.instance.workQueue.maybeExecuteOne(debugReason: 'RenderSmootherRaw.performLayout');
      SmootherFacade.instance.smootherParentLastChild?.markNeedsLayout();
    }

    // final lastFrameStart = SmootherBindingInfo.instance.lastFrameStart ?? DateTime.now();
    // logger(
    //     '[$debugName] performLayout start elapsed=${DateTime.now().difference(lastFrameStart)} lastFrameStart=$lastFrameStart');
    //
    // if (SmootherFacade.instance.scheduler.shouldExecute()) {
    //   logger('[$debugName] performLayout execute');
    //
    //   super.performLayout();
    //   _hasSkippedChildLayout = false;
    //   _hasSucceededLayout = true;
    // } else {
    //   logger('[$debugName] performLayout skip');
    //
    //   size = placeholder.size.resolve(constraints);
    //   _hasSkippedChildLayout = true;
    //   SmootherFacade.instance.workQueue.add(_onWorkQueueExecute);
    //
    //   // TODO redo the work in the next frame
    // }
    //
    // logger(
    //     '[$debugName] performLayout end elapsed=${DateTime.now().difference(lastFrameStart)} lastFrameStart=$lastFrameStart');
  }

  // void _onWorkQueueExecute() {
  //   if (!disposed) {
  //     markNeedsLayout();
  //   }
  // }
  //
  // @override
  // void visitChildrenForSemantics(RenderObjectVisitor visitor) {
  //   // according to comments of [visitChildrenForSemantics], it should "skip all
  //   // children that are not semantically relevant (e.g. because they are invisible)".
  //   // Thus, when the child does not have up-to-date [layout], we should not visit it.
  //   if (!_hasSkippedChildLayout) super.visitChildrenForSemantics(visitor);
  // }
  //
  // @override
  // void paint(PaintingContext context, Offset offset) {
  //   if (_hasSucceededLayout) {
  //     super.paint(context, offset);
  //   } else {
  //     context.canvas.drawRect(offset & size, Paint()..color = placeholder.color);
  //   }
  // }

  @override
  // ignore: unnecessary_overrides
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    // TODO some info
  }
}
