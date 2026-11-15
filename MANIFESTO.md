# Speakboard Manifesto

**The keyboard you would keep even if you never spoke. The dictation you would keep even if you never typed.**

> **Status:** v0.2, 15 Nov 2026, draft for owner review. v0.2 applies two decisions the owner made on 15 Nov 2026: English only at launch (ADR-0010) and one branch with no pull requests (ADR-0013). No code exists yet. Every number in this document is a target we commit to before measuring, not a result. Platform facts are sourced at the end.

## Why this exists

On iPhone today you pick one. Apple's keyboard types beautifully and dictates adequately. The dictation keyboards transcribe beautifully and treat typing as an afterthought: you switch to them to speak, switch back to type, and get bounced through another app to turn the microphone on. One field guide calls it the globe-key tax.

Speakboard refuses the choice. It is one keyboard that is indistinguishable from Apple's when you type and as good as the best dictation products when you talk.

It is not a clone of Wispr Flow or Codex dictation. Those are voice products that happen to ship a keyboard. This is a keyboard, built to Apple's standard, in which voice is a first-class way to enter text.

## The take

Five positions that make this ours.

1. **Keyboard first.** If someone notices they are not on Apple's keyboard, that is a bug. The only visible difference is that the mic is better.
2. **One input stream.** Voice and touch are not modes. Speak a sentence, fix a word with your thumb, keep talking. Nothing to confirm, nothing to switch.
3. **Local by default.** Speech is recognised on the phone. It works in airplane mode, and nothing you say needs a server to become text.
4. **It says what you said.** Cleanup removes the noise of speech. It never adds an idea, changes your tone or rewrites your sentence unless you ask.
5. **A tool, not a feed.** No streaks, no badges, no cards, no upsell inside the keyboard. It shows up, does the job and gets out of the way.

## Principles

**1. Latency is the feature.** Nobody praises a keyboard for being fast. They feel it as theirs, or as broken. Every interaction has a budget, and a missed budget is a bug with the same standing as a crash.

**2. Never drop a frame, never drop a word.** A dropped frame while typing and a lost dictation are the same failure: the tool lost something the user gave it. Audio is kept until its text is confirmed in the field, and every failure has a recovery path the user can see.

**3. The extension is thin.** The keyboard process draws keys and inserts text. Audio, models, storage and anything that touches the network live in the containing app. The keyboard stays small enough that iOS never has a reason to kill it.

**4. Boring where it is a keyboard, exceptional where it is voice.** We do not reinvent layout, gestures, haptics or sounds. We copy Apple exactly and spend our invention on speech.

**5. Honest about the platform.** iOS does not let a keyboard use the microphone. We do not hide that behind private APIs or tricks that break on the next point release. We design so the cost is paid once per session and never in the middle of a thought.

**6. Privacy you can verify.** A keyboard with Full Access can see everything you type. Our answer is structural, not a promise: the keyboard extension contains no networking code at all, and the build fails if that changes.

**7. Measure on the worst phone.** Budgets are checked on the oldest supported iPhone, in Low Power Mode. The newest device proves nothing.

**8. Simulator green is not shipped.** Keyboard extensions fail in ways only a real device shows. Nothing is released without a device run of type, dictate, hop, return, insert.

## Budgets

These are law. A budget changes only through a measured argument in a reviewed change, recorded on its Linear ticket, never because a deadline slipped. CI fails on a regression.

| Typing | Budget |
| -- | -- |
| Touch-down to key highlight, haptic and click | Same frame, with under 2 ms of our main-thread work per key event |
| Touch-up to `insertText` | Same run-loop turn, no async hop |
| Hitches while typing | Zero frames over budget at 120 Hz across a 60-second burst at 10 keys per second |
| Allocations in the keystroke path | Zero |
| Suggestion bar update | Under 30 ms, computed off the main thread, never blocking a key |
| Our share of cold start (`viewDidLoad` to first interactive frame) | Under 150 ms at p95 |
| Extension memory | Under 30 MB steady, under 40 MB peak |

