# AirProDrop

[English](README.md) · **Bahasa Indonesia**

Kirim file antara Mac dan iPhone pakai gerakan, mirip AirDrop. Bedanya, file cukup dilempar ke tepi layar, lalu terlihat meluncur dari satu perangkat ke perangkat lain.

- Drag file ke tepi layar Mac, file langsung terbang ke iPhone.
- Tekan lama file di iPhone, lempar ke arah Mac, file langsung terbuka di Mac.
- Tepi layar yang menghadap perangkat lain menyala silver, lalu busur cahaya menyapu kedua layar saat file menyeberang.

Tidak perlu WiFi yang sama. Seperti AirDrop, AirProDrop tersambung langsung antar perangkat lewat WiFi peer-to-peer milik Apple (AWDL). Cukup WiFi dalam keadaan menyala.

## Fitur

- **Drop di tepi layar Mac:** app menu bar memantau tepi layar yang bersebelahan dengan iPhone. Lepas file di sana untuk mengirim.
- **Lempar untuk mengirim di iPhone:** tekan lama file, lalu lempar ke arah Mac.
- **Efek visual ala AirDrop:** glow di tepi layar, cahaya di bingkai layar yang menipis dari tengah ke ujung, busur silver yang menyapu layar, dan efek riak yang membengkokkan isi layar iPhone saat gelombang lewat.
- **Pairing sekali saja:** pilih Mac dari daftar Mac di sekitar, lalu masukkan kode 6 digit yang tampil di Mac, cukup sekali. Setelah itu kedua perangkat saling menemukan dan tersambung otomatis setiap kali app dibuka.
- **Terenkripsi dengan forward secrecy:** setiap koneksi memakai pertukaran kunci baru, jadi meskipun suatu kunci bocor, transfer sebelumnya tetap tidak bisa dibuka.
- **Banyak perangkat terpercaya:** bisa mempercayai beberapa iPhone atau Mac, dan melupakan salah satunya kapan saja.
- **File yang diterima:**
  - Mac: disimpan langsung ke `~/Downloads` seperti AirDrop, lalu otomatis dibuka.
  - iPhone: tampil di grid file di dalam app, bisa dipreview dengan Quick Look, dibagikan, atau dihapus.

## Kebutuhan

