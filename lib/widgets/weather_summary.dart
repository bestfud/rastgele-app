import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_models.dart';

List<Widget> buildWeatherSummaryChips(
  WeatherSnapshot? weather, {
  required Widget Function(String label) chipBuilder,
}) {
  if (weather == null) {
    return const <Widget>[];
  }

  final chips = <Widget>[
    if (weather.airTemperature != null)
      chipBuilder('${weather.airTemperature!.toStringAsFixed(1)}°'),
    if (weather.windSpeed != null)
      chipBuilder('Rüzgar ${weather.windSpeed!.toStringAsFixed(1)}'),
    if (weather.pressure != null)
      chipBuilder('Basınç ${weather.pressure!.toStringAsFixed(0)}'),
    if (weather.windDirection != null)
      chipBuilder('Yön ${weather.windDirection}°'),
    if (weather.precipitation != null)
      chipBuilder('Yağış ${weather.precipitation!.toStringAsFixed(1)}'),
    if (weather.snapshotTime != null)
      chipBuilder(DateFormat.MMMd().format(weather.snapshotTime!.toLocal())),
  ];

  if (chips.isNotEmpty) {
    return chips;
  }

  return <Widget>[
    chipBuilder('Hava verisi mevcut'),
  ];
}
