# Aegixa

**Aegixa** is a Flutter-based personal safety app focused on fast SOS dispatch, live location sharing, emergency media capture, and in-app panic delivery.

## Features

- **SOS trigger flow** with hold-to-activate protection.
- **Live location sharing** to emergency contacts through Supabase-backed SOS sessions.
- **SOS inbox** so recipients can view incoming panic alerts, live map links, and saved media.
- **Voice and video evidence capture** during an SOS session.
- **Recipient media download** so received voice and video files can be saved locally and cleaned from remote storage afterward.
- **Panic notifications** with full-screen alerts, overlay support, and emergency sound.
- **FCM push delivery** for background and closed-app SOS notifications.
- **Emergency contact onboarding** with username-based in-app delivery.
- **Firebase Auth + Supabase** hybrid stack.
- **OEM battery guidance** for brands that aggressively restrict background delivery.

## Stack

- Flutter / Dart
- Firebase Auth
- Firebase Cloud Messaging
- Supabase Database, Storage, and Edge Functions
- Geolocator / Flutter Map

## Who It Is For

- **Individuals who want personal safety support** during travel, commutes, late-night movement, or unfamiliar environments.
- **Students and working professionals** who need a quick way to alert trusted contacts in an emergency.
- **Families and close groups** who want a private, app-based emergency network with live updates.
- **Anyone who prefers evidence-backed alerts** with audio/video capture attached to SOS sessions.

## How Aegixa Helps

- **One-touch emergency flow** with hold-to-activate safety to reduce accidental triggers.
- **Real-time location updates** so emergency contacts can track where help is needed.
- **Multi-channel panic delivery** using in-app alerts, full-screen panic UI, and push notifications.
- **Emergency evidence collection** through voice and video recording during active SOS sessions.
- **Recipient-first alert handling** with an SOS inbox, map links, and media download support.

## Why It Stands Out

- **Built for speed under pressure** with a clear SOS-first interaction model.
- **Works across background states** through Firebase Cloud Messaging and edge-powered push routing.
- **Practical device support** with OEM battery guidance for Android brands that restrict background behavior.
- **Optimized storage workflow** by letting recipients download media and then clean remote files.

## Important Notes

- Android devices from Xiaomi, Vivo, Oppo, Realme, Huawei, and similar OEMs may require battery optimization or autostart changes for reliable emergency alerts.
- The app includes an onboarding warning, a battery optimization shortcut, and an OEM-specific guide screen to help users configure this.
- SOS media is uploaded for recipients, then downloaded locally by recipients and cleaned up remotely to reduce Supabase storage usage.

## Project Structure

- `lib/screens` UI screens including home, onboarding, SOS inbox, battery guide, and recordings.
- `lib/services` services for SOS alerts, media handling, push notifications, and device settings.
- `supabase/functions/send-sos-push` Edge Function used to send FCM push notifications.
- `supabase_*.sql` database setup files.

Built for personal safety and rapid emergency response.
