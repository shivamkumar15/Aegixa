# Aegixa — Guardian Safety App

<p align="center">
  <img src="assets/Logo.png" alt="Aegixa Logo" width="120" height="120">
</p>

<p align="center">
  <b>Empowering personal safety through rapid SOS dispatch, live tracking, and evidence-backed emergency response.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white" alt="Supabase">
  <img src="https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" alt="Firebase">
</p>

---

## 🌟 Why Aegixa?

In critical moments, speed and reliability are everything. Traditional safety apps often fail because they require too many steps to activate or are silenced by aggressive battery management. 

**Aegixa** (from *Aegis*, the mythological shield) was designed as a "Guardian" that stays vigilant in the background. It is built for:
- **Speed Under Pressure**: A hold-to-activate flow that ensures SOS is triggered only when intended, but instantly.
- **Unstoppable Alerts**: Leveraging Android Overlays and Full-Screen Intents to ensure you see an alert even if your phone is locked or you're using another app.
- **Evidence That Matters**: Automatically capturing audio and video to provide a clear record of the emergency.

---

## 🚀 Overview

Aegixa is a high-performance personal safety application built with Flutter. It combines real-time location sharing with automated media evidence capture, providing a comprehensive safety net for individuals in vulnerable situations.

## ✨ Key Features

### 🚨 High-Priority SOS
- **Hold-to-Activate:** Prevents accidental triggers while allowing for rapid dispatch under stress.
- **System-Level Overlays:** On Android, incoming panic alerts trigger a modal that appears over any active application.
- **Full-Screen Intents:** Critical alerts wake the device and present a full-screen response UI.

### 📍 Real-Time "Guardian" Tracking
- **Live Location Sharing:** Continuous GPS updates shared via Supabase Realtime during active sessions.
- **Panic Inbox:** A centralized hub for recipients to manage multiple incoming alerts, view live maps, and access emergency media.

### 📁 Smart Evidence Management
- **Automated Media Capture:** Begins voice/video recording immediately upon SOS activation.
- **Privacy-First Cleanup:** Recipients download media locally to their devices; once confirmed, remote files are purged from Supabase to maintain user privacy.

---

## 🔬 Technical Deep Dive

### The SOS Lifecycle
1. **Trigger**: User holds the SOS button.
2. **Dispatch**: A Supabase Edge Function triggers FCM push notifications to all registered emergency contacts.
3. **Alerting**: Recipient devices receive a high-priority FCM message, triggering `PanicAlertService` which launches a system overlay and plays a looping alarm.
4. **Session**: The sender's device begins streaming location to a Supabase session table and starts local media recording.
5. **Resolution**: Once the session ends, media is uploaded. Recipients are notified to download evidence, and remote storage is optimized via automated cleanup.

### Background Reliability
Aegixa includes specialized **OEM Battery Guidance**. Since brands like Xiaomi and Oppo aggressively kill background services, Aegixa detects the device brand and provides the user with a direct shortcut to "Autostart" and "Battery Optimization" settings to ensure the "Guardian" remains active.

---

## 🛠️ Technical Stack

- **Frontend:** [Flutter](https://flutter.dev/) & [Dart](https://dart.dev/)
- **Authentication:** [Firebase Auth](https://firebase.google.com/docs/auth)
- **Database & Storage:** [Supabase](https://supabase.com/) (PostgreSQL + Realtime + Storage)
- **Push Notifications:** [Firebase Cloud Messaging (FCM)](https://firebase.google.com/docs/cloud-messaging)
- **Payments:** [RevenueCat](https://www.revenuecat.com/) for premium safety tiers.

## 📂 Project Structure

```bash
lib/
├── screens/    # UI for Home, SOS Inbox, Panic Overlays, etc.
├── services/   # SOS Logic, Panic Alerts (Overlays), Media, and Push.
├── utils/      # Auth validators and device helpers.
└── main.dart   # App entry point.
```

---

<p align="center">
  Built with ❤️ for a safer world.
</p>
