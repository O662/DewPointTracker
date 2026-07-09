import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_place.dart';
import '../models/units.dart';
import '../models/weather_data.dart';
import '../radar_config.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/widget_bridge.dart';

enum LoadStatus { idle, loading, ready, error }

/// Weather state for one swipeable location page: either the device location
/// ([place] == null) or a saved/favorite place. Each slot fetches and caches
/// independently so swiping between locations is instant once loaded.
class WeatherSlot {
  WeatherSlot({this.place});

  /// null → follow the device GPS location.
  final SavedPlace? place;

  LoadStatus status = LoadStatus.idle;
  WeatherData? weather;
  String? label;
  double? latitude;
  double? longitude;
  String errorMessage = '';
  bool permissionBlocked = false;
  DateTime? lastFetched;

  bool get isDevice => place == null;
  String get key => place?.id ?? 'gps';

  bool isStale(Duration maxAge) {
    final last = lastFetched;
    return last == null || DateTime.now().difference(last) > maxAge;
  }
}

/// Owns the per-location weather slots (device + favorites), the favorites
/// list, the home-card layout order, and the chosen display unit.
class WeatherController extends ChangeNotifier {
  WeatherController({
    WeatherService? weatherService,
    LocationService? locationService,
  })  : _weatherService = weatherService ?? WeatherService(),
        _locationService = locationService ?? LocationService() {
    _rebuildSlots();
  }

  static const _placePrefsKey = 'selected_place';
  static const _favoritesPrefsKey = 'favorite_places';
  static const _cardOrderPrefsKey = 'home_card_order';
  static const _radarPastPrefsKey = 'radar_past_hours';
  static const _radarFuturePrefsKey = 'radar_future_hours';
  static const _profanityFilterPrefsKey = 'profanity_filter';
  static const _unitPrefsKey = 'temp_unit';

  /// Ids of the reorderable home cards, in default order.
  static const defaultCardOrder = [
    'hilo',
    'dewpoint',
    'metrics',
    'hourly',
    'daily',
  ];

  /// How often weather silently re-fetches in the background, and how old the
  /// data may get before a resume/tab-switch triggers a refresh. Open-Meteo
  /// updates its current conditions every ~15 minutes.
  static const autoRefreshInterval = Duration(minutes: 15);
  static const staleAfter = Duration(minutes: 10);

  final WeatherService _weatherService;
  final LocationService _locationService;

  TempUnit unit = TempUnit.fahrenheit;

  /// User's starred places, in the order they appear as swipe pages.
  List<SavedPlace> favorites = [];

  /// Home-screen card order (drag-to-reorder, persisted).
  List<String> cardOrder = List.of(defaultCardOrder);

  /// User-tunable radar timeline range (Settings page, persisted). Applies
  /// to the US NEXRAD/HRRR timeline; the RainViewer fallback serves fixed
  /// ranges regardless.
  int radarPastHours = kDefaultRadarPastHours;
  int radarFutureHours = kDefaultRadarFutureHours;

  /// Keeps the dew point blurbs family-friendly (Settings page, persisted).
  /// Turning it off switches the gauge to the uncensored blurb pool.
  bool profanityFilter = true;

  /// The place currently being viewed (null = device location). Persisted.
  SavedPlace? place;

  /// A searched place that isn't a favorite — shown as the last swipe page so
  /// picking a one-off city doesn't require starring it.
  SavedPlace? _transient;

  final Map<String, WeatherSlot> _slotCache = {};
  List<WeatherSlot> _slots = const [];

  bool _restored = false;
  Timer? _refreshTimer;

  // ---------------------------------------------------------------------
  // Slots & selection
  // ---------------------------------------------------------------------

  /// The swipeable pages: device location first, then favorites in order,
  /// then (if present) the transient searched place.
  List<WeatherSlot> get slots => _slots;

  /// Index of the slot currently being viewed.
  int get activeIndex {
    final key = place?.id ?? 'gps';
    final i = _slots.indexWhere((s) => s.key == key);
    return i < 0 ? 0 : i;
  }

  WeatherSlot get active => _slots[activeIndex];

  // Compatibility surface — the rest of the app (radar, home states) reads
  // the active slot through these.
  LoadStatus get status => active.status;
  WeatherData? get weather => active.weather;
  String? get locationLabel => active.label;
  double? get latitude => active.latitude;
  double? get longitude => active.longitude;
  String get errorMessage => active.errorMessage;
  bool get permissionBlocked => active.permissionBlocked;
  bool get isLoading => status == LoadStatus.loading;
  bool get usingSavedPlace => place != null;

