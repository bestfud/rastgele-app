import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/app_models.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_ui.dart';

class PostLocationPreviewScreen extends StatefulWidget {
  const PostLocationPreviewScreen({
    super.key,
    required this.post,
  });

  final SocialPost post;

  @override
  State<PostLocationPreviewScreen> createState() =>
      _PostLocationPreviewScreenState();
}

class _PostLocationPreviewScreenState extends State<PostLocationPreviewScreen> {
  late final MapController _mapController;
  late final LatLng _point;
  late double _radiusMeters;
  double _zoom = 11;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _point = LatLng(widget.post.latitude ?? 0, widget.post.longitude ?? 0);
    _radiusMeters = widget.post.hasExactSpotAction ? 350 : 1600;
    _zoom = widget.post.hasExactSpotAction ? 13.2 : 11.2;
  }

  void _setZoom(double nextZoom) {
    _zoom = nextZoom.clamp(8.5, 16.5);
    _mapController.move(_point, _zoom);
    setState(() {});
  }

  String get _radiusLabel {
    if (_radiusMeters >= 1000) {
      return '${(_radiusMeters / 1000).toStringAsFixed(1)} km';
    }

    return '${_radiusMeters.round()} m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Harita seçimi'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.post.locationLabel.isNotEmpty
                  ? widget.post.locationLabel
                  : 'Konum önizleme',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Alanı incele, yarıçapı ayarla ve görünümü hızlıca kontrol et.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: appSoftShadow(theme.colorScheme.primary),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _point,
                          initialZoom: _zoom,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.fishing.app',
                          ),
                          CircleLayer(
                            circles: [
                              CircleMarker(
                                point: _point,
                                radius: _radiusMeters,
                                useRadiusInMeter: true,
                                color: AppColors.primarySoft,
                                borderColor:
                                    AppColors.primary.withValues(alpha: 0.35),
                                borderStrokeWidth: 1.4,
                              ),
                            ],
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _point,
                                width: 56,
                                height: 56,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.card,
                                    shape: BoxShape.circle,
                                    boxShadow: appSoftShadow(
                                        theme.colorScheme.primary),
                                  ),
                                  child: AppIcon(
                                    AppGlyph.spot,
                                    size: 34,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        top: 14,
                        left: 14,
                        right: 14,
                        child: _MapTopSlider(
                          radiusLabel: _radiusLabel,
                          value: _radiusMeters,
                          onChanged: (value) {
                            setState(() {
                              _radiusMeters = value;
                            });
                          },
                        ),
                      ),
                      Positioned(
                        right: 14,
                        top: 110,
                        child: Column(
                          children: [
                            _MapFab(
                              icon: const AppIcon(
                                AppGlyph.follow,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              onTap: () => _setZoom(_zoom + 0.8),
                            ),
                            const SizedBox(height: 10),
                            _MapFab(
                              icon: const Text(
                                '−',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              onTap: () => _setZoom(_zoom - 0.8),
                            ),
                            const SizedBox(height: 10),
                            _MapFab(
                              icon: const AppIcon(
                                AppGlyph.compass,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              onTap: () => _setZoom(_zoom),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 14,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.card.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Seçilen alan',
                                      style:
                                          theme.textTheme.labelLarge?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _radiusLabel,
                                      style:
                                          theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Tamam'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${_point.latitude.toStringAsFixed(5)}, ${_point.longitude.toStringAsFixed(5)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapTopSlider extends StatelessWidget {
  const _MapTopSlider({
    required this.radiusLabel,
    required this.value,
    required this.onChanged,
  });

  final String radiusLabel;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Mesafe',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                radiusLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: 250,
            max: 5000,
            divisions: 19,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _MapFab extends StatelessWidget {
  const _MapFab({
    required this.icon,
    required this.onTap,
  });

  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(child: icon),
        ),
      ),
    );
  }
}
