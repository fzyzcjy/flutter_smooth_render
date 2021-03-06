import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_smooth_render/src/facade.dart';

var logger = _defaultLogger;

// ignore: avoid_print
void _defaultLogger(String message) => print('${DateTime.now().toIso8601String()}|$message');

class SmootherScheduler {
  SmootherScheduler.raw();

  static var durationThreshold = const Duration(microseconds: 1000000 ~/ 60);

  bool shouldExecute() {
    final lastFrameStart = SmootherFacade.instance.bindingInfo.lastFrameStart;
    if (lastFrameStart == null) return true; // not sure what to do... so fallback to conservative

    final currentDuration = DateTime.now().difference(lastFrameStart);
    assert(() {
      logger('shouldStartPieceOfWork currentDuration=${currentDuration.inMilliseconds}ms');
      return true;
    }());

    return currentDuration <= durationThreshold;
  }
}

typedef SmootherWorkJob = void Function();

class SmootherWorkQueue {
  final _queue = Queue<SmootherWorkJob>();

  SmootherWorkQueue.raw();

  void add(SmootherWorkJob item) {
    _queue.add(item);
    _maybeAddPostFrameCallback();
  }

  var _hasPostFrameCallback = false;

  void _maybeAddPostFrameCallback() {
    if (_hasPostFrameCallback) return;
    _hasPostFrameCallback = true;

    logger('SmootherWorkQueue addPostFrameCallback');
    WidgetsBinding.instance!.addPostFrameCallback((_) {
      logger('SmootherWorkQueue inside postFrameCallback queue.len=${_queue.length}');

      // If, after the current frame is finished, there is still some work to be done,
      // Then we need to schedule a new frame
      if (_queue.isNotEmpty) {
        logger(
            'SmootherWorkQueue call SmootherParentLastChild.markNeedsBuild since SmootherWorkQueue.workQueue not empty');
        SmootherFacade.instance.smootherParentLastChild?.markNeedsLayout();
      }

      _hasPostFrameCallback = false;
    });
  }

  // void executeMany() {
  //   // At least execute one, even if are already too late. Otherwise, on low-end devices,
  //   // it can happen that *no* work is executed on *each and every* frame, so the objects
  //   // are never rendered.
  //   executeOne();
  //
  //   while (SmootherFacade.instance.scheduler.shouldExecute() && _queue.isNotEmpty) {
  //     executeOne();
  //   }
  // }

  void maybeExecuteOne({required String debugReason}) {
    if (_queue.isEmpty) return;

    final effectiveShouldExecute =
        !SmootherFacade.instance.hasExecuteWorkQueueInCurrentFrame || SmootherFacade.instance.scheduler.shouldExecute();
    if (!effectiveShouldExecute) {
      return;
    }
    SmootherFacade.instance.hasExecuteWorkQueueInCurrentFrame = true;

    final item = _queue.removeFirst();
    logger('SmootherWorkQueue executeOne run $item debugReason=$debugReason');
    item();

    if (_queue.isNotEmpty) {
      _maybeAddPostFrameCallback();
    }
  }
}

void addPostFrameCallbackForAllFrames(void Function(Duration) run) {
  void addPostFrameCallback() {
    SchedulerBinding.instance!.addPostFrameCallback((timeStamp) {
      run(timeStamp);
      addPostFrameCallback();
    });
  }

  addPostFrameCallback();
}

mixin DisposeStatusRenderBoxMixin on RenderBox {
  var disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

// implementation references [ValueKey]
@immutable
class SmootherLabel<T> {
  /// Creates a label that delegates its [operator==] to the given value.
  const SmootherLabel(this.value);

  /// The value to which this label delegates its [operator==]
  final T value;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is SmootherLabel<T> && other.value == value;
  }

  @override
  int get hashCode => hashValues(runtimeType, value);

  @override
  String toString() {
    final valueString = T == String ? "<'$value'>" : '<$value>';
    return '[$T $valueString]';
  }
}