Apple publishes no memory limit for keyboard extensions. Developer reports put the ceiling between roughly 50 and 77 MB, so we assume 50.

| Voice | Budget |
| -- | -- |
| Mic press to capture, with a session armed | Under 50 ms, and the first syllable is never clipped |
| First words visible | Under 400 ms after you start speaking |
| Stop to final text in the field | Under 500 ms at p50 and under 1 s at p95, for up to 30 s of speech, fully on device |
| App hops | At most one per session, zero while a session is armed |
| Lost dictations | Zero |
| Battery cost of an armed, idle session | Under 3% per hour |
| Accuracy | On our own evaluation set, word error rate at or below the best cloud dictation product we can run on the same audio. No release regresses it |

## What "native" means

**Look.** Key sizes, spacing, radii, type, colours, popups and animation curves are measured from the system keyboard on every device size, in light and dark, and measured again on every iOS release. The iOS 26 Liquid Glass keyboard is the visual target. We draw everything ourselves and use no Apple assets.

**Behaviour.** Apple gives custom keyboards no API for the things users assume are part of the platform. Apple's own list of what we must build ourselves: layout per keyboard type, autocorrection and suggestions, auto-capitalisation, double-space period, caps lock and keycap artwork. To that we add what people use without thinking about it: key popups and long-press accents, the space-bar cursor trackpad, accelerating delete, the return key that changes with the field, and haptics and clicks that match the system's.

**Autocorrect is the hard part.** Apple's autocorrect does not come with the platform. A custom keyboard gets a word lexicon and the user's text shortcuts, and nothing else. A keyboard that looks native and corrects badly is worse than one that looks foreign. Typing quality, meaning the touch model plus the language model, is a core product. It gets its own test set and the same attention as dictation.

**What iOS will not let us do, and how we live with it.**

* **Password fields and phone pads.** iOS swaps in the system keyboard. Because we look identical, the swap is invisible.
* **Drawing above the keyboard's top edge.** The suggestion bar gives top-row popups their headroom.
* **Selecting text or showing a correction bubble at the insertion point.** Corrections and undo live in the suggestion bar.

## What "on par" means for dictation

Par is measured, not claimed. The bar is Wispr Flow and Codex dictation as they ship today.

* **Accuracy on real speech.** Accents, noise, names and jargon, in English for version 1. We evaluate on our own recordings of real dictation, not on a clean academic corpus.
* **Cleanup.** Punctuation and capitalisation. Fillers removed. Spoken self-corrections resolved, so "Tuesday, no, Wednesday" becomes "Wednesday". Numbers, dates and lists formatted.
* **Your words.** A personal vocabulary learned on the device from what you type and correct.
* **Speed.** The budgets above.
* **Reversibility.** The raw transcript is one tap away, and one undo restores exactly what was there before.

Where we differ on purpose: local by default, no account to start, no rewriting unless asked, and no switching keyboards to speak.

## The platform, honestly

**The facts.**

* Custom keyboards have no access to the microphone. The containing app must own the audio session, and the keyboard has to open the app to start one. Wispr Flow works this way too.
* Since iOS 26.4, several dictation developers report that a keyboard can no longer send the user back to the previous app automatically, so the user swipes back by hand. We found no statement from Apple and have not verified this on a device yet.
* The keyboard and the app can share data only when the user grants Full Access.

**Our answer.**

* **One hop arms a session.** The session is long-lived, ends on a timeout the user chooses and is always visible as a Live Activity. While it is armed, the mic key works instantly and in place.
* **Arm without the keyboard.** Action Button, Control Center, Shortcuts and the Lock Screen can all arm a session, so the hop often never happens.
* **No private APIs to jump back.** If Apple restores a supported path, we adopt it that day.
* **Capture sits behind one interface.** If Apple ever gives keyboards a microphone, the hop disappears and nothing else changes.

