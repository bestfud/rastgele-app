import 'package:flutter/material.dart';

import '../models/app_models.dart';

enum AppScoreVisualState { scored, estimated, calculating }

class AppScoreStyle {
  const AppScoreStyle({
    required this.background,
    required this.foreground,
    required this.border,
    required this.shadow,
  });

  final Color background;
  final Color foreground;
  final Color border;
  final Color shadow;

  factory AppScoreStyle.fromState({
    required AppScoreVisualState state,
    required String? rawLabel,
  }) {
    if (state == AppScoreVisualState.calculating) {
      return const AppScoreStyle(
        background: Color(0xFFF3F5F7),
        foreground: Color(0xFF7A8794),
        border: Color(0xFFE4E8ED),
        shadow: Color(0x1A8793A1),
      );
    }

    if (state == AppScoreVisualState.estimated) {
      return const AppScoreStyle(
        background: Color(0xFFEEF4F7),
        foreground: Color(0xFF4A6575),
        border: Color(0xFFD9E5EB),
        shadow: Color(0x163E677F),
      );
    }

    switch (_normalizedScoreKey(rawLabel)) {
      case 'excellent':
        return const AppScoreStyle(
          background: Color(0xFFE6F4EA),
          foreground: Color(0xFF245C38),
          border: Color(0xFFCBE3D2),
          shadow: Color(0x1A2D6A42),
        );
      case 'good':
        return const AppScoreStyle(
          background: Color(0xFFE7F1EE),
          foreground: Color(0xFF2D5E5A),
          border: Color(0xFFCEE1DC),
          shadow: Color(0x163A6D69),
        );
      case 'medium':
        return const AppScoreStyle(
          background: Color(0xFFFFF4DA),
          foreground: Color(0xFF8A6628),
          border: Color(0xFFF0E0B1),
          shadow: Color(0x14A98535),
        );
      case 'weak':
      case 'bad':
        return const AppScoreStyle(
          background: Color(0xFFF9E7E5),
          foreground: Color(0xFF93473E),
          border: Color(0xFFEBCAC5),
          shadow: Color(0x16A05248),
        );
      default:
        return const AppScoreStyle(
          background: Color(0xFFEEF2F5),
          foreground: Color(0xFF4B5B66),
          border: Color(0xFFDCE4EA),
          shadow: Color(0x12394C59),
        );
    }
  }
}

class AppScorePresentation {
  const AppScorePresentation({
    required this.value,
    required this.label,
    required this.summary,
    required this.state,
    required this.style,
    required this.rawLabel,
  });

  final int? value;
  final String label;
  final String? summary;
  final AppScoreVisualState state;
  final AppScoreStyle style;
  final String? rawLabel;

  bool get hasScore => value != null;
}

AppScorePresentation buildScorePresentation({
  FishingScore? score,
  WeatherSnapshot? weatherSnapshot,
}) {
  final state = resolveScoreVisualState(
    score: score,
    weatherSnapshot: weatherSnapshot,
  );
  final rawLabel = score?.scoreLabel;
  final label = state == AppScoreVisualState.scored
      ? localizedScoreLabel(rawLabel)
      : 'Hesaplanıyor';
  final summary = _normalizedSummary(
    state == AppScoreVisualState.scored
        ? score?.scoreSummary
        : (weatherSnapshot != null
              ? 'Yeni skor hazırlanıyor.'
              : 'Skor verisi işleniyor.'),
  );

  return AppScorePresentation(
    value: score?.scoreValue,
    label: label,
    summary: summary,
    state: state,
    style: AppScoreStyle.fromState(
      state: state,
      rawLabel: rawLabel,
    ),
    rawLabel: rawLabel,
  );
}

AppScorePresentation buildPostScorePresentation(SocialPost post) {
  if (post.linkedSpotScoreValue == null) {
    return AppScorePresentation(
      value: null,
      label: 'Hesaplanıyor',
      summary: null,
      state: AppScoreVisualState.calculating,
      style: AppScoreStyle.fromState(
        state: AppScoreVisualState.calculating,
        rawLabel: null,
      ),
      rawLabel: null,
    );
  }

  return AppScorePresentation(
    value: post.linkedSpotScoreValue,
    label: localizedScoreLabel(post.linkedSpotScoreLabel),
    summary: _normalizedSummary(post.linkedSpotScoreSummary),
    state: AppScoreVisualState.scored,
    style: AppScoreStyle.fromState(
      state: AppScoreVisualState.scored,
      rawLabel: post.linkedSpotScoreLabel,
    ),
    rawLabel: post.linkedSpotScoreLabel,
  );
}

AppScoreVisualState resolveScoreVisualState({
  required FishingScore? score,
  required WeatherSnapshot? weatherSnapshot,
}) {
  if (score?.scoreValue != null) {
    return AppScoreVisualState.scored;
  }

  if (weatherSnapshot != null) {
    return AppScoreVisualState.estimated;
  }

  return AppScoreVisualState.calculating;
}

String localizedScoreLabel(String? rawLabel) {
  switch (_normalizedScoreKey(rawLabel)) {
    case 'excellent':
      return 'Çok iyi';
    case 'good':
      return 'İyi';
    case 'medium':
      return 'Orta';
    case 'weak':
      return 'Zayıf';
    case 'bad':
      return 'Kötü';
    default:
      return 'Skor';
  }
}

String? shortScoreSummary(String? summary, {int maxLength = 88}) {
  final normalized = _normalizedSummary(summary);
  if (normalized == null) {
    return null;
  }

  if (normalized.length <= maxLength) {
    return normalized;
  }

  return '${normalized.substring(0, maxLength - 3)}...';
}

String _normalizedScoreKey(String? rawLabel) {
  final normalized = (rawLabel ?? '').trim().toLowerCase();
  switch (normalized) {
    case 'great':
    case 'excellent':
    case 'çok iyi':
      return 'excellent';
    case 'good':
    case 'iyi':
      return 'good';
    case 'fair':
    case 'medium':
    case 'average':
    case 'orta':
      return 'medium';
    case 'poor':
    case 'weak':
    case 'zayıf':
    case 'zayif':
      return 'weak';
    case 'low':
    case 'bad':
    case 'kötü':
    case 'kotu':
      return 'bad';
    default:
      return normalized;
  }
}

String? _normalizedSummary(String? summary) {
  final text = summary?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }

  return text.replaceAll(RegExp(r'\s+'), ' ');
}
