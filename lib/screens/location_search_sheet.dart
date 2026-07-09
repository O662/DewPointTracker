import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/saved_place.dart';
import '../services/place_search_service.dart';
import '../state/weather_controller.dart';

/// Result of [showLocationSearchSheet]:
///   • `null` → cancelled, no change
///   • [LocationChoice.myLocation] → follow the device location again
///   • [LocationChoice.place] → show weather for the chosen place
class LocationChoice {
  const LocationChoice._({this.place, this.useMyLocation = false});

  const LocationChoice.myLocation() : this._(useMyLocation: true);
  const LocationChoice.forPlace(SavedPlace place) : this._(place: place);

  final SavedPlace? place;
  final bool useMyLocation;
}

/// Opens the place search sheet and applies the user's choice to [controller].
Future<void> openLocationSearch(
  BuildContext context,
  WeatherController controller,
) async {
  final choice = await showLocationSearchSheet(context, controller);
  if (choice == null) return;
  if (choice.useMyLocation) {
    await controller.useMyLocation();
  } else if (choice.place case final place?) {
    await controller.selectPlace(place);
  }
}

Future<LocationChoice?> showLocationSearchSheet(
  BuildContext context,
  WeatherController controller,
) {
  return showModalBottomSheet<LocationChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LocationSearchSheet(controller: controller),
  );
}

class _LocationSearchSheet extends StatefulWidget {
  const _LocationSearchSheet({required this.controller});

  final WeatherController controller;

  @override
  State<_LocationSearchSheet> createState() => _LocationSearchSheetState();
}

class _LocationSearchSheetState extends State<_LocationSearchSheet> {
  final PlaceSearchService _service = PlaceSearchService();
  final TextEditingController _query = TextEditingController();

  Timer? _debounce;
  List<SavedPlace> _results = const [];
  bool _searching = false;
  bool _failed = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
        _failed = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(text));
  }

  Future<void> _search(String text) async {
    try {
      final results = await _service.search(text);
      if (!mounted || _query.text != text) return;
      setState(() {
        _results = results;
        _searching = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || _query.text != text) return;
      setState(() {
        _results = const [];
        _searching = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.78;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: const Color(0xFF161E33).withValues(alpha: 0.96),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Row(
                    children: [
                      Icon(Icons.search_rounded,
                          color: Color(0xFF4FB0E8), size: 26),
                      SizedBox(width: 10),
                      Text(
                        'Change location',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _query,
                    autofocus: true,
                    autocorrect: false,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(color: Colors.white),
                    onChanged: _onQueryChanged,
                    decoration: InputDecoration(
                      hintText: 'City or town name…',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      prefixIcon: Icon(Icons.place_rounded,
                          color: Colors.white.withValues(alpha: 0.5)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF4FB0E8)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Flexible(
                    // Favorites can be toggled from inside the sheet, so the
                    // list has to follow controller changes live.
                    child: ListenableBuilder(
                      listenable: widget.controller,
                      builder: (context, _) => ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(top: 6, bottom: 10),
                        children: _buildTiles(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTiles(BuildContext context) {
    final controller = widget.controller;
    final hasQuery = _query.text.trim().length >= 2;

    if (!hasQuery) {
      // Idle sheet: quick access to the device location and starred places.
      return [
        if (controller.usingSavedPlace)
          _ResultTile(
            icon: Icons.my_location_rounded,
            iconColor: const Color(0xFF35D29A),
            title: 'Use my location',
            subtitle: 'Follow this device again',
            onTap: () => Navigator.of(context)
                .pop(const LocationChoice.myLocation()),
          ),
        if (controller.favorites.isNotEmpty) ...[
          _sectionLabel('FAVORITES'),
          for (final place in controller.favorites)
            _ResultTile(
              icon: Icons.location_city_rounded,
              iconColor: const Color(0xFF4FB0E8),
              title: place.name,
              subtitle: place.region,
              onTap: () =>
                  Navigator.of(context).pop(LocationChoice.forPlace(place)),
              trailing: _FavoriteStar(
                isFavorite: true,
                onPressed: () => controller.toggleFavorite(place),
              ),
            ),
        ] else
          _hint('Search for a city, then tap the star to save it '
              'as a favorite. Swipe on the weather page to switch.'),
      ];
    }

    if (_searching) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 22),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
          ),
        ),
      ];
    }
    if (_failed) {
      return [_hint('Search failed. Check your connection.')];
    }
    if (_results.isEmpty) {
      return [_hint('No places found for “${_query.text.trim()}”.')];
    }
    return [
      for (final place in _results)
        _ResultTile(
          icon: Icons.location_city_rounded,
          iconColor: const Color(0xFF4FB0E8),
          title: place.name,
          subtitle: place.region,
          onTap: () =>
              Navigator.of(context).pop(LocationChoice.forPlace(place)),
          trailing: _FavoriteStar(
            isFavorite: widget.controller.isFavorite(place),
            onPressed: () => widget.controller.toggleFavorite(place),
          ),
        ),
    ];
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 14, 6, 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      );

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13.5,
            ),
          ),
        ),
      );
}

class _FavoriteStar extends StatelessWidget {
  const _FavoriteStar({required this.isFavorite, required this.onPressed});

  final bool isFavorite;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
      icon: Icon(
        isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
        size: 24,
        color: isFavorite
            ? const Color(0xFFFFD54F)
            : Colors.white.withValues(alpha: 0.45),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
      trailing: trailing,
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12.5,
              ),
            ),
    );
  }
}
