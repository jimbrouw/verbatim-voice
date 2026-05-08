Plan for Verbatim

Verdict: good idea, but only worth building if you make it local, fast, cheap, and visually invisible. That is the clear gap in the market.  ￼

1. Positioning

Use this:

Verbatim is the minimalist Mac dictation app that stays out of your way.

Do not position it as another AI writing assistant. That space is crowded. Position it as:

* fast push-to-talk dictation
* system-wide Mac text input
* tiny UI
* privacy-first
* no subscription

1. MVP Feature Set

Build only this first:

1. Global hotkey
    * Hold Left/Right Option to record
    * Release to transcribe and paste
2. System-wide text insertion
    * Works in Slack, Notes, browsers, Word, code editors
3. Tiny recording UI
    * small floating pill
    * no big transcript box
    * optional 3-word menu bar preview
4. Local Whisper transcription
    * use whisper.cpp
    * make privacy the main selling point
5. Basic settings
    * hotkey choice
    * model quality/speed
    * launch at login
    * punctuation on/off

6. Avoid These at First

Do not build:

* AI rewriting
* meeting transcription
* team features
* cloud sync
* complex prompt presets
* mobile app
* big dashboard
* collaboration features

That turns it into Wispr Flow-lite. Bad move.

1. Business Model

Best option:

Tier Price Notes
Free trial £0 limited minutes or 7 days
One-time licence £24–£39 main offer
Pro upgrade later £49–£79 advanced local models/settings

Avoid monthly subscription at launch. The document says subscription fatigue is one of the core market complaints.  ￼

1. Technical Build Plan

Stack

* macOS native app: Swift / SwiftUI
* Audio capture: AVFoundation
* Global hotkey: Carbon/EventTap APIs
* Speech engine: whisper.cpp
* Text insertion: Accessibility API / pasteboard fallback
* Packaging: signed .dmg

Build order

1. Hotkey records audio
2. Save temp audio buffer
3. Send to local Whisper
4. Paste text into active app
5. Add tiny UI state
6. Add settings
7. Sign and package

8. Brand / Domain

Keep Verbatim if possible. It is strong.

Check:

* useverbatim.app
* getverbatim.app
* verbatimvoice.app
* verbatimmac.app
* speakverbatim.app

Best name direction: simple, serious, Mac-native. Avoid cute startup names.

1. Landing Page Structure

One-page site:

1. Hero
    * “Private Mac dictation that stays out of your way.”
    * Button: “Join beta”
2. Demo GIF
    * hold Option → speak → text appears
3. Why different
    * local/private
    * no big floating transcript
    * one-time purchase
    * system-wide
4. Comparison table
    * Verbatim vs Wispr Flow vs Superwhisper
5. Beta signup

6. Launch Strategy

Start with:

* Reddit: r/macapps, r/productivity
* Hacker News “Show HN”
* Product Hunt later, not first
* Mac indie app communities
* short demo videos on X/LinkedIn

Reddit framing:

I liked Wispr Flow but wanted something local, cheaper, and less visually distracting, so I built Verbatim — a minimalist Mac dictation app that stays out of your way.

1. First 30 Days

Week 1

* Validate domain
* Make landing page
* Build clickable demo or fake prototype
* Collect emails

Week 2

* Build hotkey/audio/transcription prototype
* Test local Whisper speed

Week 3

* Add system-wide paste
* Add tiny UI
* Test across common apps

Week 4

* Private beta with 20–50 users
* Fix latency, reliability, permissions
* Prepare launch post

Main Risk

The idea is not defensible on features. The edge is taste + execution:

* faster than clunky apps
* quieter than Wispr Flow
* simpler than Superwhisper
* cheaper than subscriptions
* private by default

That is the lane. Stick to it.
