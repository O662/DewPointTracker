/// Configuration for the radar timeline.
library;

/// Default / allowed hours of radar history. NEXRAD archive tiles are
/// timestamped, so any range works — but frame spacing grows with the range
/// (see RadarService) to keep the number of mounted tile layers sane.
const int kDefaultRadarPastHours = 1;
const int kMinRadarPastHours = 1;
const int kMaxRadarPastHours = 6;

/// Default / allowed hours of forecast radar ahead of "now".
///
/// Inside the continental US these come from the HRRR model via the Iowa
/// State Mesonet tile cache — free, no API key — which forecasts up to 18
/// hours out, so that is the hard ceiling. Outside the US the timeline falls
/// back to RainViewer's short (~30 minute) nowcast regardless of this value.
const int kDefaultRadarFutureHours = 8;
const int kMinRadarFutureHours = 1;
const int kMaxRadarFutureHours = 18;
