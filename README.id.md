# AirProDrop

[English](README.md) · **Bahasa Indonesia**

Kirim file antara Mac dan iPhone pakai gerakan, mirip AirDrop. Bedanya, file cukup dilempar ke tepi layar, lalu terlihat meluncur dari satu perangkat ke perangkat lain.

- Drag file ke tepi layar Mac, file langsung terbang ke iPhone.
- Tekan lama file di iPhone, lempar ke arah Mac, file langsung terbuka di Mac.
- Bagikan foto atau file dari app apa pun di iPhone, ketuk **AirProDrop**, lalu file terangkat dari layar dan terbang ke Mac.
- Tepi layar yang menghadap perangkat lain menyala silver, lalu busur cahaya menyapu kedua layar saat file menyeberang.

Tidak perlu WiFi yang sama. Seperti AirDrop, AirProDrop tersambung langsung antar perangkat lewat WiFi peer-to-peer milik Apple (AWDL). Cukup WiFi dalam keadaan menyala.

## Fitur

- **Drop di tepi layar Mac:** app menu bar memantau tepi layar yang bersebelahan dengan iPhone. Lepas file di sana untuk mengirim.
- **Lempar untuk mengirim di iPhone:** tekan lama file, lalu lempar ke arah Mac.
- **Kirim dari app mana pun:** Share Extension menaruh AirProDrop di lembar Share iOS. Ketuk, file mengambang di atas layar, terbang ke Mac, lalu lembarnya tertutup sendiri. Tanpa ketukan tambahan, dan app AirProDrop tidak perlu dibuka.
- **Efek visual ala AirDrop:** glow di tepi layar, cahaya di bingkai layar yang menipis dari tengah ke ujung, busur silver yang menyapu layar, dan efek riak yang membengkokkan isi layar iPhone saat gelombang lewat.
- **Pairing lewat radar:** iPhone menampilkan radar berdenyut berisi semua Mac di sekitar. Ketuk Mac kamu, kode 6 digit langsung muncul di layar Mac, lalu ketik di iPhone, cukup sekali. Setelah itu kedua perangkat saling menemukan dan tersambung otomatis.
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
| Tools | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) |
| Akun Apple Developer | Team berbayar, dibutuhkan untuk App Group yang dipakai bersama oleh app dan Share Extension |

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

### 2. Pakai Team signing sendiri

`project.yml` memakai Team milik maintainer. Kalau build dengan akun Apple Developer lain, ganti dengan Team ID kamu sebelum build:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: TEAM_ID_KAMU
```

Kalau bundle ID atau App Group (`group.com.mrhafid.airpro`) sudah dipakai orang lain, ganti di `project.yml`, bagian properti `.entitlements`, dan `Shared/SharedContainer.swift`. Setelah itu jalankan `xcodegen generate`.

### 3. Build dan install

Cara paling cepat lewat script build. Script ini meng-generate ulang proyek, memasang app Mac ke `/Applications`, dan meng-install app iPhone ke iPhone yang tercolok ke Mac:

```bash
./build.sh          # Mac dan iPhone
./build.sh mac      # hanya Mac → /Applications
./build.sh phone    # hanya iPhone → iPhone yang tercolok
./build.sh phone achmad   # pilih iPhone dari sebagian namanya
```

Sebelum install ke iPhone pertama kali, colok iPhone, ketuk **Trust This Computer**, lalu nyalakan **Settings → Privacy & Security → Developer Mode**.

Bisa juga lewat Xcode: pilih scheme **AirProDropMac** dengan **My Mac**, atau scheme **AirProDropPhone** dengan iPhone kamu, lalu tekan **⌘R**.

Saat pertama dibuka, izinkan akses **Local Network** di kedua perangkat, dan izinkan notifikasi di Mac. App Mac tidak punya jendela; ikon iPhone muncul di menu bar.

### 4. Pairing (cukup sekali)

1. Buka AirProDrop di iPhone. Radar muncul dan Mac kamu tampil di dalamnya.
2. Ketuk Mac kamu. Jendela kecil berisi kode 6 digit muncul di bagian atas layar Mac.
3. Ketik kodenya di iPhone. Titik status berubah hijau dengan nama Mac kamu, dan mulai saat itu keduanya tersambung otomatis.

Setiap kode berlaku 2 menit. Kalau kode salah, Mac langsung menampilkan kode baru. Setelah 3 kali salah, jendelanya ditutup dan Mac mengabaikan permintaan pairing selama 30 detik. Kode juga tetap bisa dimunculkan manual lewat **Pair New iPhone…** di menu bar.

Radar bisa ditutup dengan **✕** dan dibuka lagi lewat tombol **Nearby Macs** di tengah layar file yang masih kosong.

### 5. Atur posisi iPhone

- **Mac:** menu bar → *iPhone sits on the* **Left / Right**
- **iPhone:** menu `⋯` → **Mac on the left / right**

Arah glow dan arah kirim mengikuti setting ini.

## Cara pakai

**Mac → iPhone**

Drag file dari Finder sampai ke ujung tepi layar di sisi iPhone. Tepi layar menyala dan layar iPhone meredup. Lepaskan untuk mengirim. Bisa juga lewat **Send Files…** di menu bar.

**iPhone → Mac**

Tambahkan file lewat tombol foto atau **Import from Files**. Tekan lama sebuah file sampai kartunya terangkat, lalu lempar ke arah Mac.

**Dari app mana pun (Photos, Files, Safari, …)**

1. Ketuk **Share**, lalu pilih **AirProDrop** di baris app.
2. File mengambang di atas layar dan, begitu Mac tersambung, langsung terbang sendiri ke arah Mac. Bisa juga dilempar sendiri.
3. Lembar Share tertutup setelah file sampai.

Supaya AirProDrop berada tepat di sebelah AirDrop, geser baris app sampai ujung, ketuk **More → Edit**, lalu pindahkan AirProDrop ke paling depan. Bisa mengirim sampai 20 foto, video, atau file sekaligus.

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
- **Identitas perangkat:** setiap perangkat membuat kunci identitas Ed25519 sendiri saat pertama kali dibuka. Di iOS kunci ini disimpan di Keychain milik App Group, jadi app dan Share Extension-nya memakai identitas yang sama dan Share Extension tidak perlu pairing lagi.
- **Meminta kode:** mengetuk Mac di radar mengirim permintaan kode singkat. Mac membuka jendela pairing dan menampilkan kodenya, lalu iPhone melakukan pairing lewat koneksi baru dengan kode yang diketik.
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
  SharedContainer.swift        Penyimpanan App Group yang dipakai app iPhone dan extension-nya
  GlassStyles.swift            Gaya panel Liquid Glass dan transisi panel (iOS)
Mac/                           App menu bar, jendela overlay, target drop di tepi layar, jendela kode pairing
Phone/                         App iPhone, library file, UI pairing radar, container snapshot
ShareExtension/                Extension lembar Share untuk mengirim file langsung ke Mac
build.sh                       Build dan install app Mac dan iPhone
```

