import 'package:flutter/material.dart';

import 'units.dart';

/// Human-comfort classification of a dew point value. The bands are the
/// meteorological standard, expressed in Fahrenheit, and are independent of the
/// user's chosen display unit.
enum DewPointComfort {
  dry(
    label: 'Dry',
    blurbs: [
      'Don\'t forget to hydrate!',
      'Crispy air and lip balm weather.',
      'Static shock roulette begins now.',
      'Your skin called and it wants lotion.',
      'Bone dry, hide you houseplants.',
    ],
    spicyBlurbs: [
      'It\'s dry as hell. Drink some damn water.',
      'Moisturize, you crusty bastard.',
      'Chapped lips incoming. Don\'t be a dumbass; balm those lips.',
      'It\'s so damn dry, your sinuses filed a complaint.',
    ],
    color: Color(0xFF4FB0E8),
  ),
  comfortable(
    label: 'Comfortable',
    blurbs: [
      'A good time to get things done!',
      'Perfect porch swing weather.',
      'Air so nice you\'ll forget it\'s there.',
      'It doesn\'t get better than this.',
      'Chef\'s-kiss conditions.',
      'Absolutely delightful out there.',
    ],
    spicyBlurbs: [
      'Hot damn, it\'s nice out!',
      'Get your ass outside, it\'s perfect.',
      'Weather this good and you\'re inside? Bullshit.',
      'Enjoy this shit while it lasts.',
      'It\'s giving bad bitch energy.',
    ],
    color: Color(0xFF35D29A),
  ),
  sticky(
    label: 'Sticky',
    blurbs: [
      'A little humid. :/',
      'The air is giving clingy.',
      'Slightly soupy around the edges.',
      'Your hair is about to get creative.',
      'Noticeable, but survivable.',
    ],
    spicyBlurbs: [
      'Kinda humid. Not tragic, just annoying as hell.',
      'The air\'s starting its clingy bullshit again.',
      'Your hair doesn\'t stand a damn chance.',
      'Mildly sweaty. Whatever. It\'s fine. Dammit.',
      'Sticky enough to piss you off, not enough to brag about.',
      'The air is being a passive-aggressive little shit today.',
      'Not soup yet, but the broth is warming up, dammit.',
      'Humidity\'s at "why is my shirt touching me like that" levels. Ugh.',
      'The atmosphere is flirting with you and it\'s gross as hell.',
      'The air is gaslighting you.',
      'Just sticky enough to ruin your damn hair.',
    ],
    color: Color(0xFFD8D24B),
  ),
  muggy(
    label: 'Muggy',
    blurbs: [
      'Hope you\'re not doing anything strenuous...',
      'The air has opinions today.',
      'Feels like walking through soup.',
      'Going outside: instant regret.',
      'Two blocks out, and you\'ll need a towel for the trip back.',
      'The air is like a warm, wet blanket.',
      'It\'s a good day to stay inside and watch TV.',
      'The air has a bit of an attitude today.',
      'Don\'t wear anything you aren\'t ready to sweat through.',
      'Feels like a warm, wet slap in the face.',
      'Congrats, you\'re marinating now.',
    ],
    spicyBlurbs: [
      'It\'s muggy as hell out there.',
      'The air is thick as shit today.',
      'Every flight of stairs is a damn cardio event now.',
      'You don\'t walk through this air, you goddamn chew it.',
      'The mailbox is a fucking round-trip swamp run.',
      'Sweating in places you didn\'t know you could sweat in. Fucking Fantastic.',
      'The air is 90% moisture and 10% spite, and it\'s pissed at you.',
      'The atmosphere is being shitty today.',
      'If your ex was a dew point, they would be this shit.',
      'Aw, shit.',
    ],
    color: Color(0xFFF2A33C),
  ),
  oppressive(
    label: 'Oppressive',
    blurbs: [
      'Who needs a sauna when you have this?',
      'The atmosphere is 90% swamp.',
      'Breathing counts as exercise today.',
      'Shirt number two is on standby.',
      'Sweat: guaranteed. Dignity: optional.',
      'Can life go back to giving lemons?',
    ],
    spicyBlurbs: [
      'It\'s a goddamn swamp out there.',
      'This air is an asshole.',
      'Hot, wet, and hostile. This weather is straight-up bullshit.',
      'It\'ll take you only five damn minutes to sweat through your shirt.',
      'The air said "fuck you," specifically to you.',
      'Stepping outside is like getting bear-hugged by a wet mattress. Fuck that.',
      'Your car\'s AC is about to earn its whole damn paycheck.',
      'The swamp isn\'t out there anymore. You\'re IN the fucking swamp.',
      'This isn\'t weather, it\'s a hostage situation with a shitty sauna.',
      'Free full-body swamp-ass with every trip outside.',
      'If the weather was a shitty job, it would be customer service on Black Friday.',
      'This is complete and utter bullshit.',
      'Dear life, we\'ll take the fucking lemons over this, thanks.',
      'Aw, hell naw.',
    ],
    color: Color(0xFFEE6C4D),
  ),
  miserable(
    label: 'Miserable',
    blurbs: [
      'Realm of despair. Stay inside and cry.',
      'Outside is canceled.',
      'This is soup. You live in soup now.',
      'The atmosphere is actively hostile.',
      'Even the mosquitoes are tired.',
      'This is the kind of day that makes you question your life choices.',
      'Today\'s forecast: misery with a chance of regret.',
      'Today is an excellent day to stay inside and contemplate your existence.',
      'Today is an exercise in futility. Don\'t go outside.',
      'This is the kind of day that makes you want to quit.',
      'You should get a medal for surviving this weather.',
      'The air is a relentless, oppressive force. Stay inside.',
      'This is the kind of day that makes you want to move to Antarctica.',
      'The air is a cruel, unrelenting adversary. Stay inside.',
      'You should get hazard pay for walking to your car.',
      'The air is a relentless, oppressive force.',
    ],
    spicyBlurbs: [
      'Absolutely fucking miserable. Stay inside.',
      'It\'s like breathing hot soup. Fuck this.',
      'Outdoors is a scam today. Total bullshit.',
      'Satan\'s sweaty asscrack out there.',
      'This dew point is a fucking war crime.',
      'The Geneva Convention should cover this shit.',
      'Outside is Satan\'s armpit and you\'re the fucking deodorant.',
      'Even the devil said "nah, fuck that" and went back inside.',
      'The air isn\'t air anymore. It\'s hot gravy with a grudge. Fuck this.',
      'Whoever ordered this weather can go straight to hell.',
      'This is God\'s crockpot and you\'re the damn brisket.',
      'Abandon all hope, ye who touch that fucking doorknob.',
      'Fuck it, I\'m out.',
      'This shit should be illegal.', 
      'It\'s a goddamn crime against humanity.',
      'This humidity is a fucking war crime.',
      'I did not consent to this shit.',
      'Fuck this, fuck that, fuck everything!',
      'You should get a medal for surviving this shit.',
      'You should get hazard pay for dealing with this shit.',
      'Quick, someone hide this shit before Canada discovers it.',     
    ],
    color: Color(0xFFE3415E),
  );