  WeatherSlot _slotFor(SavedPlace? p) =>
      _slotCache.putIfAbsent(p?.id ?? 'gps', () => WeatherSlot(place: p));

  void _rebuildSlots() {
    _slots = [
      _slotFor(null),
      for (final f in favorites) _slotFor(f),
      if (_transient case final t? when !isFavorite(t)) _slotFor(t),
    ];
  }

  /// Called by the home PageView when the user swipes to another location.
  void setActivePage(int index) {
    if (index < 0 || index >= _slots.length) return;
    final slot = _slots[index];
    if (slot.key == (place?.id ?? 'gps')) return;
    place = slot.place;
    _persistSelectedPlace();
    notifyListeners();
    if (slot.weather == null || slot.isStale(staleAfter)) {
      refreshSlot(slot);
    }
  }

  // ---------------------------------------------------------------------
  // Favorites
  // ---------------------------------------------------------------------

  bool isFavorite(SavedPlace p) => favorites.any((f) => f.id == p.id);

  void toggleFavorite(SavedPlace p) {
    if (isFavorite(p)) {
      favorites.removeWhere((f) => f.id == p.id);
      // Keep the page under the user's thumb: an unstarred but currently
      // viewed place lives on as the transient page instead of vanishing.
      if (place?.id == p.id) _transient = p;
    } else {
      favorites.add(p);
      if (_transient?.id == p.id) _transient = null;
    }
    _rebuildSlots();
    _persistFavorites();
    notifyListeners();
    // Pre-warm the new page so swiping to it is instant.
    final slot = _slotCache[p.id];
    if (slot != null && isFavorite(p) && slot.weather == null) {
      refreshSlot(slot);
    }
  }

  // ---------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------

  /// Restore persisted state (first call) and fetch the active location.
  /// Safe to call repeatedly (retry / pull-to-refresh).
  Future<void> load() async {
    if (!_restored) {
      await _restore();
    }
    await refreshSlot(active, force: true);
  }

  /// Fetch weather for one slot. Skips if already loading, or if the slot is
  /// fresh and [force] is false.
  Future<void> refreshSlot(WeatherSlot slot, {bool force = false}) async {
    if (slot.status == LoadStatus.loading) return;
    if (!force && slot.weather != null && !slot.isStale(staleAfter)) return;

    slot.status = LoadStatus.loading;
    slot.errorMessage = '';
    slot.permissionBlocked = false;
    notifyListeners();

    try {
      if (slot.place case final p?) {
        slot.latitude = p.latitude;
        slot.longitude = p.longitude;
        slot.label = p.label;
      } else {
        final location = await _locationService.current();
        slot.latitude = location.latitude;
        slot.longitude = location.longitude;
        slot.label = location.label;
        // Home-screen widgets can't use location services in the background;
        // they follow the app's most recent fix instead.
        unawaited(WidgetBridge.saveLastFix(
          latitude: location.latitude,
          longitude: location.longitude,
          label: location.label,
        ));
      }

      slot.weather = await _weatherService.fetch(
        latitude: slot.latitude!,
        longitude: slot.longitude!,
      );
      slot.lastFetched = DateTime.now();
      slot.status = LoadStatus.ready;
      if (slot.key == active.key) unawaited(WidgetBridge.sync());
    } on LocationException catch (e) {
      slot.errorMessage = e.message;
      slot.permissionBlocked = e.openSettings;
      slot.status = LoadStatus.error;
    } on WeatherException catch (e) {
      slot.errorMessage = e.message;
      slot.status = LoadStatus.error;
    } catch (e) {
      slot.errorMessage = 'Something went wrong while loading weather.';
      slot.status = LoadStatus.error;
    }
    notifyListeners();
  }

  /// Show weather for a searched place from now on (persisted).
  Future<void> selectPlace(SavedPlace newPlace) async {
    place = newPlace;
    if (!isFavorite(newPlace)) _transient = newPlace;
    _rebuildSlots();
    _persistSelectedPlace();
    notifyListeners();
    await refreshSlot(active, force: true);
  }

  /// Go back to following the device location (clears any saved place).
  Future<void> useMyLocation() async {
    place = null;
    _persistSelectedPlace();
    notifyListeners();
    await refreshSlot(active, force: true);
  }

  /// Keeps the displayed conditions current without any user action.
  void startAutoRefresh() {
    _refreshTimer ??= Timer.periodic(autoRefreshInterval, (_) {
      if (!isLoading) refreshSlot(active, force: true);
    });
  }

  /// Refresh only if the data is old — used when the app returns to the
  /// foreground so a quick app-switch doesn't refetch needlessly.
  Future<void> refreshIfStale() async {
    if (isLoading) return;
    if (active.isStale(staleAfter)) {
      await refreshSlot(active, force: true);
    }
  }