## Privacy contract

1. **What you type never leaves the phone.** The keyboard extension links no networking code, and CI enforces it.
2. **What you say is recognised on the phone.** Audio is deleted once its text is in the field, unless you turn on history, which stays local.
3. **An armed session keeps the microphone session open.** That is the only way iOS lets an app stay ready in the background, and iOS shows its indicator while it does. Outside an explicit press, audio exists only in a sub-second in-memory buffer used to avoid clipping your first syllable. It is never written, transcribed or sent.
4. **No account is needed** to type or dictate.
5. **Diagnostics are opt-in** and contain timings and counters, never text or audio.
6. **Any future cloud feature is off by default,** labelled where it is used, and runs from the app, never from the keyboard.

## What we will not build

* An assistant, a chatbot or a "rewrite this for me" product inside the keyboard.
* Themes, GIFs, stickers or anything else that makes the keyboard feel like an app.
* Streaks, notifications or referral prompts in the keyboard.
* A cross-platform UI layer. The hot path is Swift, UIKit and Core Animation.
* Ads, data sales or training on user content.
* Meeting recording or long-form transcription.
* Android, Mac or Windows versions before the iPhone one is right.

## Open decisions

These are the owner's calls. Each has a recommended default so work is not blocked.

1. **Local only, or local with optional cloud?** Recommended: version 1 is local only. Revisit only if our evaluation shows on-device recognition cannot reach par.
2. **Recognition engine.** Recommended: a bake-off between Apple SpeechAnalyzer, Parakeet on Core ML and WhisperKit, on our own evaluation set, on real iPhones, with the engine behind one protocol. Public benchmarks are vendor-run on Macs. They put all three at roughly 2 to 4% word error rate on clean English and disagree on harder audio.
3. **Minimum iOS version.** Recommended: iOS 26. It gives one visual target, SpeechAnalyzer and Apple's on-device language model.
4. **Launch languages.** Decided by the owner on 15 Nov 2026: English only (ADR-0010). Locale stays a parameter, and layouts, lexicons and rules are data per locale, so a later language is an addition.
5. **Cleanup model.** Recommended: rules plus a small on-device model first, with a cloud model only as an explicit opt-in later.
6. **Business model.** The only constraint from this document is no ads and no data.

## The test

If a change makes Speakboard feel less like Apple's keyboard, or less like being listened to, it does not ship.

## Sources

* Apple, [App Extension Programming Guide: Custom Keyboard](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html): no microphone access, secure fields and phone pads, the top-edge drawing limit, what open access enables, and the features a custom keyboard must build itself.
* Wispr Flow docs, [Set up the Flow keyboard on iPhone](https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone) and [Starting your first dictation](https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation): the app hop and Full Access requirement.
* [Wispr Flow field guide, iPhone chapter](https://github.com/vkorost/wispr-flow-field-guide/blob/main/book/chapters/05-iphone.md): the globe-key tax, the swipe back after iOS 26.4 and reported battery figures. Third party, not verified.
* iOS 26.4 return-to-app change: [Superwhisper docs](https://superwhisper.com/docs/common-issues/ios-26-keyboard-changes), [Apple Developer Forums thread 826851](https://developer.apple.com/forums/thread/826851) and [OpenWhispr PR 2365](https://github.com/OpenWhispr/openwhispr/pull/2365). Developer reports read through search summaries, with no Apple statement found.
* [Dictus iOS issue 281](https://github.com/getdictus/dictus-ios/issues/281): the roughly 50 MB extension ceiling, cold-start failures and a change that passed 516 tests and still crashed on a device.
* On-device recognition benchmarks, all vendor-run and directional only: [Inscribe](https://get-inscribe.com/blog/apple-speech-api-benchmark.html), [Lyonesse](https://lyonesse.app/blog/parakeet-moss-apple-speech-benchmark.html) and [Argmax](https://www.argmaxinc.com/blog/apple-and-argmax).
