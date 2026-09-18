import 'dart:math' as math;

class ExperimentSampleSizeEstimate {
  const ExperimentSampleSizeEstimate({
    required this.perVariant,
    required this.totalExposures,
  });

  final int perVariant;
  final int totalExposures;
}

ExperimentSampleSizeEstimate estimateExperimentSampleSize({
  required double baselineConversionRate,
  required double relativeMinimumDetectableLift,
  required int confidenceLevel,
  required int power,
  required int variantCount,
}) {
  if (!baselineConversionRate.isFinite ||
      baselineConversionRate <= 0 ||
      baselineConversionRate >= 1) {
    throw ArgumentError.value(
      baselineConversionRate,
      'baselineConversionRate',
      'must be between 0 and 1',
    );
  }
  if (!relativeMinimumDetectableLift.isFinite ||
      relativeMinimumDetectableLift <= 0 ||
      baselineConversionRate * (1 + relativeMinimumDetectableLift) >= 1) {
    throw ArgumentError.value(
      relativeMinimumDetectableLift,
      'relativeMinimumDetectableLift',
      'must produce a variant conversion rate below 100%',
    );
  }
  if (variantCount < 2 || variantCount > 10) {
    throw ArgumentError.value(variantCount, 'variantCount');
  }

  final alphaZ = switch (confidenceLevel) {
    90 => 1.6448536269514722,
    95 => 1.959963984540054,
    99 => 2.5758293035489004,
    _ => throw ArgumentError.value(confidenceLevel, 'confidenceLevel'),
  };
  final powerZ = switch (power) {
    80 => 0.8416212335729143,
    90 => 1.2815515655446004,
    _ => throw ArgumentError.value(power, 'power'),
  };

  final controlRate = baselineConversionRate;
  final variantRate = controlRate * (1 + relativeMinimumDetectableLift);
  final pooledRate = (controlRate + variantRate) / 2;
  final numerator =
      alphaZ * math.sqrt(2 * pooledRate * (1 - pooledRate)) +
      powerZ *
          math.sqrt(
            controlRate * (1 - controlRate) + variantRate * (1 - variantRate),
          );
  final perVariant =
      (numerator *
              numerator /
              ((variantRate - controlRate) * (variantRate - controlRate)))
          .ceil();

  return ExperimentSampleSizeEstimate(
    perVariant: perVariant,
    // This is a traffic budget across all arms; alpha is not adjusted for
    // multiple pairwise comparisons in experiments with more than two arms.
    totalExposures: perVariant * variantCount,
  );
}
