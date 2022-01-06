import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AndroidScrollPhysics extends ScrollPhysics {
  /// Creates scroll physics that prevent the scroll offset from exceeding the
  /// bounds of the content..
  const AndroidScrollPhysics({ScrollPhysics? parent}) : super(parent: parent);

  @override
  AndroidScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return AndroidScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    assert(() {
      if (value == position.pixels) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('$runtimeType.applyBoundaryConditions() was called redundantly.'),
          ErrorDescription('The proposed new position, $value, is exactly equal to the current position of the '
              'given ${position.runtimeType}, ${position.pixels}.\n'
              'The applyBoundaryConditions method should only be called when the value is '
              'going to actually change the pixels, otherwise it is redundant.'),
          DiagnosticsProperty<ScrollPhysics>('The physics object in question was', this, style: DiagnosticsTreeStyle.errorProperty),
          DiagnosticsProperty<ScrollMetrics>('The position object in question was', position, style: DiagnosticsTreeStyle.errorProperty)
        ]);
      }
      return true;
    }());
    if (value < position.pixels && position.pixels <= position.minScrollExtent) // underscroll
      return value - position.pixels;
    if (position.maxScrollExtent <= position.pixels && position.pixels < value) // overscroll
      return value - position.pixels;
    if (value < position.minScrollExtent && position.minScrollExtent < position.pixels) // hit top edge
      return value - position.minScrollExtent;
    if (position.pixels < position.maxScrollExtent && position.maxScrollExtent < value) // hit bottom edge
      return value - position.maxScrollExtent;
    return 0.0;
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    final Tolerance tolerance = this.tolerance;
    if (position.outOfRange) {
      double? end;
      if (position.pixels > position.maxScrollExtent) end = position.maxScrollExtent;
      if (position.pixels < position.minScrollExtent) end = position.minScrollExtent;
      assert(end != null);
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        end!,
        math.min(0.0, velocity),
        tolerance: tolerance,
      );
    }
    if (velocity.abs() < tolerance.velocity) return null;
    if (velocity > 0.0 && position.pixels >= position.maxScrollExtent) return null;
    if (velocity < 0.0 && position.pixels <= position.minScrollExtent) return null;
    return AndroidScrollerSimulation(
      position: position.pixels,
      velocity: velocity,
      tolerance: tolerance,
    );
  }
}

const int _NB_SAMPLES = 100;
List<double> _SPLINE_POSITION = List<double>.filled(_NB_SAMPLES + 1, 0);
List<double> _SPLINE_TIME = List<double>.filled(_NB_SAMPLES + 1, 0);

const double _INFLEXION = 0.35; // Tension lines cross at (INFLEXION, 1)
const double _START_TENSION = 0.5;
const double _END_TENSION = 1.0;
const double _P1 = _START_TENSION * _INFLEXION;
const double _P2 = 1.0 - _END_TENSION * (1.0 - _INFLEXION);

/** Earth's gravity in SI units (m/s^2) */
const double GRAVITY_EARTH = 9.80665;
/**
 * The coefficient of friction applied to flings/scrolls.
 */
const double SCROLL_FRICTION = 0.015;
double DECELERATION_RATE = math.log(0.78) / math.log(0.9);
const double INFLEXION = 0.35; // Tension lines cross at (INFLEXION, 1)

bool _bInited = false;

void _initConsts() {
  if (_bInited) {
    return;
  }
  _bInited = true;

  double x_min = 0.0;
  double y_min = 0.0;
  for (var i = 0; i < _NB_SAMPLES; i++) {
    final double alpha = i.toDouble() / _NB_SAMPLES;

    double x_max = 1.0;
    double x, tx, coef;
    while (true) {
      x = x_min + (x_max - x_min) / 2.0;
      coef = 3.0 * x * (1.0 - x);
      tx = coef * ((1.0 - x) * _P1 + x * _P2) + x * x * x;
      if ((tx - alpha).abs() < 1E-5) break;
      if (tx > alpha)
        x_max = x;
      else
        x_min = x;
    }
    _SPLINE_POSITION[i] = coef * ((1.0 - x) * _START_TENSION + x) + x * x * x;

    double y_max = 1.0;
    double y, dy;
    while (true) {
      y = y_min + (y_max - y_min) / 2.0;
      coef = 3.0 * y * (1.0 - y);
      dy = coef * ((1.0 - y) * _START_TENSION + y) + y * y * y;
      if ((dy - alpha).abs() < 1E-5) break;
      if (dy > alpha)
        y_max = y;
      else
        y_min = y;
    }
    _SPLINE_TIME[i] = coef * ((1.0 - y) * _P1 + y * _P2) + y * y * y;
  }
  _SPLINE_POSITION[_NB_SAMPLES] = _SPLINE_TIME[_NB_SAMPLES] = 1.0;
}