| | Minimal |
|---|---|
| Mac | macOS 14 Sonoma |
| iPhone | iOS 17 |
| Xcode | 16 atau lebih baru (dibangun dengan Xcode 26) |
| Tools | [XcodeGen](https://github.com/yonaskolb/XcodeGen), hanya jika mengubah `project.yml` |

WiFi harus menyala di kedua perangkat. Tidak harus tersambung ke jaringan yang sama.

## Cara memulai

### 1. Buka proyek

```bash
git clone https://github.com/Mr-Hafid/AirProDrop.git
cd AirProDrop
open AirProDrop.xcodeproj
```

Kalau mengubah `project.yml`, generate ulang proyeknya dulu:

```bash
brew install xcodegen
xcodegen generate
```

### 2. Jalankan app Mac

1. Pilih scheme **AirProDropMac** dan **My Mac**, lalu tekan **⌘R**.
2. Ikon iPhone muncul di menu bar. App ini tidak punya jendela; semuanya ada di menu bar.
3. Izinkan akses **Local Network** kalau macOS memintanya.

### 3. Jalankan app iPhone

1. Pilih target **AirProDropPhone** → **Signing & Capabilities** → pilih **Team** kamu.
2. Colokkan iPhone, pilih scheme **AirProDropPhone**, lalu tekan **⌘R**.
3. Izinkan akses **Local Network** saat iOS memintanya.

### 4. Pairing (cukup sekali)

1. Klik ikon di menu bar Mac. Saat pertama kali, kode pairing 6 digit langsung tampil; berikutnya klik **Pair New iPhone…** untuk memunculkannya. Setiap kode berlaku 2 menit.
2. Di iPhone, pilih Mac kamu dari **Nearby Macs**, lalu masukkan kodenya.
3. Titik status di app iPhone berubah hijau dengan nama Mac kamu. Mulai saat itu, keduanya tersambung otomatis setiap kali app iPhone dibuka.

Setelah 3 kali kode salah, Mac berhenti menerima perangkat baru sampai kamu klik **Pair New iPhone…** lagi.

### 5. Atur posisi iPhone

- **Mac:** menu bar → *iPhone sits on the* **Left / Right**
- **iPhone:** menu `⋯` → **Mac on the left / right**

Arah glow dan arah kirim mengikuti setting ini.

## Cara pakai

**Mac → iPhone**

Drag file dari Finder sampai ke ujung tepi layar di sisi iPhone. Tepi layar menyala dan layar iPhone meredup. Lepaskan untuk mengirim. Bisa juga lewat **Send Files…** di menu bar.

**iPhone → Mac**

Tambahkan file lewat tombol foto atau **Import from Files**. Tekan lama sebuah file sampai kartunya terangkat, lalu lempar ke arah Mac.

## Cara kerja

```
┌──────────────── Mac (app menu bar) ────────────────┐      ┌──────────── App iPhone ────────────┐
│ Strip drop di tepi ─┐                              │      │ Grid file ─ tekan lama + lempar    │
│                     ▼                              │      │              │                     │
│           MacCoordinator ── NWListener (Bonjour) ◄─┼─AWDL─┼─► NWBrowser ─ PhoneCoordinator     │
│                  │       X25519 + Ed25519          │      │              │                     │
│   Jendela overlay (glow, busur, kartu terbang)     │      │  Glow, busur, riak konten, kartu   │
└────────────────────────────────────────────────────┘      └────────────────────────────────────┘
```

- **Discovery & koneksi:** `Network.framework` dengan Bonjour (`_airpro._tcp`) dan `includePeerToPeer = true`. Opsi ini mengaktifkan AWDL, jalur WiFi peer-to-peer yang sama dengan yang dipakai AirDrop.
- **Identitas perangkat:** setiap perangkat membuat kunci identitas Ed25519 sendiri saat pertama kali dibuka (di Keychain pada iOS).
- **Pairing:** kedua perangkat bertukar kunci X25519 sementara, lalu kode 6 digit dicocokkan per bit dengan sistem komitmen (ide yang sama dengan pairing Bluetooth berkode). Penyusup hanya punya satu kali tebakan dengan peluang satu banding sejuta dan tidak bisa mencoba-coba kode secara offline. Setelah kode cocok, masing-masing menyimpan kunci identitas perangkat lain sebagai perangkat terpercaya.
- **Reconnect:** setiap koneksi menjalankan pertukaran kunci X25519 baru yang ditandatangani kunci identitas kedua perangkat. Perangkat yang menyamar sebagai Mac atau iPhone kamu akan ditolak, dan setiap sesi punya kunci sendiri (forward secrecy).
- **Enkripsi:** setiap frame dienkripsi dengan ChaCha20-Poly1305 lewat CryptoKit.
- **Protokol:** frame dengan panjang di depannya, berisi pesan kontrol JSON (hover, mulai transfer, pairing) dan potongan file 256 KB.
- **Visual:** shader Metal lewat `colorEffect` dan `layerEffect` di SwiftUI. Di iPhone, efek riak dijalankan pada snapshot layar, karena shader tidak bisa langsung dipakai pada view berbasis UIKit.

## Struktur proyek

```
project.yml                    Spesifikasi XcodeGen untuk kedua target
Shared/                        Kode yang dipakai kedua app
  PeerConnection.swift         Framing, pesan kontrol, transfer file per potongan
  TransportParameters.swift    NWParameters TCP dengan peer-to-peer aktif
  SecureHandshake.swift        Handshake pairing dan reconnect
  SessionCipher.swift          Enkripsi frame ChaCha20-Poly1305
  DeviceIdentity.swift         Kunci identitas tiap perangkat
  TrustStore.swift             Daftar perangkat terpercaya
  SecureStore.swift            Penyimpanan Keychain / UserDefaults
  ControlMessage.swift         Pesan yang dikirim antar perangkat
  TransferStage.swift          State glow dan animasi kartu terbang
  EdgeGlow.swift               View glow dan modifier riak konten
  AirDropGlow.metal            Shader glow, cahaya bingkai, busur, dan riak
  FlyingCard.swift             View kartu thumbnail
  ThumbnailRenderer.swift      Thumbnail Quick Look dan encoding
Mac/                           App menu bar, jendela overlay, target drop di tepi layar
Phone/                         App iPhone, library file, UI pairing, container snapshot
```

## Keterbatasan

- **App iPhone harus terbuka di layar.** iOS menghentikan app pihak ketiga di background, jadi tidak seperti AirDrop, AirProDrop tidak bisa menerima file saat app ditutup.
- **Strip drop di Mac hanya selebar 4 px.** Kalau monitor eksternal diletakkan di sisi yang sama dengan iPhone, kursor akan pindah ke monitor itu, bukan berhenti di tepi layar.
- **Di Mac hanya file dari Finder yang diterima.** Drag langsung dari app Photos atau browser (file promise) belum didukung.
- **Desktop Mac tidak ikut beriak.** Membengkokkan jendela app lain butuh izin Screen Recording, jadi di Mac hanya glow dan busur yang tampil tanpa mendistorsi isi di belakangnya.
- **Satu koneksi aktif per Mac.** Beberapa iPhone bisa dipercaya, tapi Mac hanya tersambung ke iPhone yang terakhir terhubung.
- **Di Mac, kunci disimpan di UserDefaults** karena build development di-sign ad hoc. Memindahkannya ke Keychain butuh Team signing yang proper.

## Lisensi

Belum ada lisensi. Semua hak dilindungi sampai lisensi ditambahkan.
