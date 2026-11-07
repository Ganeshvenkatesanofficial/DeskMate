/// The first-run onboarding flow (pure logic; UI in `onboarding_view.dart`).
///
/// Port of FilDOS `onboarding/steps.ts`, adapted to DeskMate: the file-access
/// step only exists on macOS (TCC gates Desktop / Documents / Downloads
/// there), and the folders → assistant → models → privacy steps only when the
/// user opted into AI — they configure the AI layer and mean nothing without it.
library;

enum OnboardingStep { welcome, appearance, access, ai, folders, assistant, models, privacy, ready }

List<OnboardingStep> onboardingSteps({required bool aiEnabled, required bool isMac}) => [
  OnboardingStep.welcome,
  OnboardingStep.appearance,
  if (isMac) OnboardingStep.access,
  OnboardingStep.ai,
  if (aiEnabled) ...[OnboardingStep.folders, OnboardingStep.assistant, OnboardingStep.models, OnboardingStep.privacy],
  OnboardingStep.ready,
];

/// Label of the primary (bottom-right) button on [step].
String onboardingCta(OnboardingStep step) => switch (step) {
  OnboardingStep.welcome => 'Get started',
  OnboardingStep.ready => 'Start exploring',
  _ => 'Continue',
};

/// Why the primary button is disabled on [step], or null when it may advance.
String? onboardingBlocker(OnboardingStep step, {required bool agreedToTerms, required bool hasChatModel}) =>
    switch (step) {
      OnboardingStep.welcome when !agreedToTerms => 'Agree to the Terms & Privacy Policy to continue',
      OnboardingStep.assistant when !hasChatModel => 'Pick an assistant model first',
      _ => null,
    };
