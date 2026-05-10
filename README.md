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

##Overview

**Aegixa** is a high-performance personal safety application built with Flutter. It focuses on critical, time-sensitive emergency flows, ensuring that help is just a single interaction away. By combining real-time location sharing with automated media evidence capture, Aegixa provides a comprehensive safety net for individuals in vulnerable situations.

##  Key Features

###  Emergency Response
- **One-Touch SOS:** Streamlined trigger flow with hold-to-activate protection to prevent accidental alerts.
- **Panic Inbox:** A dedicated space for recipients to view incoming panic alerts, access live map links, and review saved media.
- **Multi-Channel Delivery:** Uses FCM push notifications and full-screen panic UI to ensure alerts are noticed immediately.

###  Real-Time Tracking
- **Live Location Sharing:** Continuous location updates shared with emergency contacts via Supabase-backed SOS sessions.
- **Interactive Map:** Integrated Flutter Map for recipients to track the sender's movement in real-time.

###  Evidence Capture
- **Media Recording:** Automatic voice and video capture during active SOS sessions.
- **Optimized Storage:** Recipient-first media handling—recipients download files locally, followed by automated remote cleanup to maintain privacy and storage efficiency.

###  Reliability & Compatibility
- **Background Persistence:** Built for reliability across background states using Firebase Cloud Messaging.
- **OEM Battery Guidance:** Specialized support and in-app instructions for Android brands (Xiaomi, Vivo, Oppo, etc.) that aggressively restrict background processes.

##  Technical Stack

- **Frontend:** [Flutter](https://flutter.dev/) & [Dart](https://dart.dev/)
- **Authentication:** [Firebase Auth](https://firebase.google.com/docs/auth)
- **Database & Storage:** [Supabase](https://supabase.com/) (PostgreSQL + Storage)
- **Push Notifications:** [Firebase Cloud Messaging (FCM)](https://firebase.google.com/docs/cloud-messaging)
- **Edge Logic:** Supabase Edge Functions for notification routing.
- **Mapping:** [Geolocator](https://pub.dev/packages/geolocator) & [Flutter Map](https://pub.dev/packages/flutter_map)


<p align="center">
  Built with ❤️ for a safer world.
</p>