  const DewPointComfort({
    required this.label,
    required this.blurbs,
    required this.spicyBlurbs,
    required this.color,
  });

  final String label;

  /// Family-friendly one-liners for this band.
  final List<String> blurbs;

  /// Uncensored one-liners, shown only when the profanity filter is off.
  final List<String> spicyBlurbs;

  final Color color;

  /// Today's blurb for this band. Rotates daily — stable across rebuilds all
  /// day (no flicker), fresh tomorrow. [allowProfanity] switches to the
  /// uncensored pool (Settings → profanity filter off). [when] exists for
  /// tests; it defaults to now.
  String blurb({bool allowProfanity = false, DateTime? when}) {
    final pool = allowProfanity ? spicyBlurbs : blurbs;
    final t = when ?? DateTime.now();
    final days =
        DateTime(t.year, t.month, t.day).difference(DateTime(2024)).inDays;
    // Offset by the band index so neighboring bands don't rotate in lockstep.
    return pool[(days + index * 3) % pool.length];
  }

  /// Classify a dew point given in Celsius.
  static DewPointComfort fromCelsius(double dewPointC) {
    final f = celsiusToFahrenheit(dewPointC);
    if (f < 50) return DewPointComfort.dry;
    if (f < 60) return DewPointComfort.comfortable;
    if (f < 65) return DewPointComfort.sticky;
    if (f < 70) return DewPointComfort.muggy;
    if (f < 75) return DewPointComfort.oppressive;
    return DewPointComfort.miserable;
  }
}

/// Lower / upper bounds (in °F) used to lay out the comfort gauge.
const double dewPointGaugeMinF = 35;
const double dewPointGaugeMaxF = 80;

/// Normalised position (0..1) of a Celsius dew point along the comfort gauge.
double dewPointGaugePosition(double dewPointC) {
  final f = celsiusToFahrenheit(dewPointC);
  final t = (f - dewPointGaugeMinF) / (dewPointGaugeMaxF - dewPointGaugeMinF);
  return t.clamp(0.0, 1.0);
}

/// The ordered colours that make up the gauge gradient.
const List<Color> dewPointGaugeColors = [
  Color(0xFF4FB0E8),
  Color(0xFF35D29A),
  Color(0xFFD8D24B),
  Color(0xFFF2A33C),
  Color(0xFFEE6C4D),
  Color(0xFFE3415E),
];