class AndroidScrollerSimulation extends Simulation {
  AndroidScrollerSimulation({
    this.position = 0,
    this.velocity = 0,
    this.friction = 0.015,
    Tolerance tolerance = Tolerance.defaultTolerance,
  }) : super(tolerance: tolerance) {
    _initConsts();
    _physicalCoeff = computeDeceleration(0.84);
    _duration = getSplineFlingDuration(velocity);
    print('zzzzz' + _duration.toString());
    _distance = getSplineFlingDistance(velocity);
    print('zzzzz' + _distance.toString());
  }

  /// The position of the particle at the beginning of the simulation.
  final double position;

  /// The velocity at which the particle is traveling at the beginning of the
  /// simulation.
  final double velocity;

  /// The amount of friction the particle experiences as it travels.
  ///
  /// The more friction the particle experiences, the sooner it stops.
  final double friction;

  double _duration = 0;
  double _distance = 0;
  double _physicalCoeff = 0;

  double getSplineFlingDistance(double velocity) {
    final double l = getSplineDeceleration(velocity);
    final double decelMinusOne = DECELERATION_RATE - 1.0;
    return friction * _physicalCoeff * math.exp(DECELERATION_RATE / decelMinusOne * l);
  }

  void computeCurrX(double timePassed) {}

  double getSplineFlingDuration(double velocity) {
    final double l = getSplineDeceleration(velocity);
    final double decelMinusOne = DECELERATION_RATE - 1.0;
    return math.exp(l / decelMinusOne);
  }

  ///friction = miu
  ///_physicalCoeff = cos*g
  ///friction * _physicalCoeff = a
  ///v/a = t
  ///
  double getSplineDeceleration(double velocity) {

    // 0.35 * 8000 = 2800
    // 0.015 * 51855.0144 = 777
    // div = 3.6
    // ln = 1.28
    return math.log(INFLEXION * velocity.abs() / (friction * _physicalCoeff));
  }

  //400 128978.976
  //160 51855.0144
  double computeDeceleration(double friction) {
    int mPpi = 160;
    return 9.80665 // g (m/s^2)f
        *
        39.37 // inch/meter
        *
        mPpi // pixels per inch
        *
        friction;
  }

  @override
  double dx(double time) {
    final double t = time / _duration;
    final int index = (_NB_SAMPLES * t).toInt();
    double distanceCoef = 1;
    double velocityCoef = 0;
    if (index < _NB_SAMPLES) {
      final double t_inf = index / _NB_SAMPLES;
      final double t_sup = (index + 1) / _NB_SAMPLES;
      final double d_inf = _SPLINE_POSITION[index];
      final double d_sup = _SPLINE_POSITION[index + 1];
      velocityCoef = (d_sup - d_inf) / (t_sup - t_inf);
      distanceCoef = d_inf + (t - t_inf) * velocityCoef;
    }
    double mCurrVelocity;
    mCurrVelocity = velocityCoef * _distance / _duration;
    print('zzzzzv' + mCurrVelocity.toString());
    return mCurrVelocity;
  }

  @override
  bool isDone(double time) {
    return time >= _duration;
  }

