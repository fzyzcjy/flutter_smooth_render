import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_smooth_render/flutter_smooth_render.dart';
import 'package:flutter_smooth_render_example/heavy_widget.dart';
import 'package:flutter_smooth_render_example/misc.dart';

void main() {
  SmootherFacade.init();
  reportFrameEnd();

  FlutterError.onError = (details) {
    printWrapped('!!!ERROR!!! $details');
  };

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SmootherParent(
        child: MaterialApp(
          home: Theme(
            data: ThemeData(
              pageTransitionsTheme: PageTransitionsTheme(
                  builders: Map.fromEntries(TargetPlatform.values
                      .map((platform) => MapEntry(platform, const CupertinoPageTransitionsBuilder())))),
            ),
            child: const FirstPage(),
          ),
        ),
      ),
    );
  }
}

class FirstPage extends StatelessWidget {
  const FirstPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('First')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SimpleAnimatedBox(),
            TextButton(
              onPressed: () =>
                  Navigator.push<dynamic>(context, MaterialPageRoute<dynamic>(builder: (_) => const SecondPage())),
              child: const Text('Navigate'),
            ),
          ],
        ),
      ),
    );
  }
}

class SecondPage extends StatefulWidget {
  const SecondPage({Key? key}) : super(key: key);

  @override
  State<SecondPage> createState() => _SecondPageState();
}

class _SecondPageState extends State<SecondPage> {
  var seenFirstBuild = false;
  var heaviness = const Duration(milliseconds: 8);

  @override
  Widget build(BuildContext context) {
    if (!seenFirstBuild) {
      seenFirstBuild = true;
      logger('SecondPage first build() called');
      SchedulerBinding.instance!.addPostFrameCallback((_) {
        logger('SecondPage first frame finished');
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('First')),
      body: Column(
        children: [
          Row(
            children: [
              const Text('Heaviness'),
              for (final targetHeaviness in const [
                Duration(milliseconds: 1),
                Duration(milliseconds: 4),
                Duration(milliseconds: 8),
                Duration(milliseconds: 16),
                Duration(milliseconds: 32),
              ])
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => heaviness = targetHeaviness),
                    child: Text(
                      '${targetHeaviness.inMilliseconds}ms',
                      style: TextStyle(color: targetHeaviness == heaviness ? Colors.blue : Colors.black87),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) => ListView.builder(
                itemCount: 100,
                itemBuilder: (_, index) => _buildRow(constraints, index),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BoxConstraints constraints, int index) {
    return Row(
      children: [
        if (index < 8) const SimpleTickBox(),
        Expanded(
          child: Smoother(
            debugName: '$index',
            placeholder: SmootherPlaceholder(
              size: SmootherSizeResolver.constant(Size(constraints.maxWidth, 48)),
            ),
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(width: 48, child: Text('#$index')),
                    Expanded(child: HeavyBuildPhaseWidget(heaviness: heaviness, debugName: '$index')),
                    Expanded(child: HeavyLayoutPhaseWidget(heaviness: heaviness, debugName: '$index')),
                    // Not that frequently seen... So disable it at first
                    // Expanded(child: HeavyPaintPhaseWidget(heaviness: heaviness, debugName: '$index')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void reportFrameEnd() {
  var count = 0;

  void addPostFrameCallback() {
    SchedulerBinding.instance!.addPostFrameCallback((_) {
      logger('====== Frame end: #$count ======');
      count++;
      addPostFrameCallback();
    });
  }

  addPostFrameCallback();
}

/// https://stackoverflow.com/questions/49138971/logging-large-strings-from-flutter
void printWrapped(String text) {
  final pattern = RegExp('.{1,800}'); // 800 is the size of each chunk
  // ignore: avoid_print
  pattern.allMatches(text).forEach((match) => print(match.group(0)));
}
