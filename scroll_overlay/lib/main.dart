// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'linked_scroll_controller.dart';

const EventChannel _platformVelocityEventChannel =
    EventChannel('scroll_overlay.flutter.io/velocity');

void main() {
  runApp(
    MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const FlutterDemo(),
    ),
  );
}

class FlutterDemo extends StatefulWidget {
  const FlutterDemo({Key? key}) : super(key: key);

  @override
  _FlutterDemoState createState() => _FlutterDemoState();
}

class _FlutterDemoState extends State<FlutterDemo> {
  /// How many times the velocity is measured per second.
  ///
  /// Setting this to not too small value - to get a meaningful velocity information,
  /// and not too big - to distinguish individual digits after thousands.
  static const int measurementsPerSecond = 25;
  static const Duration velocityTimerInverval =
      Duration(milliseconds: 1000 ~/ measurementsPerSecond);

  /// The base item extent at 0 index.
  ///
  /// Each item will have an extent = this + index.
  static const int baseItemExtent = 40;

  double? flutterVelocity;
  double? platformVelocity;
  ScrollController controller = ScrollController();
  // ScrollController controllerCopy = ScrollController();
  // final TrackingScrollController trackingScrollController = TrackingScrollController();
  late Timer velocityTimer;
  double? oldOffset;
  // LinkedScrollControllerGroup linkedScrollControllerGroup = LinkedScrollControllerGroup();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addPostFrameCallback((timeStamp) {
      velocityTimer = Timer.periodic(velocityTimerInverval, (timer) {
        if (oldOffset != null) {
          final double delta = controller.offset - oldOffset!;
          final double velocity = delta * measurementsPerSecond;
          if (velocity != flutterVelocity) {
            setState(() {
              flutterVelocity = velocity;
            });
          }
        }
        oldOffset = controller.offset;
      });
    });
    _platformVelocityEventChannel
        .receiveBroadcastStream()
        .listen((dynamic velocity) {
      if (velocity != platformVelocity) {
        setState(() {
          platformVelocity = velocity / MediaQuery.of(context).devicePixelRatio;
        });
      }
    });
    // controller = linkedScrollControllerGroup.addAndGet();
    // controllerCopy = linkedScrollControllerGroup.addAndGet();
  }

  @override
  void dispose() {
    controller.dispose();
    velocityTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          ListView.builder(
            addRepaintBoundaries: false,
            controller: controller,
            physics: ClampingScrollPhysics(),
            itemCount: 1000,
            itemBuilder: (BuildContext context, int index) {
              return Container(
                height: (baseItemExtent + index * 3).toDouble(),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF666666),
                    width: 0.0,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(left: 100.0),
                      child: Text(
                        'Flutter $index',
                        style: const TextStyle(fontSize: 16.0),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // ListView.builder(
          //   addRepaintBoundaries: false,
          //   controller: controllerCopy,
          //   physics: BouncingScrollPhysicsTemp(),
          //   itemCount: 1000,
          //   itemBuilder: (BuildContext context, int index) {
          //     return Container(
          //       height: (baseItemExtent + index * 3).toDouble(),
          //       decoration: BoxDecoration(
          //         border: Border.all(
          //           color: const Color(0xFF666666),
          //           width: 0.0,
          //         ),
          //       ),
          //       child: Row(
          //         crossAxisAlignment: CrossAxisAlignment.center,
          //         children: <Widget>[
          //           Padding(
          //             padding: const EdgeInsets.only(left: 100.0),
          //             child: Text(
          //               'Flutter $index',
          //               style: const TextStyle(fontSize: 16.0),
          //             ),
          //           ),
          //         ],
          //       ),
          //     );
          //   },
          // ),
          Align(
            alignment: FractionalOffset.centerRight,
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 18.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                      'Flutter velocity\n${flutterVelocity?.round().abs() ?? ""}'),
                  Text(
                      'Platform velocity\n${platformVelocity?.round().abs() ?? ""}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
