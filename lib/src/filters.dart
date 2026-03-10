import 'package:flutter/material.dart';

/// Represents a filter configuration.
class Filter {
  final String name;
  final List<double> matrix;

  const Filter({required this.name, required this.matrix});

  ColorFilter get colorFilter => ColorFilter.matrix(matrix);
}

/// A collection of preset filters.
class PresetFilters {
  static const List<double> _noFilter = [
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  static const List<double> _greyscale = [
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  static const List<double> _sepia = [
    0.393,
    0.769,
    0.189,
    0,
    0,
    0.349,
    0.686,
    0.168,
    0,
    0,
    0.272,
    0.534,
    0.131,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  static const List<double> _invert = [
    -1,
    0,
    0,
    0,
    255,
    0,
    -1,
    0,
    0,
    255,
    0,
    0,
    -1,
    0,
    255,
    0,
    0,
    0,
    1,
    0,
  ];

  // High contrast / "Pop"
  static const List<double> _highContrast = [
    1.5,
    0,
    0,
    0,
    -50,
    0,
    1.5,
    0,
    0,
    -50,
    0,
    0,
    1.5,
    0,
    -50,
    0,
    0,
    0,
    1,
    0,
  ];

  // Vintage / Warm
  static const List<double> _vintage = [
    0.9,
    0.5,
    0.1,
    0,
    0,
    0.3,
    0.8,
    0.1,
    0,
    0,
    0.2,
    0.3,
    0.5,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  // Cool / Blueish
  static const List<double> _cool = [
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1.2,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  // Technicolor imitation
  static const List<double> _technicolor = [
    1.9,
    -0.3,
    -0.2,
    0,
    -30,
    -0.2,
    1.7,
    -0.1,
    0,
    -30,
    -0.1,
    -0.1,
    2.3,
    0,
    -50,
    0,
    0,
    0,
    1,
    0,
  ];

  static const List<Filter> list = [
    Filter(name: "Normal", matrix: _noFilter),
    Filter(name: "B&W", matrix: _greyscale),
    Filter(name: "Sepia", matrix: _sepia),
    Filter(name: "Pop", matrix: _highContrast),
    Filter(name: "Vintage", matrix: _vintage),
    Filter(name: "Cool", matrix: _cool),
    Filter(name: "Techni", matrix: _technicolor),
    Filter(name: "Invert", matrix: _invert),
  ];
}
