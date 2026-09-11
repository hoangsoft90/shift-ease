// =============================================================================
// ShiftEase Money Engine — PayRuleTemplate Library (plan2 §5.6, plan1 §7)
// =============================================================================
//
// Purpose: give new users a correct starting configuration per industry +
// country so pay is never miscalculated from the very first use.
//
// INVARIANT-005 applies here too: a template contains ONLY pay-rule material
// (rate, differentials, overtime rules) — never shift time/UI semantics.
//
// The template id is the stable key referenced by the user flow and by golden
// test PAY-010 (tpl-us-ca-nurse).
// =============================================================================

import 'money_types.dart';

/// Country scope of a template library entry.
enum TemplateCountry {
  us,
  uk,
  de;

  static TemplateCountry fromName(String name) =>
      TemplateCountry.values.firstWhere(
        (c) => c.name.toUpperCase() == name.toUpperCase(),
        orElse: () => TemplateCountry.us,
      );
}

/// A ready-made PayRule configuration suggested per industry/country/region.
/// The user picks one, it becomes a versioned PayRule, and every field is
/// editable afterwards (plan2 §5.6 user flow).
class PayRuleTemplate {
  final String id;
  final String name;
  final TemplateCountry country;
  final String? region;
  final String description;

  /// Default base rate — always overridable by the user.
  final double defaultBaseRate;

  final List<PayDifferential> differentials;
  final List<OvertimeRule> overtimeRules;

  const PayRuleTemplate({
    required this.id,
    required this.name,
    required this.country,
    this.region,
    required this.description,
    required this.defaultBaseRate,
    required this.differentials,
    required this.overtimeRules,
  });
}

const PayDifferential _night10 = PayDifferential(
  type: DifferentialType.night,
  mode: DifferentialMode.percent,
  value: 10,
  scope: DifferentialScope.allHoursInShift,
);

const PayDifferential _ukNight30 = PayDifferential(
  type: DifferentialType.night,
  mode: DifferentialMode.percent,
  value: 30,
  scope: DifferentialScope.allHoursInShift,
);

/// Seed library for MVP (US, UK, DE) — plan2 §5.6 table.
///
/// | id | country | overtime rules |
/// |---|---|---|
/// | tpl-us-ca-nurse | US/CA | SHIFT>8h x1.5, WEEK>40h x1.5 (daily OT, CA law) |
/// | tpl-us-ny-nurse | US/NY | WEEK>40h x1.5 |
/// | tpl-us-tx-nurse | US/TX | WEEK>40h x1.5 (federal default) |
/// | tpl-uk-nurse   | UK     | WEEK>39h x1.5 (NHS Agenda for Change) |
/// | tpl-de-nurse   | DE     | DAY>8h x1.5, WEEK>40h x1.5 |
const List<PayRuleTemplate> payRuleTemplateLibrary = [
  PayRuleTemplate(
    id: 'tpl-us-ca-nurse',
    name: 'US Hospital Nurse — California',
    country: TemplateCountry.us,
    region: 'California',
    description:
        'California daily overtime: >8h per shift AND >40h per week, both x1.5.',
    defaultBaseRate: 45,
    differentials: [_night10],
    overtimeRules: [
      OvertimeRule(
          thresholdHours: 8,
          period: OvertimePeriod.shift,
          multiplier: 1.5),
      OvertimeRule(
          thresholdHours: 40, period: OvertimePeriod.week, multiplier: 1.5),
    ],
  ),
  PayRuleTemplate(
    id: 'tpl-us-ny-nurse',
    name: 'US Hospital Nurse — New York',
    country: TemplateCountry.us,
    region: 'New York',
    description: 'New York: weekly overtime only (no daily OT), >40h x1.5.',
    defaultBaseRate: 45,
    differentials: [_night10],
    overtimeRules: [
      OvertimeRule(
          thresholdHours: 40, period: OvertimePeriod.week, multiplier: 1.5),
    ],
  ),
  PayRuleTemplate(
    id: 'tpl-us-tx-nurse',
    name: 'US Hospital Nurse — Texas',
    country: TemplateCountry.us,
    region: 'Texas',
    description: 'Federal default: weekly overtime only, >40h x1.5.',
    defaultBaseRate: 40,
    differentials: [_night10],
    overtimeRules: [
      OvertimeRule(
          thresholdHours: 40, period: OvertimePeriod.week, multiplier: 1.5),
    ],
  ),
  PayRuleTemplate(
    id: 'tpl-uk-nurse',
    name: 'UK NHS Nurse',
    country: TemplateCountry.uk,
    description:
        'NHS Agenda for Change: weekly overtime >39h x1.5; 30% night premium.',
    defaultBaseRate: 20,
    differentials: [_ukNight30],
    overtimeRules: [
      OvertimeRule(
          thresholdHours: 39, period: OvertimePeriod.week, multiplier: 1.5),
    ],
  ),
  PayRuleTemplate(
    id: 'tpl-de-nurse',
    name: 'German Krankenschwester',
    country: TemplateCountry.de,
    description:
        'German labor law: daily >8h x1.5 AND weekly >40h x1.5. Differential '
        'config varies by collective agreement (Tarifvertrag) — left empty so '
        'the user configures their own.',
    defaultBaseRate: 22,
    differentials: [],
    overtimeRules: [
      OvertimeRule(
          thresholdHours: 8, period: OvertimePeriod.day, multiplier: 1.5),
      OvertimeRule(
          thresholdHours: 40, period: OvertimePeriod.week, multiplier: 1.5),
    ],
  ),
];

/// Look up a seed template by its stable id (throws if unknown).
PayRuleTemplate payRuleTemplateById(String id) => payRuleTemplateLibrary
    .firstWhere((t) => t.id == id,
        orElse: () =>
            throw ArgumentError('Unknown PayRuleTemplate id: $id'));