  @override
  double x(double time) {
    final double t = time / _duration;
    final int index = (_NB_SAMPLES * t).toInt();
    double distanceCoef = 1;
    double velocityCoef = 0;
    if (index < _NB_SAMPLES) {
      final double t_inf = index / _NB_SAMPLES;
      final double t_sup = (index + 1) / _NB_SAMPLES;
      final double d_inf = _SPLINE_POSITION[index];
      final double d_sup = _SPLINE_POSITION[index + 1];
      velocityCoef = (d_sup - d_inf) / (t_sup - t_inf);
      distanceCoef = d_inf + (t - t_inf) * velocityCoef;
    }
    double mCurrVelocity;
    mCurrVelocity = velocityCoef * _distance / _duration;
    double result = distanceCoef * _distance * velocity.sign;
    print('zzzzzd' + result.toString());
    // int mStartX = 0;
    return position + result;
  }
}

// class ClampingScrollSimulation extends Simulation {
//   /// Creates a scroll physics simulation that matches Android scrolling.
//   ClampingScrollSimulation({
//     @required this.position,
//     @required this.velocity,
//     this.friction = 0.015,
//     Tolerance tolerance = Tolerance.defaultTolerance,
//   }) : assert(_flingVelocityPenetration(0.0) == _initialVelocityPenetration),
//         super(tolerance: tolerance) {
//     _duration = _flingDuration(velocity);
//     _distance = (velocity * _duration / _initialVelocityPenetration).abs();
//   }
//
//   /// The position of the particle at the beginning of the simulation.
//   final double position;
//
//   /// The velocity at which the particle is traveling at the beginning of the
//   /// simulation.
//   final double velocity;
//
//   /// The amount of friction the particle experiences as it travels.
//   ///
//   /// The more friction the particle experiences, the sooner it stops.
//   final double friction;
//
//   double _duration;
//   double _distance;
//
//   // See DECELERATION_RATE.
//   static final double _kDecelerationRate = math.log(0.78) / math.log(0.9);
//
//   // See computeDeceleration().
//   static double _decelerationForFriction(double friction) {
//     return friction * 61774.04968;
//   }
//
//   // See getSplineFlingDuration(). Returns a value in seconds.
//   double _flingDuration(double velocity) {
//     // See mPhysicalCoeff
//     final double scaledFriction = friction * _decelerationForFriction(0.84);
//
//     // See getSplineDeceleration().
//     final double deceleration = math.log(0.35 * velocity.abs() / scaledFriction);
//
//     return math.exp(deceleration / (_kDecelerationRate - 1.0));
//   }
//
//   // Based on a cubic curve fit to the Scroller.computeScrollOffset() values
//   // produced for an initial velocity of 4000. The value of Scroller.getDuration()
//   // and Scroller.getFinalY() were 686ms and 961 pixels respectively.
//   //
//   // Algebra courtesy of Wolfram Alpha.
//   //
//   // f(x) = scrollOffset, x is time in milliseconds
//   // f(x) = 3.60882×10^-6 x^3 - 0.00668009 x^2 + 4.29427 x - 3.15307
//   // f(x) = 3.60882×10^-6 x^3 - 0.00668009 x^2 + 4.29427 x, so f(0) is 0
//   // f(686ms) = 961 pixels
//   // Scale to f(0 <= t <= 1.0), x = t * 686
//   // f(t) = 1165.03 t^3 - 3143.62 t^2 + 2945.87 t
//   // Scale f(t) so that 0.0 <= f(t) <= 1.0
//   // f(t) = (1165.03 t^3 - 3143.62 t^2 + 2945.87 t) / 961.0
//   //      = 1.2 t^3 - 3.27 t^2 + 3.065 t
//   static const double _initialVelocityPenetration = 3.065;
//   static double _flingDistancePenetration(double t) {
//     return (1.2 * t * t * t) - (3.27 * t * t) + (_initialVelocityPenetration * t);
//   }
//
//   // The derivative of the _flingDistancePenetration() function.
//   static double _flingVelocityPenetration(double t) {
//     return (3.6 * t * t) - (6.54 * t) + _initialVelocityPenetration;
//   }
//
//   @override
//   double x(double time) {
//     final double t = (time / _duration).clamp(0.0, 1.0);
//     return position + _distance * _flingDistancePenetration(t) * velocity.sign;
//   }
//
//   @override
//   double dx(double time) {
//     final double t = (time / _duration).clamp(0.0, 1.0);
//     return _distance * _flingVelocityPenetration(t) * velocity.sign / _duration;
//   }
//
//   @override
//   bool isDone(double time) {
//     return time >= _duration;
//   }
// }
