import 'package:flutter/animation.dart';

class AppMotion {
  AppMotion._();

  static const Duration page = Duration(milliseconds: 340);
  static const Duration pageFast = Duration(milliseconds: 220);
  static const Duration card = Duration(milliseconds: 260);
  static const Duration micro = Duration(milliseconds: 160);

  static const Curve emphasized = Cubic(0.22, 1, 0.36, 1);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve decelerate = Curves.easeOut;
}
