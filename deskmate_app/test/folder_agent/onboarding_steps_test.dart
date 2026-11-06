import 'package:deskmate_app/folder_agent/onboarding/onboarding_steps.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('onboardingSteps', () {
    test('macOS with AI: full tour', () {
      expect(onboardingSteps(aiEnabled: true, isMac: true), [
        OnboardingStep.welcome,
        OnboardingStep.appearance,
        OnboardingStep.access,
        OnboardingStep.ai,
        OnboardingStep.folders,
        OnboardingStep.assistant,
        OnboardingStep.models,
        OnboardingStep.privacy,
        OnboardingStep.ready,
      ]);
    });

    test('AI off skips the AI-only steps', () {
      expect(onboardingSteps(aiEnabled: false, isMac: true), [
        OnboardingStep.welcome,
        OnboardingStep.appearance,
        OnboardingStep.access,
        OnboardingStep.ai,
        OnboardingStep.ready,
      ]);
    });

    test('access step is macOS only', () {
      expect(onboardingSteps(aiEnabled: true, isMac: false), isNot(contains(OnboardingStep.access)));
      expect(onboardingSteps(aiEnabled: false, isMac: false), [
        OnboardingStep.welcome,
        OnboardingStep.appearance,
        OnboardingStep.ai,
        OnboardingStep.ready,
      ]);
    });
  });

  test('CTA labels', () {
    expect(onboardingCta(OnboardingStep.welcome), 'Get started');
    expect(onboardingCta(OnboardingStep.ready), 'Start exploring');
    expect(onboardingCta(OnboardingStep.models), 'Continue');
  });

  test('blockers: terms on welcome, a chat model on assistant', () {
    expect(onboardingBlocker(OnboardingStep.welcome, agreedToTerms: false, hasChatModel: true), isNotNull);
    expect(onboardingBlocker(OnboardingStep.welcome, agreedToTerms: true, hasChatModel: false), isNull);
    expect(onboardingBlocker(OnboardingStep.assistant, agreedToTerms: true, hasChatModel: false), isNotNull);
    expect(onboardingBlocker(OnboardingStep.assistant, agreedToTerms: true, hasChatModel: true), isNull);
    expect(onboardingBlocker(OnboardingStep.models, agreedToTerms: false, hasChatModel: false), isNull);
  });
}
