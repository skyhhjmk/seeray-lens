import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/features/integration/application/experiment_sample_size.dart';

void main() {
  test('estimates equal sample size for a two-arm conversion test', () {
    final estimate = estimateExperimentSampleSize(
      baselineConversionRate: 0.05,
      relativeMinimumDetectableLift: 0.20,
      confidenceLevel: 95,
      power: 80,
      variantCount: 2,
    );

    expect(estimate.perVariant, inInclusiveRange(8000, 8500));
    expect(estimate.totalExposures, estimate.perVariant * 2);
  });

  test('requires more traffic for smaller effects and stricter certainty', () {
    int estimate({double lift = 0.2, int confidence = 95, int power = 80}) =>
        estimateExperimentSampleSize(
          baselineConversionRate: 0.05,
          relativeMinimumDetectableLift: lift,
          confidenceLevel: confidence,
          power: power,
          variantCount: 2,
        ).perVariant;

    final normal = estimate();
    expect(estimate(lift: 0.1), greaterThan(normal));
    expect(estimate(confidence: 99), greaterThan(normal));
    expect(estimate(power: 90), greaterThan(normal));
  });

  test('rejects impossible baselines, lifts, and experiment sizes', () {
    expect(
      () => estimateExperimentSampleSize(
        baselineConversionRate: 0,
        relativeMinimumDetectableLift: 0.2,
        confidenceLevel: 95,
        power: 80,
        variantCount: 2,
      ),
      throwsArgumentError,
    );
    expect(
      () => estimateExperimentSampleSize(
        baselineConversionRate: 0.6,
        relativeMinimumDetectableLift: 1,
        confidenceLevel: 95,
        power: 80,
        variantCount: 2,
      ),
      throwsArgumentError,
    );
    expect(
      () => estimateExperimentSampleSize(
        baselineConversionRate: 0.05,
        relativeMinimumDetectableLift: 0.2,
        confidenceLevel: 95,
        power: 80,
        variantCount: 1,
      ),
      throwsArgumentError,
    );
  });
}