  // ---------------------------------------------------------------------
  // Home-card layout
  // ---------------------------------------------------------------------

  /// Move a home card from [oldIndex] to [newIndex] (already adjusted for
  /// ReorderableListView's removal offset).
  void moveCard(int oldIndex, int newIndex) {
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= cardOrder.length ||
        newIndex < 0 ||
        newIndex >= cardOrder.length) {
      return;
    }
    final id = cardOrder.removeAt(oldIndex);
    cardOrder.insert(newIndex, id);
    notifyListeners();
    _persistCardOrder();
  }

  // ---------------------------------------------------------------------
  // Radar settings
  // ---------------------------------------------------------------------

  /// Update the radar timeline range (either or both ends), clamped to what
  /// the sources support. The radar screen listens and rebuilds its timeline.
  void setRadarRange({int? pastHours, int? futureHours}) {
    var changed = false;
    if (pastHours != null) {
      final v = pastHours.clamp(kMinRadarPastHours, kMaxRadarPastHours);
      if (v != radarPastHours) {
        radarPastHours = v;
        changed = true;
      }
    }
    if (futureHours != null) {
      final v = futureHours.clamp(kMinRadarFutureHours, kMaxRadarFutureHours);
      if (v != radarFutureHours) {
        radarFutureHours = v;
        changed = true;
      }
    }
    if (!changed) return;
    notifyListeners();
    _persistRadarRange();
  }

  Future<void> _persistRadarRange() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_radarPastPrefsKey, radarPastHours);
      await prefs.setInt(_radarFuturePrefsKey, radarFutureHours);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Blurb settings
  // ---------------------------------------------------------------------

  /// Toggle the dew point blurb profanity filter (Settings page).
  void setProfanityFilter(bool value) {
    if (value == profanityFilter) return;
    profanityFilter = value;
    notifyListeners();
    _persistProfanityFilter().then((_) => WidgetBridge.sync());
  }

  Future<void> _persistProfanityFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_profanityFilterPrefsKey, profanityFilter);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------

  Future<void> _restore() async {
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      favorites = List.of(SavedPlace.decodeList(prefs.getString(_favoritesPrefsKey)));
      place = SavedPlace.decode(prefs.getString(_placePrefsKey));
      if (place case final p? when !isFavorite(p)) _transient = p;

      radarPastHours = (prefs.getInt(_radarPastPrefsKey) ??
              kDefaultRadarPastHours)
          .clamp(kMinRadarPastHours, kMaxRadarPastHours);
      radarFutureHours = (prefs.getInt(_radarFuturePrefsKey) ??
              kDefaultRadarFutureHours)
          .clamp(kMinRadarFutureHours, kMaxRadarFutureHours);

      profanityFilter = prefs.getBool(_profanityFilterPrefsKey) ?? true;
      unit = prefs.getString(_unitPrefsKey) == 'c'
          ? TempUnit.celsius
          : TempUnit.fahrenheit;

      final savedOrder = prefs.getStringList(_cardOrderPrefsKey);
      if (savedOrder != null) {
        // Merge defensively: drop ids we no longer ship, append new ones.
        cardOrder = [
          for (final id in savedOrder)
            if (defaultCardOrder.contains(id)) id,
          for (final id in defaultCardOrder)
            if (!savedOrder.contains(id)) id,
        ];
      }
    } catch (_) {
      // Persistence is best-effort; defaults still work this session.
    }
    _rebuildSlots();
    // Hand the native home-screen widgets the current blurb pools.
    unawaited(WidgetBridge.writeComfortBands());
  }

  Future<void> _persistSelectedPlace() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (place case final p?) {
        await prefs.setString(_placePrefsKey, p.encode());
      } else {
        await prefs.remove(_placePrefsKey);
      }
      // Widgets show the place the app is viewing; retarget them right away.
      await WidgetBridge.sync();
    } catch (_) {}
  }

  Future<void> _persistFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_favoritesPrefsKey, SavedPlace.encodeList(favorites));
    } catch (_) {}
  }

  Future<void> _persistCardOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_cardOrderPrefsKey, cardOrder);
    } catch (_) {}
  }

  void toggleUnit() {
    unit =
        unit == TempUnit.fahrenheit ? TempUnit.celsius : TempUnit.fahrenheit;
    notifyListeners();
    _persistUnit().then((_) => WidgetBridge.sync());
  }

  Future<void> _persistUnit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _unitPrefsKey, unit == TempUnit.celsius ? 'c' : 'f');
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
