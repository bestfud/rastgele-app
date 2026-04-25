import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/spot_repository.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_ui.dart';
import '../widgets/shell_scaffold.dart';
import '../widgets/spot_card.dart';
import 'spot_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({
    super.key,
    required this.repository,
    required this.selectedIndex,
    required this.refreshSeed,
    required this.onSelectTab,
    required this.onOpenAddSpot,
    required this.onOpenCreatePost,
    required this.onOpenSearch,
    required this.onOpenLocation,
    required this.onLogout,
  });

  final SpotRepository repository;
  final int selectedIndex;
  final int refreshSeed;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onOpenAddSpot;
  final VoidCallback onOpenCreatePost;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLocation;
  final VoidCallback onLogout;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late Future<List<SpotFeedItem>> _favoritesFuture;

  @override
  void initState() {
    super.initState();
    _favoritesFuture = widget.repository.fetchFavoriteSpots();
  }

  @override
  void didUpdateWidget(covariant FavoritesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSeed != widget.refreshSeed) {
      _reload();
    }
  }

  Future<void> _reload() async {
    final future = widget.repository.fetchFavoriteSpots();
    setState(() {
      _favoritesFuture = future;
    });
    await future;
  }

  Future<void> _openSpot(SpotFeedItem item) async {
    debugPrint(
      '[SPOT_NAV] tap source=favorites postId=${item.sourcePostId ?? 'null'} passedSpotId=${item.spot.id} linkedSpotId=null linkedFishingSpotId=null itemSpotId=${item.spot.id}',
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpotDetailScreen(
          repository: widget.repository,
          spotId: item.spot.id,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _toggleSavedSpot(SpotFeedItem item) async {
    try {
      await widget.repository.toggleFavorite(
        spotId: item.spot.id,
        shouldFavorite: !item.isSaved,
      );
      if (!mounted) {
        return;
      }
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            item.isSaved
                ? 'Kayıt kaldırılamadı: $error'
                : 'Mera kaydedilemedi: $error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShellScaffold(
      title: 'Favoriler',
      selectedIndex: widget.selectedIndex,
      onSelectIndex: widget.onSelectTab,
      onOpenAddSpot: widget.onOpenAddSpot,
      onOpenCreatePost: widget.onOpenCreatePost,
      onOpenSearch: widget.onOpenSearch,
      onOpenLocation: widget.onOpenLocation,
      onLogout: widget.onLogout,
      body: FutureBuilder<List<SpotFeedItem>>(
        future: _favoritesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Favoriler yüklenemedi: ${snapshot.error}'),
            );
          }

          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                children: const [
                  SizedBox(height: 140),
                  AppEmptyState(
                    iconWidget: AppIcon(
                      AppGlyph.fish,
                      size: 24,
                      color: AppColors.textSecondary,
                    ),
                    message: 'Favori meraların burada listelenecek.',
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return SpotCard(
                  item: item,
                  onTap: () => _openSpot(item),
                  onToggleSaved: () => _toggleSavedSpot(item),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