## Keterbatasan

- **App iPhone harus terbuka di layar.** iOS menghentikan app pihak ketiga di background, jadi tidak seperti AirDrop, AirProDrop tidak bisa menerima file saat app ditutup.
- **Strip drop di Mac hanya selebar 4 px.** Kalau monitor eksternal diletakkan di sisi yang sama dengan iPhone, kursor akan pindah ke monitor itu, bukan berhenti di tepi layar.
- **Di Mac hanya file dari Finder yang diterima.** Drag langsung dari app Photos atau browser (file promise) belum didukung.
- **Desktop Mac tidak ikut beriak.** Membengkokkan jendela app lain butuh izin Screen Recording, jadi di Mac hanya glow dan busur yang tampil tanpa mendistorsi isi di belakangnya.
- **Lembar Share harus tetap terbuka sampai file sampai.** iOS menghentikan Share Extension begitu ditutup, jadi AirProDrop baru menutupnya setelah transfer selesai. Untuk foto lewat AWDL, ini hanya butuh satu atau dua detik.
- **Tampilan Share yang transparan memakai perilaku yang tidak didokumentasikan Apple.** Berjalan di iOS 26, tapi versi iOS berikutnya bisa saja menampilkan lembar biasa. Pengiriman tetap jalan di kedua kondisi.
- **Satu koneksi aktif per Mac.** Beberapa iPhone bisa dipercaya, tapi Mac hanya tersambung ke iPhone yang terakhir terhubung.
- **App Mac di-sign ad hoc.** Kuncinya disimpan di UserDefaults, macOS bisa meminta izin notifikasi lagi setelah build ulang, dan Mac lain akan menampilkan peringatan "developer tidak terverifikasi". Sign dengan sertifikat Developer ID lalu notarisasi akan menyelesaikan ketiganya.

## Lisensi

Copyright (C) 2026 Achmad Hafid Supriyadi (Mr Hafid)

AirProDrop adalah perangkat lunak bebas: kamu boleh mendistribusikan ulang dan/atau mengubahnya sesuai ketentuan GNU General Public License yang diterbitkan Free Software Foundation, baik versi 3 maupun (sesuai pilihanmu) versi yang lebih baru.

AirProDrop didistribusikan dengan harapan bermanfaat, tetapi TANPA JAMINAN APA PUN, termasuk jaminan tersirat atas KELAYAKAN UNTUK DIPERDAGANGKAN atau KESESUAIAN UNTUK TUJUAN TERTENTU. Teks lengkapnya ada di file [LICENSE](LICENSE) (berbahasa Inggris, dan hanya versi itu yang berlaku secara hukum).

Kalau kamu mendistribusikan versi yang sudah diubah, source code-nya wajib dibuka dengan lisensi yang sama.
